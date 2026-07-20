# Iteration 4 report — Clipboard UX polish

**Task:** task_c758570c8764 · **Dispatch:** ctx_12d75c0af88d  
**Date:** 2026-07-20

## Summary

Space popup restyled like cards with arrow under the selected card; navigation stays live while the popup is open; strip scroll jank reduced; single-click delay removed; copy paths get press→green fill→promote-to-⌘1 animation with delayed notch close (~0.72s).

## Changed files (file:line)

| File | Highlights |
|------|------------|
| `ClipboardHistory/Views/ClipboardCardView.swift` | Instant `onTapGesture` (no double-tap); copy fill/scale phases; `compositingGroup`+`drawingGroup`; icon/text snapshot in `init`; `ScreenFrameReporter` |
| `ClipboardHistory/Views/ClipboardHistoryView.swift` | `performCopyWithAnimation`; popup follow on selection; timer 60s; delayed close |
| `ClipboardHistory/Views/ClipboardTextPopupPanel.swift` | Card-like translucent fill; arrow; anchor under card midX + clamp + arrow offset |
| `ClipboardHistory/Views/ClipboardKeyboardMonitor.swift` | Nav allowed while `popupOpen` |
| `ClipboardHistory/Views/ClipboardIconCache.swift` | **New** — NSWorkspace icon cache |
| `ClipboardHistory/Core/ClipboardHistoryManager.swift` | `promoteCopied(_:)` bumps `lastCopiedAt` + re-sort |
| `ContentView.swift` | (unchanged from iter3 popup hide on close) |
| `project.pbxproj` | Register new sources |

### Key anchors

- Click delay fix: `ClipboardCardView` — single `.onTapGesture(perform:)` only (removed `count: 2`)
- Copy anim: `ClipboardHistoryView.performCopyWithAnimation` — press 0.07s → fill 0.28s → promote 0.32s → close 0.72s
- Promote: `ClipboardHistoryManager.promoteCopied` (~line after `copySelected`)
- Popup style/position: `ClipboardTextPopupPanel.layoutFrame` + `ClipboardFullTextPopupContent`
- Nav while popup open: `ClipboardKeyboardMonitor.handleKeyDown` (no early return that swallows arrows)

## 1) Popup styling

- Fill: `Color.white.opacity(0.12)` over `.ultraThinMaterial` (same family as card `white.opacity(0.08/0.14)`)
- Corner radius **10**, stroke `white.opacity(0.12)` — matches cards
- Soft window shadow on panel only (not on strip cards)

## 2) Arrow + under-card placement

- Small upward triangle on top of body (`PopupArrow`)
- Anchor X = selected card **screen midX** via `ScreenFrameReporter` (AppKit `convertToScreen`)
- Ideal panel center = card midX; clamp to screen margins; **arrowOffsetX** = target − panelCenter (clamped inside body)
- Vertical: top of panel under open notch bottom (`window.maxY - openNotchSize.height - gap`)

## 3) Navigation while popup open

- Keyboard no longer blocks arrows/WASD/HJKL when `popupOpen`
- `onChange(selectedIndex)` + selected-card reporter call `ClipboardTextPopupController.update(text:anchor:)`
- Trackpad scroll of strip unaffected (popup is external nonactivating panel)
- Space / Escape close popup; clicks on notch cards allowed (outside-click ignores notch window)

## 4) Scroll jank — cause & fix

**Causes found:**
1. `onTapGesture(count:2)` + `count:1` delayed input (separate from jank but felt laggy)
2. **NSWorkspace.icon** / **HistoryItem.image** recreated every body pass while scrolling
3. Relative-time `Timer` every **30s** still forced strip invalidation; reduced to **60s**
4. Per-card multi-layer fill/stroke without flattening → expensive blend during scroll
5. `isSelected` animations on every selection change during fast keyboard nav

**Fixes:**
- `ClipboardIconCache` for app + file icons
- Snapshot preview text/images in card `init`
- `.compositingGroup()` + `.drawingGroup(opaque: false)` on each card
- Timer 60s; max 9 cards keeps work bounded
- Removed selection ease animation spam where possible

## 5) Click delay — cause & fix

**Cause:** stacked `onTapGesture(count: 2)` then `count: 1` — system waits to distinguish double-click before firing single-click.  
**Fix:** only instant single-click; paste remains Enter / ⌘1–9 / paste-on-click setting. Double-tap removed.

## 6–7) Copy behavior + animation

Any copy (click, ⌘C, context menu Copy):
1. **Immediate** `ClipboardService.copy` (`.fromMaccy` on pasteboard → poller skips duplicate)
2. Scale down ~0.94 (press)
3. Accent-green circle expands from center (~0.3s) — same `Color.accentColor` as selection ring
4. `promoteCopied` → `lastCopiedAt = now`, re-sort, selection tracks item to front (⌘1)
5. Spring list reorder + scroll-to-leading
6. Notch stays open **~0.72s**, then closes

Paste paths (Enter / ⌘N / paste-on-click) close immediately as before.

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

### Runtime

See deploy log: process from `/Applications/boringNotch.app/Contents/MacOS/boringNotch`, alive ≥5s.

### Build tail

```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/boringNotch.app
note: Disabling hardened runtime with ad-hoc codesigning.
** BUILD SUCCEEDED **
```

## Left

Nothing required for this task. Optional: matched-geometry “fly” if spring reorder still feels discrete on some macOS versions.
