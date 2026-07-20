# Design sizing rollback report

**Task:** task_ca14c6c602e3 · **Dispatch:** ctx_c81eebe55600  
**Date:** 2026-07-20

## What was rolled back

Iter **6** (105×105 Shelf) and **7** (90×90 album art) card sizing — restored pre-iter6 adaptive rectangles.

## Restored Clipboard geometry (pre-iter6)

| Token | Restored value |
|-------|----------------|
| Height | Adaptive: `min(max(available, 56), 120)` from GeometryReader |
| Width | `max(100, min(cardH * 1.35, 140))` (~140 max) |
| Corner radius | **10** |
| Spacing | **8** |
| Outer H padding | **10** |
| Top / bottom safe | **4** / **10** |
| Strip inset | **2** |
| Vertical fill | Full strip height (no fixed square frame) |
| Popup corner | **12** |

Formula in `ClipboardHistoryView.layoutMetrics` (restored).

## NotchHomeView rollback

Removed all three iter7 `.frame(width/height: MusicPlayerImageSizes.size.opened)` additions from:

- `albumArtBackground`
- `albumArtDarkOverlay`
- `albumArtImage`

**Confirmation:** `rg size.opened NotchHomeView.swift` → no matches. File matches original open-art pattern (aspectRatio fit, no explicit open size).

## Kept (not rolled back)

- Keyboard re-entry fix (`clipboardTabDidActivate`, teardown guard)
- History limit 9 + migration
- Copy/paste animations, Space external popup + arrow
- ⌘1–3 / ⌘⇧[] tab switching and tab badges
- Layout-independent keyCodes, ⌘C

## Changed files

- `ClipboardHistory/Views/ClipboardHistoryView.swift` — adaptive metrics
- `ClipboardHistory/Views/ClipboardCardView.swift` — inset 8, line-limit formula
- `ClipboardHistory/Views/ClipboardTextPopupPanel.swift` — corner 12
- `Notch/NotchHomeView.swift` — remove explicit album frames

Space popup still anchors via `ScreenFrameReporter` midX of selected card (works at any card size).

## Build & deploy

```
** BUILD SUCCEEDED **
```

Deployed to `/Applications/boringNotch.app`; process alive ≥5s from `/Applications`.

### Build tail

```
RegisterWithLaunchServices ...
** BUILD SUCCEEDED **
```
