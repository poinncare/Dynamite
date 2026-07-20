//
//  RateLimitService.swift
//  boringNotch — continuous rate-limit polling ported from Orca rate-limits/service.ts
//
//  Auto-refreshes without restart: 15 min default poll + faster cadence when Usage tab is active.
//

import AppKit
import Combine
import Foundation

@MainActor
final class RateLimitService: ObservableObject {
    static let shared = RateLimitService()

    @Published private(set) var state: RateLimitState = .empty
    @Published private(set) var isFetching = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastError: String?

    /// When true, poll more frequently (Usage tab open / notch open on usage).
    @Published var usageUIActive = false {
        didSet {
            if usageUIActive != oldValue {
                restartTimer()
                if usageUIActive {
                    Task { await refreshIfNeeded(force: false) }
                }
            }
        }
    }

    // Orca defaults
    private let defaultPollMs: TimeInterval = 15 * 60
    private let activePollMs: TimeInterval = 60 // keep UI fresh while looking at usage
    private let minRefetchMs: TimeInterval = 30
    private let staleThresholdMs: TimeInterval = 30 * 60

    private var pollTimer: Timer?
    private var currentToken: CancellationToken?
    private var lastFetchStartedAt: Date?
    private var started = false

    private init() {}

    func start(fetchImmediately: Bool = true) {
        guard !started else {
            if fetchImmediately {
                Task { await refresh(force: true) }
            }
            return
        }
        started = true
        if fetchImmediately {
            Task { await refresh(force: true) }
        } else {
            // Deferred startup — match Orca DEFERRED_STARTUP_ACTIVE_REFRESH_MS ~1s
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await refresh(force: true)
            }
        }
        restartTimer()

        // Resume / wake refresh
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(force: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshIfNeeded(force: false)
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        currentToken?.cancel()
        currentToken = nil
        started = false
    }

    func refresh(force: Bool = true) async {
        await refreshIfNeeded(force: force)
    }

    private func refreshIfNeeded(force: Bool) async {
        if isFetching {
            return
        }
        if !force, let last = lastFetchStartedAt,
           Date().timeIntervalSince(last) < minRefetchMs {
            return
        }

        isFetching = true
        lastFetchStartedAt = Date()
        let token = CancellationToken()
        currentToken = token

        // Mark known providers as fetching when we have prior data
        markFetching()

        // Network + file IO off the main actor — never block the notch UI.
        let (claudeResult, codexResult, grokResult, grokConfigured) = await Task.detached(priority: .utility) {
            async let claude = ClaudeUsageFetcher.fetch(signal: token)
            async let codex = CodexUsageFetcher.fetch(signal: token)
            async let grok = GrokUsageFetcher.fetch(signal: token)
            let c = await claude
            let x = await codex
            let g = await grok
            let configured = GrokUsageFetcher.isAuthConfigured()
            return (c, x, g, configured)
        }.value

        if token.isCancelled {
            isFetching = false
            return
        }

        // Keep last good snapshot on transient errors when we already have data (Orca stale policy).
        state = RateLimitState(
            claude: merge(previous: state.claude, next: claudeResult),
            codex: merge(previous: state.codex, next: codexResult),
            gemini: state.gemini,
            opencodeGo: state.opencodeGo,
            kimi: state.kimi,
            antigravity: state.antigravity,
            minimax: state.minimax,
            grok: merge(previous: state.grok, next: grokResult),
            grokAuthConfigured: grokConfigured,
            minimaxCookieConfigured: false
        )
        lastRefreshAt = Date()
        isFetching = false
        currentToken = nil

        let errors = [claudeResult, codexResult, grokResult]
            .filter { $0.status == .error }
            .compactMap(\.error)
        lastError = errors.first
    }

    private func merge(previous: ProviderRateLimits?, next: ProviderRateLimits) -> ProviderRateLimits {
        // Drop unavailable providers from UI unless we still hold a usable snapshot.
        if next.status == .unavailable {
            if let previous, previous.status == .ok,
               Date().timeIntervalSince1970 * 1000 - Double(previous.updatedAt) < staleThresholdMs * 1000 {
                return previous
            }
            return next
        }
        if next.status == .error {
            if let previous, previous.session != nil || previous.weekly != nil || previous.monthly != nil {
                var kept = previous
                kept.error = next.error
                kept.status = .error
                return kept
            }
        }
        return next
    }

    private func markFetching() {
        func mark(_ p: ProviderRateLimits?) -> ProviderRateLimits? {
            guard var p else { return nil }
            if p.status == .ok || p.status == .error {
                p.status = .fetching
            }
            return p
        }
        state = RateLimitState(
            claude: mark(state.claude),
            codex: mark(state.codex),
            gemini: mark(state.gemini),
            opencodeGo: mark(state.opencodeGo),
            kimi: mark(state.kimi),
            antigravity: mark(state.antigravity),
            minimax: mark(state.minimax),
            grok: mark(state.grok),
            grokAuthConfigured: state.grokAuthConfigured,
            minimaxCookieConfigured: state.minimaxCookieConfigured
        )
    }

    private func restartTimer() {
        pollTimer?.invalidate()
        let interval = usageUIActive ? activePollMs : defaultPollMs
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
