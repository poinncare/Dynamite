//
//  AgentDetector.swift
//  boringNotch — installed-agent detection ported from Orca
//  Sources:
//    - src/main/ipc/preflight.ts (detectInstalledAgents)
//    - src/main/ipc/tui-agent-detection-commands.ts
//    - src/main/ipc/local-agent-install-dir-detection.ts
//

import Foundation

struct DetectedAgent: Identifiable, Equatable, Sendable {
    var id: TuiAgentID
    var label: String
    var cmd: String
    var homepageUrl: String
    var isInstalled: Bool
}

struct AgentDetectionResult: Sendable {
    var installedIDs: [TuiAgentID]
    var agents: [DetectedAgent]
    var shellHydrationOk: Bool
    var pathFailureReason: String
    var detectedAt: Date
}

enum AgentDetector {
    /// Detect installed TUI agents on the local macOS host.
    /// Matches Orca `detectInstalledAgents` for darwin:
    /// 1) probe PATH for all detect/required commands
    /// 2) for misses, probe install dirs (nvm/volta/pnpm/homebrew/…)
    /// 3) resolve agent IDs with required-command + unsupported-runtime rules
    static func detectInstalledAgents(
        runtime: TuiAgentDetectionRuntime = .darwin
    ) -> [TuiAgentID] {
        let probeCommands = AgentCatalog.probeCommands(runtime: runtime)
        var found = Set<String>()

        for cmd in probeCommands {
            if CliCommandResolver.isCommandOnPath(cmd) {
                found.insert(cmd)
            }
        }

        let missed = probeCommands.filter { !found.contains($0) }
        // Why: PATH may still be unhydrated on a cold GUI launch; bulk resolution
        // computes user install dirs once instead of blocking once per missed CLI.
        let installDirCommands = CliCommandResolver.detectCommandsInInstallDirs(missed)
        found.formUnion(installDirCommands)

        return AgentCatalog.resolveDetectedAgentIDs(foundCommands: found, runtime: runtime)
    }

    /// Hydrate login-shell PATH, then detect. Used on startup and Settings refresh.
    /// Always runs filesystem probes off the main actor so the notch never freezes.
    static func detectWithShellPathHydration(forceHydrate: Bool = false) async -> AgentDetectionResult {
        let hydration = await ShellPathHydrator.hydrateShellPath(force: forceHydrate)
        return await Task.detached(priority: .utility) {
            let installed = detectInstalledAgents()
            let installedSet = Set(installed)
            let agents: [DetectedAgent] = AgentCatalog.catalog.map { entry in
                DetectedAgent(
                    id: entry.id,
                    label: entry.label,
                    cmd: entry.cmd,
                    homepageUrl: entry.homepageUrl,
                    isInstalled: installedSet.contains(entry.id)
                )
            }
            return AgentDetectionResult(
                installedIDs: installed,
                agents: agents,
                shellHydrationOk: hydration.ok,
                pathFailureReason: hydration.failureReason,
                detectedAt: Date()
            )
        }.value
    }
}
