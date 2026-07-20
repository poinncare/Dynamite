//
//  AgentDetectionService.swift
//  boringNotch — continuous agent detection (no restart required)
//

import Combine
import Foundation

@MainActor
final class AgentDetectionService: ObservableObject {
    static let shared = AgentDetectionService()

    @Published private(set) var result: AgentDetectionResult?
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanAt: Date?

    private var pollTimer: Timer?
    private var started = false
    /// Re-scan installed agents periodically so new installs appear without restart.
    private let pollInterval: TimeInterval = 5 * 60

    private init() {}

    var installedAgents: [DetectedAgent] {
        result?.agents.filter(\.isInstalled) ?? []
    }

    var allAgents: [DetectedAgent] {
        result?.agents ?? AgentCatalog.catalog.map {
            DetectedAgent(
                id: $0.id,
                label: $0.label,
                cmd: $0.cmd,
                homepageUrl: $0.homepageUrl,
                isInstalled: false
            )
        }
    }

    func start(scanImmediately: Bool = true) {
        guard !started else {
            if scanImmediately { Task { await scan(forceHydrate: false) } }
            return
        }
        started = true
        if scanImmediately {
            Task { await scan(forceHydrate: true) }
        }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scan(forceHydrate: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        started = false
    }

    /// Manual refresh from Settings (forces login-shell PATH rehydration).
    func refresh() async {
        await scan(forceHydrate: true)
    }

    func scan(forceHydrate: Bool) async {
        if isScanning { return }
        isScanning = true
        let detection = await AgentDetector.detectWithShellPathHydration(forceHydrate: forceHydrate)
        result = detection
        lastScanAt = detection.detectedAt
        isScanning = false
    }
}
