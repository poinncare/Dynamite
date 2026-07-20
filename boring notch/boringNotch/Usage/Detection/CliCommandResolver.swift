//
//  CliCommandResolver.swift
//  boringNotch — ported from Orca src/main/codex-cli/command.ts
//  Resolves CLI binaries on PATH and common install / version-manager dirs.
//

import Foundation

enum CliCommandResolver {
    /// Resolve a single CLI name to an absolute path when found, else the original name.
    static func resolveCliCommand(
        _ commandName: String,
        pathEnv: String? = ProcessInfo.processInfo.environment["PATH"],
        homePath: String = NSHomeDirectory()
    ) -> String {
        let pathDirectories = splitPath(pathEnv)
        if let candidate = findFirstExecutable(directories: pathDirectories, commandName: commandName) {
            return candidate
        }
        let installDirectories = installDirectories(homePath: homePath)
        if let candidate = findFirstExecutable(directories: installDirectories, commandName: commandName) {
            return candidate
        }
        return commandName
    }

    /// Bulk-resolve many commands once (agent detection probes many CLIs per pass).
    static func resolveCliCommands(
        _ commandNames: [String],
        pathEnv: String? = ProcessInfo.processInfo.environment["PATH"],
        homePath: String = NSHomeDirectory()
    ) -> [String: String] {
        let pathDirectories = splitPath(pathEnv)
        let installDirectories = installDirectories(homePath: homePath)
        var resolved: [String: String] = [:]
        for commandName in Set(commandNames) {
            if let pathCandidate = findFirstExecutable(directories: pathDirectories, commandName: commandName) {
                resolved[commandName] = pathCandidate
            } else if let installCandidate = findFirstExecutable(directories: installDirectories, commandName: commandName) {
                resolved[commandName] = installCandidate
            } else {
                resolved[commandName] = commandName
            }
        }
        return resolved
    }

    /// Commands found in install dirs (absolute path) among the given list.
    /// Mirrors `detectCommandsInInstallDirs` in Orca.
    static func detectCommandsInInstallDirs(_ commands: [String]) -> Set<String> {
        guard !commands.isEmpty else { return [] }
        let resolved = resolveCliCommands(commands)
        return Set(commands.filter { path in
            let value = resolved[path] ?? path
            return value.hasPrefix("/")
        })
    }

    static func isCommandOnPath(
        _ commandName: String,
        pathEnv: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> Bool {
        findFirstExecutable(directories: splitPath(pathEnv), commandName: commandName) != nil
    }

    // MARK: - Internals

    private static func splitPath(_ pathEnv: String?) -> [String] {
        guard let pathEnv, !pathEnv.isEmpty else { return [] }
        return pathEnv
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func findFirstExecutable(directories: [String], commandName: String) -> String? {
        let fm = FileManager.default
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(commandName)
            if isRunnableCommand(candidate, fileManager: fm) {
                return candidate
            }
        }
        return nil
    }

    private static func isRunnableCommand(_ candidate: String, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: candidate)
    }

    /// Base version-manager + package-manager bin directories (macOS / darwin).
    private static func baseVersionManagerDirectories(homePath: String) -> [String] {
        [
            (homePath as NSString).appendingPathComponent(".volta/bin"),
            (homePath as NSString).appendingPathComponent(".asdf/shims"),
            (homePath as NSString).appendingPathComponent(".fnm/aliases/default/bin"),
            (homePath as NSString).appendingPathComponent(".local/share/mise/shims"),
            (homePath as NSString).appendingPathComponent(".local/bin"),
            (homePath as NSString).appendingPathComponent("Library/pnpm"),
            (homePath as NSString).appendingPathComponent(".yarn/bin"),
            (homePath as NSString).appendingPathComponent(".bun/bin"),
            // Common Homebrew / system paths for GUI apps with sparse PATH
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ]
    }

    private static func nvmVersionDirectories(homePath: String) -> [String] {
        let nvmVersionsDir = (homePath as NSString).appendingPathComponent(".nvm/versions/node")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) else {
            return []
        }
        return entries
            .sorted(by: compareVersionDesc)
            .map { (nvmVersionsDir as NSString).appendingPathComponent("\($0)/bin") }
    }

    private static func installDirectories(homePath: String) -> [String] {
        nvmVersionDirectories(homePath: homePath) + baseVersionManagerDirectories(homePath: homePath)
    }

    private static func compareVersionDesc(_ left: String, _ right: String) -> Bool {
        let leftParts = parseVersionSegment(left)
        let rightParts = parseVersionSegment(right)
        let length = max(leftParts.count, rightParts.count)
        for index in 0..<length {
            let l = index < leftParts.count ? leftParts[index] : 0
            let r = index < rightParts.count ? rightParts[index] : 0
            if r != l { return r < l } // descending
        }
        return right > left
    }

    private static func parseVersionSegment(_ raw: String) -> [Int] {
        var s = raw
        if s.lowercased().hasPrefix("v") {
            s = String(s.dropFirst())
        }
        return s.split(separator: ".").map { Int($0) ?? 0 }
    }
}
