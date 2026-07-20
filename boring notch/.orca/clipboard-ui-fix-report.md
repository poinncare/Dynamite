# Clipboard UI layout fix

## Changed files
- `boringNotch/components/ClipboardHistory/Views/ClipboardHistoryView.swift` — full rewrite of layout
- `boringNotch/components/ClipboardHistory/Views/ClipboardCardView.swift` — adaptive size + inset selection + preview

## How available height is computed
`ClipboardHistoryView` wraps content in `GeometryReader` over the content band **below** `BoringHeader` (parent `NotchLayout` already reserves header height).

```
available = geo.size.height − topSafe(2) − bottomSafe(10)
cardH     = clamp(available − searchH(28) − stackSpacing(4), 52…96)
cardW     = clamp(cardH × 1.28, 96…124)
```

`bottomSafe=10` keeps timestamps above the open-notch bottom corner radius (opened.bottom = 24). Search is fixed compact **28pt**. Cards use **fixed height frame** from metrics (no intrinsic 120 overflow).

## Fixes mapped
| Bug | Fix |
|-----|-----|
| Cards clipped top/bottom | Adaptive cardH from GeometryReader + bottomSafe |
| Green vertical strip | Removed scaleEffect; selection `strokeBorder` **inside** card bounds (not outside clip) |
| Empty body / title-only | `previewBodyText` prefers `item.text` / `previewableText`, lineLimit 5, fills remaining card space |
| Stroke clipped by ScrollView | No outer ring; HStack (not LazyHStack clip quirks); no scale |

## Build
```
** BUILD SUCCEEDED **
```
(command: `DEVELOPER_DIR=... xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination platform=macOS -derivedDataPath /tmp/boringNotch-ui2 build`)

## Screenshot
`docs/clipboard-ui-fixed.png` — open notch, clipboard tab, full rounded green selection around card, timestamp fully visible inside notch.
