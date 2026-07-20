//
//  AgentCatalog.swift
//  boringNotch — agent catalog + detection config ported from Orca
//  Sources:
//    - src/shared/tui-agent-config.ts (TUI_AGENT_CONFIG)
//    - src/renderer/src/lib/agent-catalog.tsx (labels / homepage)
//    - src/main/ipc/tui-agent-detection-commands.ts
//

import Foundation

/// Agent identity IDs matching Orca's `TuiAgent` union.
enum TuiAgentID: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case claudeAgentTeams = "claude-agent-teams"
    case openclaude
    case codex
    case autohand
    case ante
    case opencode
    case mimoCode = "mimo-code"
    case pi
    case omp
    case gemini
    case antigravity
    case aider
    case goose
    case amp
    case kilo
    case kiro
    case crush
    case aug
    case cline
    case codebuff
    case commandCode = "command-code"
    case continueAgent = "continue"
    case cursor
    case droid
    case kimi
    case mistralVibe = "mistral-vibe"
    case qwenCode = "qwen-code"
    case rovo
    case hermes
    case openclaw
    case copilot
    case grok
    case devin

    var id: String { rawValue }
}

enum TuiAgentDetectionRuntime: String, Sendable {
    case darwin
    case linux
    case win32
    case wsl
}

struct TuiAgentConfig: Sendable {
    /// Primary executable name used for PATH detection.
    var detectCmd: String
    /// Additional executable names that identify the same agent on PATH.
    var detectCmdAliases: [String]
    /// Other commands that must also be present before this agent counts as installed.
    var detectRequiredCommands: [String]
    /// Detection runtimes where this launch mode is not available as a detected agent.
    var detectUnsupportedRuntimes: [TuiAgentDetectionRuntime]
    var launchCmd: String
    var expectedProcess: String

    var allDetectCommands: [String] {
        [detectCmd] + detectCmdAliases
    }
}

struct TuiAgentDetectionCommand: Sendable {
    var id: TuiAgentID
    var cmd: String
    var requiredCommands: [String]
    var unsupportedRuntimes: [TuiAgentDetectionRuntime]
}

struct AgentCatalogEntry: Identifiable, Sendable {
    var id: TuiAgentID
    var label: String
    /// Default CLI binary name used for PATH detection (matches catalog `cmd`).
    var cmd: String
    var homepageUrl: String
    var faviconDomain: String?
}

enum AgentCatalog {
    // MARK: - TUI_AGENT_CONFIG (exact parity with Orca)

