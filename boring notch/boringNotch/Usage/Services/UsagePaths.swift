//
//  UsagePaths.swift
//  boringNotch — real-user paths for auth files (sandbox-safe)
//
//  App Sandbox makes NSHomeDirectory() point at the container, not the user's
//  real home. CLI tools write to ~/.codex, ~/.grok, ~/.claude on the real home.
//  Always resolve via getpwuid + home-relative sandbox exceptions.
//

import Foundation

enum UsagePaths {
    /// Real user home directory (e.g. /Users/name), never the sandbox container.
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        // Fallback: HOME may still be container under sandbox — try unsetting
        if let home = ProcessInfo.processInfo.environment["HOME"], home.contains("/Users/") {
            return home
        }
        return NSHomeDirectory()
    }

    static func underHome(_ components: String...) -> String {
        components.reduce(realHome) { ($0 as NSString).appendingPathComponent($1) }
    }

    // MARK: Claude
    static var claudeConfigDir: String {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        return underHome(".claude")
    }

    static var claudeCredentialsFile: String {
        (claudeConfigDir as NSString).appendingPathComponent(".credentials.json")
    }

    static var pocketClaudeCredentialsFile: String {
        underHome("Library", "Application Support", "boringNotch", "UsageAuth", "claude.credentials.json")
    }

    // MARK: Codex
    static var codexHome: String {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        return underHome(".codex")
    }

    static var codexAuthFile: String {
        (codexHome as NSString).appendingPathComponent("auth.json")
    }

    static var pocketCodexAuthFile: String {
        underHome("Library", "Application Support", "boringNotch", "UsageAuth", "codex.auth.json")
    }

    // MARK: Grok
    static var grokHome: String {
        if let env = ProcessInfo.processInfo.environment["GROK_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        return underHome(".grok")
    }

    static var grokAuthFile: String {
        (grokHome as NSString).appendingPathComponent("auth.json")
    }

    static var pocketGrokAuthFile: String {
        underHome("Library", "Application Support", "boringNotch", "UsageAuth", "grok.auth.json")
    }

    /// Read first existing file among candidates.
    static func firstExistingData(among paths: [String]) -> (Data, String)? {
        let fm = FileManager.default
        for path in paths {
            if fm.fileExists(atPath: path),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               !data.isEmpty {
                return (data, path)
            }
        }
        return nil
    }
}
