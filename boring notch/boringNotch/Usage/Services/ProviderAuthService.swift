//
//  ProviderAuthService.swift
//  boringNotch — open CLI login for usage providers (no Keychain UI in-app).
//
//  Claude Code stores OAuth only in Keychain. The app never calls Security.framework
//  (that triggers the "TheBoringNotch wants Claude Code-credentials" dialog).
//  Instead Terminal (outside sandbox) exports the keychain blob to:
//    ~/.claude/.credentials.json
//    ~/Library/Application Support/boringNotch/UsageAuth/claude.credentials.json
//  which the app reads via home-relative sandbox exceptions.
//

import AppKit
import Foundation

enum ProviderAuthService {
    /// Real user home (not the app-sandbox container).
    static var realHomeDirectory: String { UsagePaths.realHome }

    static var pocketClaudeCredentialsPath: String { UsagePaths.pocketClaudeCredentialsFile }

    static var claudeLegacyCredentialsPath: String { UsagePaths.claudeCredentialsFile }

    /// Human-readable login command for a provider.
    static func loginCommand(for provider: UsageProviderID) -> String {
        switch provider {
        case .claude:
            return "claude auth login (+ export creds for Pocket)"
        case .codex:
            return "codex login"
        case .grok:
            return "grok login"
        case .gemini, .antigravity:
            return "gemini"
        case .kimi:
            return "kimi"
        case .opencodeGo:
            return "opencode"
        case .minimax:
            return "echo 'Paste MiniMax session cookie in Settings (Orca-style)'"
        }
    }

    /// Launch Terminal and run the provider's login CLI (+ Claude credential export).
    @discardableResult
    static func beginSignIn(for provider: UsageProviderID) -> Bool {
        let script = shellScript(for: provider, mode: .loginAndSync)
        return openInTerminal(command: script, title: "\(provider.displayName) login")
    }

    /// Already signed into Claude CLI — only export Keychain → file for Pocket (no re-login).
    @discardableResult
    static func syncClaudeCredentialsOnly() -> Bool {
        let script = shellScript(for: .claude, mode: .syncOnly)
        return openInTerminal(command: script, title: "Claude sync credentials")
    }