    static let tuiAgentConfig: [TuiAgentID: TuiAgentConfig] = [
        .claude: .init(
            detectCmd: "claude",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "claude",
            expectedProcess: "claude"
        ),
        .claudeAgentTeams: .init(
            // Why: an Orca-provided launch mode, not a separate binary; detection follows the Orca CLI.
            detectCmd: "orca",
            detectCmdAliases: ["orca-dev", "orca-ide"],
            // Why: require Claude too so fresh installs (Orca shim always present) don't report Agent Teams without an agent CLI.
            detectRequiredCommands: ["claude"],
            // Why: Windows/WSL use Claude's in-process Agent Teams fallback, not this Orca native-pane/tmux-shim wrapper.
            detectUnsupportedRuntimes: [.win32, .wsl],
            launchCmd: "orca claude-teams",
            expectedProcess: "claude"
        ),
        .openclaude: .init(
            detectCmd: "openclaude",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "openclaude",
            expectedProcess: "openclaude"
        ),
        .codex: .init(
            detectCmd: "codex",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "codex",
            expectedProcess: "codex"
        ),
        .autohand: .init(
            detectCmd: "autohand",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "autohand",
            expectedProcess: "autohand"
        ),
        .ante: .init(
            detectCmd: "ante",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "ante",
            expectedProcess: "ante"
        ),
        .opencode: .init(
            detectCmd: "opencode",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "opencode",
            expectedProcess: "opencode"
        ),
        .mimoCode: .init(
            detectCmd: "mimo",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "mimo",
            expectedProcess: "mimo"
        ),
        .pi: .init(
            detectCmd: "pi",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "pi",
            expectedProcess: "pi"
        ),
        .omp: .init(
            detectCmd: "omp",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "omp",
            expectedProcess: "omp"
        ),
        .gemini: .init(
            detectCmd: "gemini",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "gemini",
            expectedProcess: "gemini"
        ),
        .antigravity: .init(
            detectCmd: "agy",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "agy",
            expectedProcess: "agy"
        ),
        .aider: .init(
            detectCmd: "aider",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "aider",
            expectedProcess: "aider"
        ),
        .goose: .init(
            detectCmd: "goose",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "goose",
            expectedProcess: "goose"
        ),
        .amp: .init(
            detectCmd: "amp",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "amp",
            expectedProcess: "amp"
        ),
        .kilo: .init(
            detectCmd: "kilo",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "kilo",
            expectedProcess: "kilo"
        ),
        .kiro: .init(
            // Why: the Kiro installer ships `kiro-cli`, not `kiro`; keep id 'kiro' for stored prefs.
            detectCmd: "kiro-cli",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "kiro-cli chat --tui",
            expectedProcess: "kiro-cli"
        ),
        .crush: .init(
            detectCmd: "crush",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "crush",
            expectedProcess: "crush"
        ),
        .aug: .init(
            // Why: @augmentcode/auggie installs a binary named `auggie`, not `aug`.
            detectCmd: "auggie",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "auggie",
            expectedProcess: "auggie"
        ),
        .cline: .init(
            detectCmd: "cline",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "cline",
            expectedProcess: "cline"
        ),
        .codebuff: .init(
            detectCmd: "codebuff",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "codebuff",
            expectedProcess: "codebuff"
        ),
        .commandCode: .init(
            // Why: use the full name (not its `cmd` alias) so detection doesn't collide with Windows' built-in cmd.exe.
            detectCmd: "command-code",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "command-code --trust",
            expectedProcess: "command-code"
        ),
        .continueAgent: .init(
            // Why: Continue's CLI binary is `cn`; `continue` is a bash/zsh builtin.
            detectCmd: "cn",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "cn",
            expectedProcess: "cn"
        ),
        .cursor: .init(
            detectCmd: "cursor-agent",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "cursor-agent",
            expectedProcess: "cursor-agent"
        ),
        .droid: .init(
            detectCmd: "droid",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "droid",
            expectedProcess: "droid"
        ),
        .kimi: .init(
            detectCmd: "kimi",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "kimi",
            expectedProcess: "kimi"
        ),
        .mistralVibe: .init(
            // Why: installer exposes binary `vibe`; package name is mistral-vibe.
            detectCmd: "vibe",
            detectCmdAliases: ["mistral-vibe"],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "vibe",
            expectedProcess: "vibe"
        ),
        .qwenCode: .init(
            // Why: package is qwen-code but installed CLI binary is `qwen`.
            detectCmd: "qwen",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "qwen",
            expectedProcess: "qwen"
        ),
        .rovo: .init(
            detectCmd: "rovo",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "rovo",
            expectedProcess: "rovo"
        ),
        .hermes: .init(
            detectCmd: "hermes",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "hermes --tui",
            expectedProcess: "hermes"
        ),
        .openclaw: .init(
            detectCmd: "openclaw",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "openclaw",
            expectedProcess: "openclaw"
        ),
        .copilot: .init(
            detectCmd: "copilot",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "copilot",
            expectedProcess: "copilot"
        ),
        .grok: .init(
            detectCmd: "grok",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "grok",
            expectedProcess: "grok"
        ),
        .devin: .init(
            detectCmd: "devin",
            detectCmdAliases: [],
            detectRequiredCommands: [],
            detectUnsupportedRuntimes: [],
            launchCmd: "devin",
            expectedProcess: "devin"
        )
    ]

    // MARK: - Detection command table (KNOWN_TUI_AGENT_DETECTION_COMMANDS)

