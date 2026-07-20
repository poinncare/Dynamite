# Iteration 7 report — Clipboard tiles = Home album-art geometry

**Task:** task_bb0af40a07fa · **Dispatch:** ctx_c4f2e60d0f97  
**Date:** 2026-07-20

## 1) Reference geometry (Home music cover)

| Token | Value | Source |
|-------|-------|--------|
| Open cover size | **90×90** | `sizing/matters.swift:22` — `MusicPlayerImageSizes.size.opened` |
| Closed cover size | 20×20 | `matters.swift:22` — `.closed` (live activity only) |
| Corner radius (open, scaling on) | **13** | `matters.swift:21` — `cornerRadiusInset.opened` |
| Corner radius (open, scaling off) | **4** | `matters.swift:21` — `.closed` branch |
| Padding around cover | **5 all sides** | `NotchHomeView.swift:21` — `AlbumArtView(...).padding(.all, 5)` |
| Home content alignment | **top** | `NotchHomeView.swift:443` — `HStack(alignment: .top, …)` |
| Open notch height | 190 | `matters.swift:16` — `openNotchSize` |
| Notch chrome horizontal pad | 19/24 + 12 | `ContentView.swift:98–102` + `cornerRadiusInsets` |

Album art clip uses the same radius switch (`NotchHomeView.swift:90–95` previously without explicit frame; now also `.frame(90×90)` at ~84–96 so the constant is actually applied).

**Note:** Before this iter, `MusicPlayerImageSizes.size.opened` was **defined but unused** (no `.frame` on open art). Iter7 wires the 90×90 frame on Home so Clipboard and Home share the same square.

## 2) Applied to Clipboard

| Token | Applied |
|-------|---------|
| Tile | `MusicPlayerImageSizes.size.opened` → **90×90** |
| Corner | same Defaults-driven 13 / 4 as album art |
| Edge inset | **5** (= album `padding(.all, 5)`) top/bottom/horizontal |
| Strip alignment | **topLeading** (match Home top stack) |
| Spacing | **10** (= 2× art padding 5) |
| Popup corner | **13** (`cornerRadiusInset.opened`) |

Files:
- `ClipboardHistoryView.swift` — metrics + top layout  
- `ClipboardCardView.swift` — inset/line limits for 90²  
- `ClipboardTextPopupPanel.swift` — corner 13  
- `NotchHomeView.swift` — explicit `.frame(width/height: size.opened)` on art  

Selection stroke, green fill, Space popup arrow (selected-card midX) unchanged in behavior; geometry scales with 90².

## 3) Screenshots

Paths:
- `docs/clipboard-ui-iter7-home.png`
- `docs/clipboard-ui-iter7-clip.png`

**Status: partial / not fully verified open-notch content**

| Attempt | Result |
|---------|--------|
| Early `osascript` + full desktop capture | Open notch briefly visible once: first “home” frame was **Shelf** (music + drop zone), clip frame showed **Clipboard square cards**; later overwritten |
| `screencapture -D 1` after ⌘1/⌘3 | Main display only; notch stayed **closed** (shortcuts/click did not keep open without reliable Accessibility/HID) |
| Swift/Quartz CGEvent | Toolchain / module errors; no inject |
| Relaunch + `click at` | Notch still closed in crops |

Honest conclusion: full-screen PNGs are saved on the built-in display, but automated open of Home/Clipboard for side-by-side size proof did not stick. Code uses the exact Home constants; manual open of Home then Clipboard should show matching 90² squares.

## 4) Build & deploy

```
** BUILD SUCCEEDED **
```

```
pkill -x boringNotch
rm -rf /Applications/boringNotch.app
ditto /tmp/pocket-dd/Build/Products/Debug/boringNotch.app /Applications/boringNotch.app
open /Applications/boringNotch.app
```

Process from `/Applications/boringNotch.app/Contents/MacOS/boringNotch`, alive ≥5s.

### Build tail

```
RegisterWithLaunchServices ...
** BUILD SUCCEEDED **
```

## Left

None for code. Optional: human-captured open-notch Home vs Clipboard pair for the design review.
