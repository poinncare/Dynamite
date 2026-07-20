# Iteration 6 report — keyboard re-entry + square Shelf-like tiles

**Task:** task_13de535df237 · **Dispatch:** ctx_9ce80e06093d  
**Date:** 2026-07-20

## 1) Navigation bug after returning to Clipboard

### Confirmed cause

Dual lifecycle race from iter5:

1. **Leave clipboard** — `ContentView` `onChange(currentView)` calls `disableClipboardHandlers()` which **clears callbacks** (`onMove`/`onEnter`/… = nil) and sets `clipboardHandlersEnabled = false`  
   (`ContentView.swift` ~187–191 pre-fix; `ClipboardKeyboardMonitor.disableClipboardHandlers`).

2. **Re-enter clipboard** — relied only on `ClipboardHistoryView.onAppear` → `setupKeyboard()`. With the tab switch **transition** (scale/opacity ~0.35s), the **outgoing** `ClipboardHistoryView.onDisappear` can run **after** the new instance’s `onAppear`, calling `teardownKeyboard()` → `disableClipboardHandlers()` again and wiping the newly bound handlers.

3. ContentView never re-activated handlers/key-focus on `currentView == .clipboard` (only disabled on leave).

So WASD/arrows stop working even though the notch-wide monitor is still running.

### Fix

| Change | Where |
|--------|--------|
| Guard teardown if clipboard is active again | `ClipboardHistoryView.teardownKeyboard` — `guard coordinator.currentView != .clipboard` |
| Post `clipboardTabDidActivate` + key focus on every entry | `ContentView.onChange(currentView == .clipboard)` |
| Rebind on notification + open-while-clipboard | `ClipboardHistoryView` `onReceive` / `notchState == .open` |
| Idempotent monitor start | `startNotchSession` already no-ops if monitors exist; `enableClipboardHandlers` is a flag set |

Handlers are re-installed on: first appear, every tab re-entry (click/⌘3/⌘⇧[]), and notch re-open while on clipboard.

## 2) Square cards = Shelf tile metrics

| Token | Shelf source | Clipboard now |
|-------|--------------|---------------|
| Side | `ShelfItemView` `.frame(width: 105)` | **105×105** square |
| Corner radius | `RoundedRectangle(cornerRadius: 12)` | **12** |
| Spacing | `ShelfView` `spacing = 8` | **8** |
| Selection fill | accent **0.15** | same when selected |
| Selection stroke | accent **0.8**, lineWidth **2** | same |
| Vertical align | `HStack(alignment: .center)` | strip centered in notch body |
| Popup radius | — | **12** (match tiles) |

Content kept: multi-line preview, app icon bottom-left, relative time bottom-right; line limit capped for square height. Green fill / Space arrow panel still use selected card screen midX via `ScreenFrameReporter`.

## Changed files

- `ClipboardHistory/Views/ClipboardHistoryView.swift` — lifecycle + fixed tile metrics  
- `ClipboardHistory/Views/ClipboardCardView.swift` — Shelf-like chrome, square-friendly lines  
- `ClipboardHistory/Views/ClipboardKeyboardMonitor.swift` — safer disable  
- `ClipboardHistory/Views/ClipboardTextPopupPanel.swift` — cornerRadius 12  
- `ContentView.swift` — activate on clipboard entry  

## Build & deploy

```
** BUILD SUCCEEDED **
```

Deployed to `/Applications/boringNotch.app`; process alive ≥5s from `/Applications`.

Screenshot: `docs/clipboard-ui-iter6.png` (full-screen capture if app was visible; open Clipboard tab to verify squares interactively).

### Build tail

```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/boringNotch.app
** BUILD SUCCEEDED **
```

## Left

None for this task. Optional: keep a single long-lived `ClipboardHistoryView` with opacity instead of switch-destroy if further lifecycle edge cases appear.