    /// Open provider docs / account page when CLI is not available.
    static func openAccountPage(for provider: UsageProviderID) {
        let urlString: String
        switch provider {
        case .claude:
            urlString = "https://claude.ai/settings"
        case .codex:
            urlString = "https://chatgpt.com"
        case .grok:
            urlString = "https://accounts.x.ai"
        case .gemini, .antigravity:
            urlString = "https://aistudio.google.com"
        case .kimi:
            urlString = "https://www.kimi.com"
        case .opencodeGo:
            urlString = "https://opencode.ai"
        case .minimax:
            urlString = "https://platform.minimax.io/console/usage"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Scripts

    private enum AuthMode {
        case loginAndSync
        case syncOnly
    }

    private static func shellScript(for provider: UsageProviderID, mode: AuthMode) -> String {
        let pathExtras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(realHomeDirectory)/.local/bin",
            "\(realHomeDirectory)/.grok/bin",
            "\(realHomeDirectory)/.volta/bin",
            "\(realHomeDirectory)/.bun/bin",
            "\(realHomeDirectory)/Library/pnpm"
        ]
        let exportPath = "export PATH=\"\(pathExtras.joined(separator: ":")):$PATH\""
        let home = realHomeDirectory

        switch provider {
        case .claude:
            return claudeScript(exportPath: exportPath, home: home, mode: mode)
        case .codex:
            return fileAuthLoginScript(
                exportPath: exportPath,
                home: home,
                command: "codex login",
                sourceFile: "\(home)/.codex/auth.json",
                pocketFile: "\(home)/Library/Application Support/boringNotch/UsageAuth/codex.auth.json",
                label: "Codex"
            )
        case .grok:
            return fileAuthLoginScript(
                exportPath: exportPath,
                home: home,
                command: "grok login",
                sourceFile: "\(home)/.grok/auth.json",
                pocketFile: "\(home)/Library/Application Support/boringNotch/UsageAuth/grok.auth.json",
                label: "Grok"
            )
        default:
            return genericLoginScript(
                exportPath: exportPath,
                command: loginCommand(for: provider),
                successHint: "Done."
            )
        }
    }

    private static func claudeScript(exportPath: String, home: String, mode: AuthMode) -> String {
        // Export runs in Terminal (not sandboxed) so `security` can read Claude Code keychain
        // items without TheBoringNotch ACL prompt. Writes files Pocket is allowed to read.
        let pocketDir = "\(home)/Library/Application Support/boringNotch/UsageAuth"
        let pocketFile = "\(pocketDir)/claude.credentials.json"
        let legacyFile = "\(home)/.claude/.credentials.json"

        let loginBlock: String
        switch mode {
        case .loginAndSync:
            loginBlock = """
            if claude auth status 2>/dev/null | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
              echo "Claude already signed in — exporting credentials for Pocket…"
            else
              echo "→ claude auth login"
              claude auth login
              login_status=$?
              if [ $login_status -ne 0 ]; then
                echo "Login exited with code $login_status"
              fi
            fi
            """
        case .syncOnly:
            loginBlock = """
            echo "Exporting existing Claude Keychain session for Pocket (no re-login)…"
            if ! claude auth status 2>/dev/null | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
              echo "Not signed in. Run Sign in first."
              exit 1
            fi
            """
        }

        return """
        clear
        \(exportPath)
        export HOME="\(home)"
        echo "Pocket — Claude auth bridge"
        echo ""
        \(loginBlock)
        echo ""
        echo "Exporting credentials to files Pocket can read…"
        mkdir -p "\(home)/.claude" "\(pocketDir)"

        export_ok=0
        # Claude Code stores under account "user" and/or $USER; try both + scoped service names.
        CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        if command -v shasum >/dev/null 2>&1; then
          SUFFIX=$(printf '%s' "$CONFIG_DIR" | shasum -a 256 | cut -c1-8)
        else
          SUFFIX=$(printf '%s' "$CONFIG_DIR" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-8)
        fi
        SERVICES=("Claude Code-credentials" "Claude Code-credentials-$SUFFIX")
        ACCOUNTS=("user" "$USER" "$(whoami)")

        for svc in "${SERVICES[@]}"; do
          for acct in "${ACCOUNTS[@]}"; do
            raw=$(security find-generic-password -s "$svc" -a "$acct" -w 2>/dev/null) || continue
            if [ -n "$raw" ]; then
              printf '%s' "$raw" > "\(legacyFile)"
              printf '%s' "$raw" > "\(pocketFile)"
              chmod 600 "\(legacyFile)" "\(pocketFile)" 2>/dev/null || true
              echo "✓ Exported from Keychain service '$svc' (account $acct)"
              echo "  → \(legacyFile)"
              echo "  → \(pocketFile)"
              export_ok=1
              break 2
            fi
          done
        done

        if [ $export_ok -eq 0 ]; then
          echo "✗ Could not read Claude Code credentials from Keychain."
          echo "  Try: claude auth login, then run this again."
          exit 2
        fi

        echo ""
        echo "Done. Return to Pocket — usage should refresh within a few seconds."
        echo "You can close this window."
        """
    }

    private static func genericLoginScript(exportPath: String, command: String, successHint: String) -> String {
        """
        clear
        echo "Pocket — signing in…"
        echo "→ \(command)"
        echo ""
        \(exportPath)
        \(command)
        status=$?
        echo ""
        if [ $status -eq 0 ]; then
          echo "Done. \(successHint)"
          echo "Return to Pocket; usage refreshes automatically."
        else
          echo "Login exited with code $status. You can retry or close this window."
        fi
        """
    }

    /// Codex / Grok: login then copy auth.json into Pocket UsageAuth for reliable sandbox reads.
    private static func fileAuthLoginScript(
        exportPath: String,
        home: String,
        command: String,
        sourceFile: String,
        pocketFile: String,
        label: String
    ) -> String {
        let pocketDir = "\(home)/Library/Application Support/boringNotch/UsageAuth"
        return """
        clear
        \(exportPath)
        export HOME="\(home)"
        echo "Pocket — \(label) auth"
        echo ""
        if [ -f "\(sourceFile)" ]; then
          echo "Existing \(label) session found — will refresh login if needed."
        fi
        echo "→ \(command)"
        \(command)
        status=$?
        echo ""
        mkdir -p "\(pocketDir)"
        if [ -f "\(sourceFile)" ]; then
          cp "\(sourceFile)" "\(pocketFile)"
          chmod 600 "\(pocketFile)" 2>/dev/null || true
          echo "✓ \(label) auth available:"
          echo "  → \(sourceFile)"
          echo "  → \(pocketFile)"
          echo ""
          echo "Done. Return to Pocket — usage should refresh within a few seconds."
          exit 0
        fi
        if [ $status -ne 0 ]; then
          echo "Login exited with code $status and no auth file was written."
        else
          echo "Login finished but \(sourceFile) was not found."
        fi
        exit 1
        """
    }

    // MARK: - Terminal launch

    private static func openInTerminal(command: String, title: String) -> Bool {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boringNotch-provider-auth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = title.replacingOccurrences(of: " ", with: "-")
        let scriptURL = dir.appendingPathComponent("\(safe).command")
        let body = "#!/bin/zsh\nset +e\n\(command)\n"
        do {
            try body.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            return openViaAppleScript(command: command)
        }

        let opened = NSWorkspace.shared.open(scriptURL)
        if opened { return true }
        return openViaAppleScript(command: command)
    }

    private static func openViaAppleScript(command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
}
