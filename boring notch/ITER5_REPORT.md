# Iteration 5 report — Enter anim, instant fill, tab ⌘ shortcuts

**Task:** task_82149aab8ff0 · **Dispatch:** ctx_b40036472170  
**Date:** 2026-07-20

## Summary

Enter paste now runs the same green-fill + promote animation with ~0.72s delayed close while CGEvent paste fires immediately; fill starts with zero delay (simultaneous with press-scale). Card ⌘N paste removed; ⌘1–3 and ⌘⇧[/] switch tabs notch-wide with badges on the tab bar. Dual-scope keyboard: notch-wide ⌘ session on any open tab; full WASD/Space/Enter/⌘C only on Clipboard.

## Changed files (file:line highlights)

| File | What |
|------|------|
| `ClipboardHistory/Views/ClipboardKeyboardMonitor.swift` | Dual scope: `startNotchSession` / `enableClipboardHandlers`; ⌘1–3 tabs; ⌘⇧ brackets; removed card paste index |
| `ClipboardHistory/Views/ClipboardHistoryView.swift` | `performAnimatedAction(paste:)`; Enter uses paste+anim; no card ⌘N; teardown only disables clipboard handlers |
| `ClipboardHistory/Views/ClipboardCardView.swift` | Removed `commandIndex`; phases `.fill` / `.flying` only |
| `Tabs/TabSelectionView.swift` | ⌘ badges 1–3 when `isCommandHeld` |
| `Tabs/TabButton.swift` | Optional `commandIndex` badge above icon |
| `ContentView.swift` | Open → notch session + key focus; leave clipboard → disable clipboard only; `.notchRequestClose` |

### Key anchors

- Simultaneous fill: `ClipboardHistoryView.performAnimatedAction` — `withAnimation { copyPhase = .fill }` immediately after pasteboard write
- Enter paste+anim: `monitor.onEnter` → `performAnimatedAction(..., paste: true)` (paste via `pasteItem` first)
- Tab switch: `ClipboardKeyboardMonitor.selectTab` / `cycleTab` (kVK_ANSI_LeftBracket=33, RightBracket=30)
- Scope: `ContentView` `notchState == .open` → `startNotchSession` + `clipboardTabKeyFocus true`

## 1) Enter animation

`onEnter` no longer closes immediately. It calls `performAnimatedAction(item:index:paste: true)`:
1. **Immediate** `manager.pasteItem` (copy + CGEvent paste, ~0.05s internal delay for focus only — not animation-gated)
2. Visual fill + promote same as copy
3. Notch closes at **0.72s**

## 2) Fill without delay

Removed staggered `.press` (0.07s) then fill. Single phase `.fill` starts at call time: scale 0.94 and green circle expand together (`easeOut` 0.28s).

## 3) ⌘N moved to tabs

- Cards: no `commandIndex`, footer always shows relative time
- Tabs: hold ⌘ → badges **⌘1 Home / ⌘2 Shelf / ⌘3 Clipboard**
- ⌘+digit (1–3, physical ANSI row) switches `BoringViewCoordinator.currentView`
- Card paste-by-number **removed**

## 4) Browser-like tab cycle

| Shortcut | keyCode | Action |
|----------|---------|--------|
| ⌘⇧[ | `kVK_ANSI_LeftBracket` (33) | Previous tab (cyclic among available) |
| ⌘⇧] | `kVK_ANSI_RightBracket` (30) | Next tab |

Available set respects `boringShelf` / `clipboardEnabled` flags for cycling; ⌘1–3 always map Home/Shelf/Clipboard and no-op if feature off.

## 5) Scope of keyboard (chosen design)

**Hybrid dual-scope (recommended path from the task):**

| Scope | When | Keys |
|-------|------|------|
| **Notch-wide** | Notch open (any tab) | `flagsChanged` → `isCommandHeld`; ⌘1–3; ⌘⇧[/]; Esc → close (or clipboard callback) |
| **Clipboard-only** | Clipboard tab visible (`enableClipboardHandlers`) | WASD/HJKL/arrows, Space, Enter, Delete, ⌘C |

Lifecycle:
- `ContentView` open → `startNotchSession()` + allow key window (`clipboardTabKeyFocus`)
- Leave clipboard → `disableClipboardHandlers()` only (notch session keeps running)
- Close notch → `stop()` + revoke key focus

Why not full keys on all tabs: avoids stealing typing/hover gestures on Home/Shelf; only ⌘ combos are global. Clipboard navigation/Space popup/⌘C unchanged when that tab is active.

## Build & deploy

```
** BUILD SUCCEEDED **
```

```
pkill -9 -x boringNotch
rm -rf /Applications/boringNotch.app
ditto /tmp/pocket-dd/Build/Products/Debug/boringNotch.app /Applications/boringNotch.app
open /Applications/boringNotch.app
```

Process: from `/Applications/boringNotch.app/Contents/MacOS/boringNotch`, alive ≥5s (see deploy log).

### Build tail

```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/boringNotch.app
** BUILD SUCCEEDED **
```

## Left

Nothing required for this task.
