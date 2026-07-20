# Iteration 3 report — boringNotch clipboard

**Task:** task_f644bff1ba7d · **Dispatch:** ctx_413d884dd187  
**Date:** 2026-07-20

## Summary

Four clipboard changes landed: layout-independent physical key navigation, ⌘C copy-selected, hard 9-card history cap (with migration), and Space full-text as an external floating `NSPanel` under the open notch.

## Changed files (file:line highlights)

| File | What |
|------|------|
| `boringNotch/components/ClipboardHistory/Views/ClipboardKeyboardMonitor.swift` | Physical keyCode nav (Carbon kVK_ANSI_*), ⌘C, Space/Enter/Delete/Escape by keyCode |
| `boringNotch/components/ClipboardHistory/Views/ClipboardHistoryView.swift` | External popup wire-up, onCopy → `copySelected()`, close on notch/tab dismiss |
| `boringNotch/components/ClipboardHistory/Views/ClipboardTextPopupPanel.swift` | **New** — non-activating floating panel + controller |
| `boringNotch/components/ClipboardHistory/Core/ClipboardHistoryManager.swift` | `migrateHistorySizeCapIfNeeded()` |
| `boringNotch/models/Constants.swift` | `clipboardHistorySize` default **9**; migration flag `clipboardHistorySizeCappedTo9` |
| `boringNotch/components/Settings/SettingsView.swift` | History size Stepper **1…9** |
| `boringNotch/ContentView.swift` | Hide text popup when notch closes / leave clipboard tab |
| `boringNotch.xcodeproj/project.pbxproj` | Register `ClipboardTextPopupPanel.swift` |

### Key line anchors

- Nav by physical keyCode: `ClipboardKeyboardMonitor.swift` ~`navigationDelta(keyCode:)` (WASD/HJKL + arrows)
- ⌘C: `handleKeyDown` branch `keyCode == kVK_ANSI_C` → `onCopy`
- History default/migration: `Constants.swift` (`clipboardHistorySize` default 9); `ClipboardHistoryManager.migrateHistorySizeCapIfNeeded()`
- External panel: `ClipboardTextPopupController.positionPanel` — screen midX, top = notch bottom − 10pt
- Popup show/hide: `ClipboardHistoryView.togglePopup` / `closePopup`

## 1) Layout-independent navigation — keyCode table

Uses `Carbon.HIToolbox` virtual key constants (same physical keys on any layout):

| Action | Keys | keyCode (kVK) |
|--------|------|----------------|
| Left | ← / A / H | `kVK_LeftArrow` / `kVK_ANSI_A`=0 / `kVK_ANSI_H`=4 |
| Right | → / D / L | `kVK_RightArrow` / `kVK_ANSI_D`=2 / `kVK_ANSI_L`=37 |
| Up | ↑ / W / K | `kVK_UpArrow` / `kVK_ANSI_W`=13 / `kVK_ANSI_K`=40 |
| Down | ↓ / S / J | `kVK_DownArrow` / `kVK_ANSI_S`=1 / `kVK_ANSI_J`=38 |
| Space (popup) | Space | `kVK_Space`=49 |
| Enter (paste) | Return / keypad Enter | `kVK_Return` / `kVK_ANSI_KeypadEnter` |
| Delete | Delete / Forward Delete | `kVK_Delete` / `kVK_ForwardDelete` |
| Escape | Esc | `kVK_Escape`=53 |
| Copy card | ⌘C | `kVK_ANSI_C`=8 + `.command` |
| Paste index | ⌘1–9 | ANSI digit row keyCodes |

Characters are **not** used for navigation — Russian (and any other) layout keeps the same physical keys working.

## 2) ⌘C

With clipboard tab active and a card selected, **⌘C** (keyCode 8 + command, no other modifiers) calls `ClipboardHistoryManager.copySelected()` → `ClipboardService.copy` (pasteboard only, no synthetic paste).  
⌘1–9 still paste; other ⌘ combos fall through untouched.

## 3) Limit 9 cards

- Default `clipboardHistorySize`: **9** (was 200).
- Settings: `Stepper` range **1…9**.
- One-shot migration `clipboardHistorySizeCappedTo9`: if stored value **> 9** (e.g. 200) → set to **9**.
- Existing `limitHistorySize(to:)` reused on load / add / Defaults updates (oldest unpinned dropped).

## 4) External full-text panel (Space)

- **Type:** borderless `NSPanel` with `.nonactivatingPanel`, `canBecomeKey = false`.
- **Level:** `.mainMenu + 4` (notch is `+3`) so it draws under/near the curtain without stealing key.
- **Look:** dark rounded material (~black 0.92 + ultraThinMaterial), scrollable text, max **~600×400**, min ~280×72.
- **Position:**
  1. Find visible `BoringNotchSkyLightWindow` / `BoringNotchWindow` (else main screen).
  2. Notch bottom Y ≈ `window.frame.maxY - openNotchSize.height` (or `screen.maxY - openNotchSize.height`).
  3. Panel frame: horizontally centered on screen (`midX - width/2`); `origin.y = notchBottomY - 10 - height` (top edge 10pt below curtain).
- **Close:** Space / Escape / Enter / outside mouse-down (local+global monitors) / notch close / leave clipboard tab.
- **While open:** `keyboard.popupOpen = true` blocks card navigation (same as before). Notch remains key via `requestKeyWindow()`.

## Build & deploy

```
** BUILD SUCCEEDED **
```

Deploy:

```
pkill -9 -x boringNotch
rm -rf /Applications/boringNotch.app
ditto /tmp/pocket-dd/Build/Products/Debug/boringNotch.app /Applications/boringNotch.app
open /Applications/boringNotch.app
```

### Runtime confirmation

```
NEWPID=64134  etime=00:05
command=/Applications/boringNotch.app/Contents/MacOS/boringNotch
TXT=/Applications/boringNotch.app/Contents/MacOS/boringNotch
PATH_OK ALIVE_OK  (≥5s)
```

### Build tail

```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/boringNotch.app
note: Disabling hardened runtime with ad-hoc codesigning.
** BUILD SUCCEEDED **
```

## Left / follow-ups

Nothing required for this task. Optional later: pin-aware total hard cap if many pins + unpinned should still total ≤9 including pins (current logic matches pre-existing Maccy-style unpinned limit).
