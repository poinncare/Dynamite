//
//  ShellPathHydrator.swift
//  boringNotch — hydrate PATH from the user's login shell (GUI apps inherit a sparse PATH).
//  Ported from Orca hydrateShellPath / agent-detection-shell-path.
//

import Foundation

struct ShellPathHydrationResult: Sendable {
    var ok: Bool
    var segments: [String]
    var failureReason: String
}

enum ShellPathHydrator {
    /// Hard cap so a slow/broken login shell cannot freeze detection forever.
    private static let hydrateTimeoutSeconds: TimeInterval = 2.5

    /// Spawn the user's login shell and capture PATH.
    static func hydrateShellPath(force: Bool = false) async -> ShellPathHydrationResult {
        // Cache unless force-refresh (Settings → Refresh agents).
        if !force, let cached = cache {
            return cached
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<ShellPathHydrationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                // Non-interactive login shell; avoid full interactive rc that can hang.
                process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                process.standardInput = FileHandle.nullDevice

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                // Skip interactive-only init that can block GUI hydration.
                env["ZDOTDIR"] = env["ZDOTDIR"] ?? NSHomeDirectory()
                process.environment = env

                let lock = NSLock()
                var resumed = false
                func finish(_ value: ShellPathHydrationResult) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }

                do {
                    try process.run()
                    // Timeout watchdog
                    DispatchQueue.global().asyncAfter(deadline: .now() + hydrateTimeoutSeconds) {
                        if process.isRunning {
                            process.terminate()
                            finish(ShellPathHydrationResult(
                                ok: false,
                                segments: [],
                                failureReason: "timeout"
                            ))
                        }
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if process.terminationStatus == 0, !path.isEmpty {
                        let segments = path
                            .split(separator: ":")
                            .map(String.init)
                            .filter { !$0.isEmpty }
                        finish(ShellPathHydrationResult(
                            ok: true,
                            segments: segments,
                            failureReason: "none"
                        ))
                    } else {
                        finish(ShellPathHydrationResult(
                            ok: false,
                            segments: [],
                            failureReason: "shell_exit_\(process.terminationStatus)"
                        ))
                    }
                } catch {
                    finish(ShellPathHydrationResult(
                        ok: false,
                        segments: [],
                        failureReason: "spawn_failed"
                    ))
                }
            }
        }

        if result.ok {
            cache = result
            mergePathSegments(result.segments)
        } else if !force {
            // Remember failures briefly so tab open doesn't re-spawn a hanging shell.
            cache = result
        }
        return result
    }

    /// Merge new PATH segments into the current process environment.
    @discardableResult
    static func mergePathSegments(_ segments: [String]) -> [String] {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var existing = Set(current.split(separator: ":").map(String.init))
        var added: [String] = []
        var ordered = current.isEmpty ? [String]() : current.split(separator: ":").map(String.init)

        for segment in segments where !segment.isEmpty {
            if existing.insert(segment).inserted {
                ordered.append(segment)
                added.append(segment)
            }
        }

        if !added.isEmpty {
            setenv("PATH", ordered.joined(separator: ":"), 1)
        }
        return added
    }

    private static var cache: ShellPathHydrationResult?
}