    /// Flattened detection commands — one entry per detectCmd / alias, as in Orca.
    static let knownDetectionCommands: [TuiAgentDetectionCommand] = {
        TuiAgentID.allCases.flatMap { id -> [TuiAgentDetectionCommand] in
            guard let config = tuiAgentConfig[id] else { return [] }
            return config.allDetectCommands.map { cmd in
                TuiAgentDetectionCommand(
                    id: id,
                    cmd: cmd,
                    requiredCommands: config.detectRequiredCommands,
                    unsupportedRuntimes: config.detectUnsupportedRuntimes
                )
            }
        }
    }()

    // MARK: - Display catalog (agent-catalog.tsx order)

    static let catalog: [AgentCatalogEntry] = [
        .init(id: .claude, label: "Claude", cmd: "claude", homepageUrl: "https://docs.anthropic.com/claude/docs/claude-code"),
        .init(id: .claudeAgentTeams, label: "Claude Agent Teams", cmd: "orca", homepageUrl: "https://code.claude.com/docs/agent-teams"),
        .init(id: .openclaude, label: "OpenClaude", cmd: "openclaude", homepageUrl: "https://openclaude.gitlawb.com/"),
        .init(id: .codex, label: "Codex", cmd: "codex", homepageUrl: "https://github.com/openai/codex"),
        .init(id: .grok, label: "Grok", cmd: "grok", homepageUrl: "https://x.ai/cli", faviconDomain: "x.ai"),
        .init(id: .copilot, label: "GitHub Copilot", cmd: "copilot", homepageUrl: "https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli"),
        .init(id: .opencode, label: "OpenCode", cmd: "opencode", homepageUrl: "https://opencode.ai/docs/cli/"),
        .init(id: .mimoCode, label: "MiMo Code", cmd: "mimo", homepageUrl: "https://mimo.xiaomi.com/coder", faviconDomain: "mimo.xiaomi.com"),
        .init(id: .ante, label: "Ante", cmd: "ante", homepageUrl: "https://github.com/AntigmaLabs/ante-preview", faviconDomain: "antigma.ai"),
        .init(id: .pi, label: "Pi", cmd: "pi", homepageUrl: "https://pi.dev"),
        .init(id: .omp, label: "OMP", cmd: "omp", homepageUrl: "https://omp.sh"),
        .init(id: .gemini, label: "Gemini", cmd: "gemini", homepageUrl: "https://github.com/google-gemini/gemini-cli", faviconDomain: "gemini.google.com"),
        .init(id: .antigravity, label: "Antigravity", cmd: "agy", homepageUrl: "https://antigravity.google/docs/cli-overview", faviconDomain: "antigravity.google"),
        .init(id: .aider, label: "Aider", cmd: "aider", homepageUrl: "https://aider.chat/docs/"),
        .init(id: .goose, label: "Goose", cmd: "goose", homepageUrl: "https://block.github.io/goose/docs/quickstart/", faviconDomain: "goose-docs.ai"),
        .init(id: .amp, label: "Amp", cmd: "amp", homepageUrl: "https://ampcode.com/manual#install", faviconDomain: "ampcode.com"),
        .init(id: .kilo, label: "Kilocode", cmd: "kilo", homepageUrl: "https://kilo.ai/docs/cli"),
        .init(id: .kiro, label: "Kiro", cmd: "kiro-cli", homepageUrl: "https://kiro.dev/docs/cli/", faviconDomain: "kiro.dev"),
        .init(id: .crush, label: "Charm", cmd: "crush", homepageUrl: "https://github.com/charmbracelet/crush", faviconDomain: "charm.sh"),
        .init(id: .aug, label: "Auggie", cmd: "auggie", homepageUrl: "https://docs.augmentcode.com/cli/overview", faviconDomain: "augmentcode.com"),
        .init(id: .autohand, label: "Autohand Code", cmd: "autohand", homepageUrl: "https://github.com/autohandai/code-cli", faviconDomain: "autohand.ai"),
        .init(id: .cline, label: "Cline", cmd: "cline", homepageUrl: "https://docs.cline.bot/cline-cli/overview", faviconDomain: "cline.bot"),
        .init(id: .codebuff, label: "Codebuff", cmd: "codebuff", homepageUrl: "https://www.codebuff.com/docs/help/quick-start", faviconDomain: "codebuff.com"),
        .init(id: .commandCode, label: "Command Code", cmd: "command-code", homepageUrl: "https://commandcode.ai/docs/quickstart", faviconDomain: "commandcode.ai"),
        .init(id: .continueAgent, label: "Continue", cmd: "cn", homepageUrl: "https://docs.continue.dev/guides/cli", faviconDomain: "continue.dev"),
        .init(id: .cursor, label: "Cursor", cmd: "cursor-agent", homepageUrl: "https://cursor.com/cli", faviconDomain: "cursor.com"),
        .init(id: .droid, label: "Droid", cmd: "droid", homepageUrl: "https://docs.factory.ai/cli/getting-started/quickstart"),
        .init(id: .kimi, label: "Kimi", cmd: "kimi", homepageUrl: "https://www.kimi.com/code/docs/en/kimi-code-cli/getting-started.html", faviconDomain: "moonshot.cn"),
        .init(id: .mistralVibe, label: "Mistral Vibe", cmd: "vibe", homepageUrl: "https://github.com/mistralai/mistral-vibe", faviconDomain: "mistral.ai"),
        .init(id: .qwenCode, label: "Qwen Code", cmd: "qwen", homepageUrl: "https://github.com/QwenLM/qwen-code", faviconDomain: "qwenlm.github.io"),
        .init(id: .rovo, label: "Rovo Dev", cmd: "rovo", homepageUrl: "https://support.atlassian.com/rovo/docs/install-and-run-rovo-dev-cli-on-your-device/", faviconDomain: "atlassian.com"),
        .init(id: .hermes, label: "Hermes", cmd: "hermes", homepageUrl: "https://hermes-agent.nousresearch.com/docs/", faviconDomain: "nousresearch.com"),
        .init(id: .devin, label: "Devin", cmd: "devin", homepageUrl: "https://devin.ai/cli", faviconDomain: "devin.ai"),
        .init(id: .openclaw, label: "OpenClaw", cmd: "openclaw", homepageUrl: "https://github.com/openclaw/openclaw", faviconDomain: "openclaw.ai")
    ]

