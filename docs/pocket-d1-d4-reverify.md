# Re-verify D1–D4 (acceptance fixes)

Project: `boring notch` | Independent code check + clean build. Nothing modified.

## Build
```
DEVELOPER_DIR=... xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination platform=macOS -derivedDataPath /tmp/pocket-verify2-dd build
```
Exit 0. Tail:
```
Validate /tmp/pocket-verify2-dd/Build/Products/Debug/boringNotch.app ...
Touch .../boringNotch.app
RegisterWithLaunchServices ...
note: Disabling hardened runtime with ad-hoc codesigning.
** BUILD SUCCEEDED **
```

## D1 clipboardPasteAutomatically — PASS
- Read on single-click: `ClipboardHistoryView.swift:81-86` — if true → `pasteItem`+close, else `copy`
- Label: `SettingsView.swift:1751-1753` «Paste on single click»
- Footer: `SettingsView.swift:1778` Enter/double-click still paste
- Key: `Constants.swift:179`

## D2 Delete vs search focus — PASS
- Early-return **before** Delete: `ClipboardKeyboardMonitor.swift:69-73` (`isSearchFocused && !isArrow` → pass event)
- Delete handler after: `75-78` only runs when not search-focused (or is arrow — Delete is not arrow)
- Enter still handled first (`56-59`) as intended

## D3 AX requestIfNeeded on paste — PASS
- `ClipboardService.paste()` `107-111`: if `!isTrusted` → `requestIfNeeded()`
- `ClipboardAccessibility.check()` `13-15` also calls `requestIfNeeded()` when untrusted
- Prompt flag: `requestIfNeeded` `18-20` with `kAXTrustedCheckOptionPrompt`

## D4 Maccy ignore flags — PASS
| Piece | Port | Maccy |
|---|---|---|
| Keys | `Constants.swift:180-182` clipboardIgnoreEvents / OnlyNext / AllAppsExceptListed | ignoreEvents / ignoreOnlyNextEvent / ignoreAllAppsExceptListed |
| ignoreEvents + onlyNext | `ClipboardService.swift:152-157` | `Clipboard.swift:164-171` — same structure |
| whitelist apps | `ClipboardService.swift:210-217` | `Clipboard.swift:241-247` — same structure |
| Settings toggles | `SettingsView.swift:1783-1793` + footer 1797-1798; onlyNext disabled unless ignoreEvents on | present |

## Verdict
| ID | Result |
|---|---|
| D1 | **PASS** |
| D2 | **PASS** |
| D3 | **PASS** |
| D4 | **PASS** |
| Build | **PASS** (`** BUILD SUCCEEDED **`) |

**Итог: PASS (все D1–D4 + build)**
