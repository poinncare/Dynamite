//
//  GrokUsageFetcher.swift
//  boringNotch — Grok billing/usage ported from Orca rate-limits/grok-fetcher.ts + grok-auth.ts
//

import Foundation

enum GrokUsageFetcher {
    private static let preferredIssuer = "https://auth.x.ai"
    private static let billingCreditsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let billingDefaultURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!
    private static let apiTimeout: TimeInterval = 15
    private static let weeklyMinutes = 10_080
    private static let monthlyMinutes = 43_200
    private static let authHeader = "xai-grok-cli"

    struct GrokAuthSession {
        var accessToken: String
        var userId: String?
        var email: String?
        var teamId: String?
        var expiresAtMs: Int64?
        var sourcePath: String
    }

    enum AuthRead {
        case missing
        case error(String)
        case ok(GrokAuthSession)
    }

    static func readAuthSession() -> AuthRead {
        let candidates = [
            UsagePaths.grokAuthFile,
            UsagePaths.pocketGrokAuthFile
        ]
        guard let (data, path) = UsagePaths.firstExistingData(among: candidates) else {
            return .missing
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .error("Grok auth file is invalid")
        }

        var preferred: GrokAuthSession?
        var fallback: GrokAuthSession?
        var expiredPreferred: GrokAuthSession?

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        for (key, value) in json {
            guard let entry = value as? [String: Any],
                  let token = entry["key"] as? String,
                  !token.isEmpty else { continue }
            let session = GrokAuthSession(
                accessToken: token,
                userId: entry["user_id"] as? String,
                email: entry["email"] as? String,
                teamId: entry["team_id"] as? String,
                expiresAtMs: RateLimitFormatting.parseResetTimestamp(entry["expires_at"]),
                sourcePath: path
            )
            let isPreferred = key == preferredIssuer || key.hasPrefix("\(preferredIssuer)::")
            let isFresh = session.expiresAtMs.map { $0 > now } ?? true

            if isPreferred {
                if isFresh {
                    if preferred == nil { preferred = session }
                } else if expiredPreferred == nil {
                    expiredPreferred = session
                }
            } else if isFresh {
                if fallback == nil { fallback = session }
            } else if fallback == nil {
                fallback = session // keep as last resort; API may still accept
            }
        }

        // Prefer fresh preferred → fresh fallback → expired preferred (API may still work / refresh).
        if let preferred { return .ok(preferred) }
        if let fallback { return .ok(fallback) }
        if let expiredPreferred { return .ok(expiredPreferred) }
        return .error("Grok auth file is invalid")
    }

    static func isAuthConfigured() -> Bool {
        if case .ok = readAuthSession() { return true }
        // File present even if parse fails counts as configured for UI.
        return FileManager.default.fileExists(atPath: UsagePaths.grokAuthFile)
            || FileManager.default.fileExists(atPath: UsagePaths.pocketGrokAuthFile)
    }

    static func fetch(signal: CancellationToken? = nil) async -> ProviderRateLimits {
        if signal?.isCancelled == true {
            return .placeholder(provider: .grok, status: .error, error: "Rate-limit fetch aborted")
        }

        switch readAuthSession() {
        case .missing:
            return .placeholder(provider: .grok, status: .unavailable, error: "Not signed in to Grok — use Sign in")
        case .error(let message):
            return .placeholder(provider: .grok, status: .error, error: message)
        case .ok(let session):
            // Why: do NOT hard-fail on expires_at alone — Grok tokens often still work
            // (or refresh server-side) past local metadata. Only treat 401 as expired.
            return await fetchBilling(session: session, signal: signal)
        }
    }

