# Acceptance fixes D1–D4

## D1 clipboardPasteAutomatically
- `ClipboardHistoryView.swift:79–87` — single click: if `Defaults[.clipboardPasteAutomatically]` then paste+close, else copy only
- `SettingsView.swift:1751–1753` — label «Paste on single click» + footer clarifies Enter/double-click still paste
- `Constants.swift:179` — key unchanged, now read

## D2 Delete vs search focus
- `ClipboardKeyboardMonitor.swift:57–79` — search-focus early-return moved **above** Delete handler; Delete only deletes cards when search not focused

## D3 AX prompt on paste
- `ClipboardService.swift:paste()` — `requestIfNeeded()` when `!isTrusted`
- `ClipboardAccessibility.swift:check()` — also calls `requestIfNeeded()` when untrusted

## D4 Maccy ignore flags
- `Constants.swift:180–182` — `clipboardIgnoreEvents`, `clipboardIgnoreOnlyNextEvent`, `clipboardIgnoreAllAppsExceptListed`
- `ClipboardService.swift:checkForChangesInPasteboard` — ignoreEvents + onlyNextEvent (Maccy:164–171)
- `ClipboardService.swift:shouldIgnore(bundle)` — whitelist mode (Maccy:241–247)
- `SettingsView.swift` Clipboard section — Ignore toggles

## Build
```
** BUILD SUCCEEDED **
```