    static func label(for id: TuiAgentID) -> String {
        catalog.first(where: { $0.id == id })?.label ?? id.rawValue
    }

    static func entry(for id: TuiAgentID) -> AgentCatalogEntry? {
        catalog.first(where: { $0.id == id })
    }

    // MARK: - Detection helpers (tui-agent-detection-commands.ts)

    static func probeCommands(
        from commands: [TuiAgentDetectionCommand] = knownDetectionCommands,
        runtime: TuiAgentDetectionRuntime = .darwin
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for command in commands where !isDetectionUnsupported(command, runtime: runtime) {
            for name in [command.cmd] + command.requiredCommands where seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    static func resolveDetectedAgentIDs(
        commands: [TuiAgentDetectionCommand] = knownDetectionCommands,
        foundCommands: Set<String>,
        runtime: TuiAgentDetectionRuntime = .darwin
    ) -> [TuiAgentID] {
        var detected: [TuiAgentID] = []
        var seen = Set<TuiAgentID>()
        for command in commands {
            if isDetectionUnsupported(command, runtime: runtime) { continue }
            guard foundCommands.contains(command.cmd) else { continue }
            let requiredOK = command.requiredCommands.allSatisfy { foundCommands.contains($0) }
            guard requiredOK else { continue }
            if seen.insert(command.id).inserted {
                detected.append(command.id)
            }
        }
        return detected
    }

    static func isDetectionUnsupported(
        _ command: TuiAgentDetectionCommand,
        runtime: TuiAgentDetectionRuntime
    ) -> Bool {
        command.unsupportedRuntimes.contains(runtime)
    }
}