    private static func fetchBilling(session: GrokAuthSession, signal: CancellationToken?) async -> ProviderRateLimits {
        do {
            let creditsData = try await getJSON(url: billingCreditsURL, session: session)
            if signal?.isCancelled == true {
                return .placeholder(provider: .grok, status: .error, error: "Rate-limit fetch aborted")
            }
            let config = resolveBillingConfig(creditsData)
            let weekly = mapWeeklyCredits(config)
            var monthly = mapMonthlyUsage(config)

            if monthly == nil {
                if let defaultData = try? await getJSON(url: billingDefaultURL, session: session) {
                    monthly = mapMonthlyUsage(resolveBillingConfig(defaultData))
                }
            }

            // If both windows missing, still show ok only if we got a config — else error.
            if weekly == nil && monthly == nil {
                return .placeholder(
                    provider: .grok,
                    status: .error,
                    error: "Grok billing returned no usage windows"
                )
            }

            let tier = (config["subscriptionTier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let authLabel = session.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? session.userId
                ?? "Grok account"
            let provenance = (tier?.isEmpty == false) ? "\(authLabel) (\(tier!))" : authLabel

            var meta = UsageRateLimitMetadata()
            meta.source = .oauth
            meta.authProvenance = provenance
            meta.credentialSource = session.sourcePath

            return ProviderRateLimits(
                provider: .grok,
                session: nil,
                weekly: weekly,
                fableWeekly: nil,
                monthly: monthly,
                buckets: nil,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                error: nil,
                status: .ok,
                usageMetadata: meta
            )
        } catch let err as NSError where err.domain == "GrokUsage" && (err.code == 401 || err.code == 403) {
            return .placeholder(
                provider: .grok,
                status: .error,
                error: "Grok sign-in expired — use Sign in"
            )
        } catch {
            return .placeholder(provider: .grok, status: .error, error: error.localizedDescription)
        }
    }

    private static func getJSON(url: URL, session: GrokAuthSession) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: apiTimeout)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authHeader, forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let userId = session.userId {
            request.setValue(userId, forHTTPHeaderField: "x-userid")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw NSError(
                domain: "GrokUsage",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Grok usage request failed (HTTP \(http.statusCode))"]
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func resolveBillingConfig(_ data: [String: Any]) -> [String: Any] {
        if let config = data["config"] as? [String: Any] {
            return config
        }
        return data
    }

    private static func mapWeeklyCredits(_ config: [String: Any]) -> RateLimitWindow? {
        let used: Double?
        if let p = config["creditUsagePercent"] as? Double { used = p }
        else if let p = config["creditUsagePercent"] as? Int { used = Double(p) }
        else if let p = config["creditUsagePercent"] as? NSNumber { used = p.doubleValue }
        else { used = nil }
        guard let usedPercent = used, usedPercent.isFinite else { return nil }

        let period = config["currentPeriod"] as? [String: Any]
        let periodEnd = (period?["end"] as? String) ?? (config["billingPeriodEnd"] as? String)
        let resetsAt = RateLimitFormatting.parseResetTimestamp(periodEnd)
        return RateLimitWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowMinutes: weeklyMinutes,
            resetsAt: resetsAt,
            resetDescription: RateLimitFormatting.resetDescription(fromMs: resetsAt)
        )
    }

    private static func mapMonthlyUsage(_ config: [String: Any]) -> RateLimitWindow? {
        guard let limit = parseMoneyVal(config["monthlyLimit"] as? [String: Any]),
              let used = parseMoneyVal(config["used"] as? [String: Any]),
              limit > 0 else {
            return nil
        }
        let period = config["currentPeriod"] as? [String: Any]
        let periodEnd = (period?["end"] as? String) ?? (config["billingPeriodEnd"] as? String)
        let resetsAt = RateLimitFormatting.parseResetTimestamp(periodEnd)
        return RateLimitWindow(
            usedPercent: min(100, max(0, (used / limit) * 100)),
            windowMinutes: monthlyMinutes,
            resetsAt: resetsAt,
            resetDescription: RateLimitFormatting.resetDescription(fromMs: resetsAt)
        )
    }

    private static func parseMoneyVal(_ value: [String: Any]?) -> Double? {
        guard let value else { return nil }
        if let n = value["val"] as? Double { return n }
        if let n = value["val"] as? Int { return Double(n) }
        if let n = value["val"] as? NSNumber { return n.doubleValue }
        if let s = value["val"] as? String, let n = Double(s) { return n }
        return nil
    }
}
