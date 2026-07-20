# Pocket iteration 2 — report

## Acceptance
| # | Status |
|---|--------|
| BUILD SUCCEEDED | ✓ |
| No search / no isSearchFocused | ✓ (rg empty) |
| Toggle Cmd+Shift+C | ✓ boringNotchApp.swift:434–447 |
| Space popup | ✓ ClipboardHistoryView textPopup + monitor onSpace |
| Footer: icon L / time R now|Nm|Nh|Nd | ✓ ClipboardCardView + ClipboardRelativeTime |
| hjkl + WASD + arrows one handler | ✓ navigationDelta() |
| ⌘ hold → ⌘N, ⌘1–9 paste | ✓ flagsChanged + onPasteIndex |
| Language picker default EN, L() | ✓ AppLanguage + Pocket.strings en/ru |

## Screenshot
`docs/clipboard-ui-iter2.png` — open clipboard tab: multi-line previews, app icons bottom-left, `4m`/`10m` times bottom-right, no search, full green selection ring.
⌘-hold screenshot: automation unreliable (System Events does not hold modifier for flagsChanged on panel); code path verified.

## Decisions / notes
1. **Strings table `Pocket`** not `Localizable` — conflict with existing `Localizable.xcstrings` (Xcode error). `L()` loads `en.lproj/Pocket.strings` / `ru.lproj/Pocket.strings`.
2. **Settings localization**: all `Text`/`Label`/`navigationTitle`/`help`/`Recorder` titles wrapped with `L()`; ~160 keys; curated RU for main sections; remaining ~68 keys fall back to English until filled.
3. **Language switch**: immediate via `LanguageManager.revision` + SettingsView `.id(...)`.
4. **fuse / ClipboardSearch.swift**: left in target unused (search UI removed; manager still calls search with empty query → all items).
5. **Toggle hotkey**: no 3s auto-close; closed→open clipboard; open+clipboard→close; open+other→switch to clipboard.

## Changed / added files
- `helpers/AppLanguage.swift` (new)
- `en.lproj/Pocket.strings`, `ru.lproj/Pocket.strings` (new)
- `components/ClipboardHistory/Views/ClipboardHistoryView.swift`
- `components/ClipboardHistory/Views/ClipboardCardView.swift`
- `components/ClipboardHistory/Views/ClipboardKeyboardMonitor.swift`
- `components/ClipboardHistory/Views/ClipboardRelativeTime.swift` (new)
- `boringNotchApp.swift` (toggle hotkey)
- `components/Settings/SettingsView.swift` (L() + language picker)
- `boringNotch.xcodeproj/project.pbxproj`

## Build tail
```
** BUILD SUCCEEDED **
```
