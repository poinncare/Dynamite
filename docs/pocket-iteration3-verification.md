# Iteration 3 — quick independent acceptance

Nothing modified. Facts vs code.

## 1) Nav by keyCode only — PASS
- `ClipboardKeyboardMonitor.swift:133-160` `navigationDelta(keyCode:)` uses only `kVK_*` / `kVK_ANSI_*`
- No `characters` / `charactersIgnoringModifiers` in file (`rg` empty)
- Arrows + WASD + HJKL physical

## 2) ⌘C copy, no paste, no clash with ⌘1–9 — PASS
- Digits first: `:75-80` `digitFromKeyCode` → `onPasteIndex`
- Then `:83-85` `keyCode == kVK_ANSI_C` (8) → `onCopy`
- Wire: `ClipboardHistoryView.swift:212-214` → `manager.copySelected()` → `ClipboardService.copy` only (`HistoryManager:159-161`), **no** `paste()`

## 3) History size 9 — PASS
- Default: `Constants.swift:179` `default: 9`
- Stepper 1…9: `SettingsView.swift:1767-1777`
- Migration once: `HistoryManager:220-231` + flag `clipboardHistorySizeCappedTo9`; called `start()` `:33`
- `limitHistorySize` on add: `:115`; load `:83`; Defaults updates `:67-70`

## 4) Space popup external panel — PASS
- `ClipboardTextPopupNSPanel` nonactivating, `canBecomeKey=false` (`ClipboardTextPopupPanel.swift:13-16, 105`)
- Position under notch center: `:130-160` midX, `notchBottomY - gap - height`
- Close: Space/Esc (`HistoryView` + monitor popupOpen); outside click monitors `:178-200`; notch/tab close `ContentView:172,179` + `teardownKeyboard:230`
- Nav blocked: monitor `:97-107` + `onMove` guard `:186-188`
- pbxproj Sources: `ClipboardTextPopupPanel.swift` registered (IDs P0CTEXTPOPUP*)

## 5) /Applications/boringNotch.app freshness — PASS
- Today 2026-07-20
- Bundle mtime **16:53**, binary **17:08** (both after 14:00)

| # | Verdict |
|---|---|
| 1 keyCode nav | **PASS** |
| 2 ⌘C | **PASS** |
| 3 size 9 | **PASS** |
| 4 Space panel | **PASS** |
| 5 App mtime | **PASS** |

**Итог: PASS (все 5)**
