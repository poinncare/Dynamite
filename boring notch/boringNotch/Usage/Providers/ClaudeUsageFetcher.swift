//
//  ClaudeUsageFetcher.swift
//  boringNotch — Claude OAuth usage from exported credential *files* only.
//  Ported from Orca rate-limits/claude-fetcher.ts (OAuth path).
//
//  Never uses Security.framework / SecItem (that shows TheBoringNotch keychain UI).
//  After `claude auth login`, ProviderAuthService exports Keychain →:
//    ~/.claude/.credentials.json
//    ~/Library/Application Support/boringNotch/UsageAuth/claude.credentials.json
//

import Foundation

enum ClaudeUsageFetcher {
    private static let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthBetaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.0"
    private static let apiTimeout: TimeInterval = 10

    static func fetch(signal: CancellationToken? = nil) async -> ProviderRateLimits {
        if signal?.isCancelled == true {
            return .placeholder(provider: .claude, status: .error, error: "Rate-limit fetch aborted")
        }

        let creds = readFromCredentialsFile()
        guard let token = creds.token else {
            if creds.hasRefreshableCredentials {
                return .placeholder(
                    provider: .claude,
                    status: .error,
                    error: "Claude credentials need refresh — use Sign in"
                )
            }
            return .placeholder(
                provider: .claude,
                status: .unavailable,
                error: "Not signed in — use Sign in (exports Claude session for Pocket)"
            )
        }

        do {
            var request = URLRequest(url: oauthUsageURL, timeoutInterval: apiTimeout)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            if signal?.isCancelled == true {
                return .placeholder(provider: .claude, status: .error, error: "Rate-limit fetch aborted")
            }
            guard let http = response as? HTTPURLResponse else {
                return .placeholder(provider: .claude, status: .error, error: "Invalid response")
            }
            guard http.statusCode == 200 else {
                return .placeholder(
                    provider: .claude,
                    status: .error,
                    error: "Claude usage request failed (HTTP \(http.statusCode))"
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .placeholder(provider: .claude, status: .error, error: "Failed to parse Claude usage")
            }

            let session = mapWindow(json["five_hour"] as? [String: Any], windowMinutes: 300)
            let weekly = mapWindow(json["seven_day"] as? [String: Any], windowMinutes: 10_080)
            let fable = mapFableWeeklyWindow(json)

            var meta = UsageRateLimitMetadata()
            meta.source = .oauth
            meta.credentialSource = creds.source
            meta.attemptedSources = [.oauth]

            return ProviderRateLimits(
                provider: .claude,
                session: session,
                weekly: weekly,
                fableWeekly: fable,
                monthly: nil,
                buckets: nil,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                error: nil,
                status: .ok,
                usageMetadata: meta
            )
        } catch {
            if signal?.isCancelled == true {
                return .placeholder(provider: .claude, status: .error, error: "Rate-limit fetch aborted")
            }
            return .placeholder(
                provider: .claude,
                status: .error,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Window mapping

    private static func mapWindow(_ raw: [String: Any]?, windowMinutes: Int) -> RateLimitWindow? {
        guard let raw else { return nil }
        let used: Double?
        if let u = raw["utilization"] as? Double {
            used = u
        } else if let u = raw["utilization"] as? Int {
            used = Double(u)
        } else if let u = raw["used_percentage"] as? Double {
            used = u
        } else if let u = raw["used_percentage"] as? Int {
            used = Double(u)
        } else {
            used = nil
        }
        guard let usedPercent = used else { return nil }
        let resetsAt = RateLimitFormatting.parseResetTimestamp(raw["resets_at"])
        return RateLimitWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt,
            resetDescription: RateLimitFormatting.resetDescription(fromMs: resetsAt)
        )
    }

    private static func mapFableWeeklyWindow(_ data: [String: Any]) -> RateLimitWindow? {
        if let limits = data["limits"] as? [[String: Any]] {
            let fable = limits.first { limit in
                guard (limit["kind"] as? String) == "weekly_scoped" else { return false }
                let hasPercent = limit["percent"] is Double || limit["percent"] is Int
                guard hasPercent else { return false }
                let scope = limit["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let name = (model?["display_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return name == "fable"
            }
            if let fable {
                let percent: Double
                if let p = fable["percent"] as? Double { percent = p }
                else if let p = fable["percent"] as? Int { percent = Double(p) }
                else { percent = 0 }
                let resetsAt = RateLimitFormatting.parseResetTimestamp(fable["resets_at"])
                return RateLimitWindow(
                    usedPercent: min(100, max(0, percent)),
                    windowMinutes: 10_080,
                    resetsAt: resetsAt,
                    resetDescription: RateLimitFormatting.resetDescription(fromMs: resetsAt)
                )
            }
        }
        return mapWindow(data["fable_weekly"] as? [String: Any], windowMinutes: 10_080)
            ?? mapWindow(data["fable_seven_day"] as? [String: Any], windowMinutes: 10_080)
            ?? mapWindow(data["seven_day_fable"] as? [String: Any], windowMinutes: 10_080)
    }

    // MARK: - Credentials (files only — never Keychain from this process)

    private struct OAuthCredResult {
        var token: String?
        var hasRefreshableCredentials: Bool
        var source: String
    }

    private static func readFromCredentialsFile() -> OAuthCredResult {
        for path in credentialsFileCandidates() {
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let parsed = parseOAuthCredentialsJSON(raw, source: path)
            if parsed.token != nil || parsed.hasRefreshableCredentials {
                return parsed
            }
        }
        return OAuthCredResult(token: nil, hasRefreshableCredentials: false, source: "none")
    }

    private static func credentialsFileCandidates() -> [String] {
        var paths: [String] = [
            UsagePaths.pocketClaudeCredentialsFile,
            UsagePaths.claudeCredentialsFile
        ]
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            paths.append((env as NSString).appendingPathComponent(".credentials.json"))
        }
        paths.append(UsagePaths.underHome("Library", "Application Support", "Claude", ".credentials.json"))
        return paths
    }

    private static func parseOAuthCredentialsJSON(_ raw: String, source: String) -> OAuthCredResult {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OAuthCredResult(token: nil, hasRefreshableCredentials: false, source: "none")
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any])
            ?? (json["claude_ai_oauth"] as? [String: Any])
        let token = (oauth?["accessToken"] as? String) ?? (oauth?["access_token"] as? String)
        let refresh = (oauth?["refreshToken"] as? String) ?? (oauth?["refresh_token"] as? String)
        let hasRefresh = (refresh?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if let token, !token.isEmpty {
            return OAuthCredResult(token: token, hasRefreshableCredentials: hasRefresh, source: source)
        }
        return OAuthCredResult(token: nil, hasRefreshableCredentials: hasRefresh, source: source)
    }
}

/// Simple cancellation flag for fetch cycles.
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
}
