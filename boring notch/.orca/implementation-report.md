# Pocket — отчёт исполнителя

## Список изменённых/добавленных файлов

### SPM / build unlock
- `boringNotch.xcodeproj/project.pbxproj` — пины, Sauce/Fuse, local MacroVisionKit, источники ClipboardHistory
- `Vendor/MacroVisionKit/**` — вендор v0.2.0 с `swift-tools-version: 5.9`

### Clipboard core (порт Maccy)
- `boringNotch/components/ClipboardHistory/Models/HistoryItem.swift`
- `boringNotch/components/ClipboardHistory/Models/HistoryItemContent.swift`
- `boringNotch/components/ClipboardHistory/Core/PasteboardTypes.swift`
- `boringNotch/components/ClipboardHistory/Core/String+Shortened.swift`
- `boringNotch/components/ClipboardHistory/Core/ClipboardAccessibility.swift`
- `boringNotch/components/ClipboardHistory/Core/KeyboardLayout.swift`
- `boringNotch/components/ClipboardHistory/Core/ClipboardStorage.swift`
- `boringNotch/components/ClipboardHistory/Core/ClipboardSearch.swift`
- `boringNotch/components/ClipboardHistory/Core/ClipboardService.swift`
- `boringNotch/components/ClipboardHistory/Core/ClipboardHistoryManager.swift`

### UI
- `boringNotch/components/ClipboardHistory/Views/ClipboardCardView.swift`
- `boringNotch/components/ClipboardHistory/Views/ClipboardKeyboardMonitor.swift`
- `boringNotch/components/ClipboardHistory/Views/ClipboardHistoryView.swift`

### Wiring
- `boringNotch/enums/generic.swift` — `NotchViews.clipboard`
- `boringNotch/components/Tabs/TabSelectionView.swift` — вкладка Clipboard
- `boringNotch/ContentView.swift` — switch + key focus cleanup
- `boringNotch/boringNotchApp.swift` — hotkey Cmd+Shift+C + start manager
- `boringNotch/models/Constants.swift` — `clipboard*` Defaults keys
- `boringNotch/components/Settings/SettingsView.swift` — Clipboard settings + shortcut recorder
- `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift` — conditional `canBecomeKey`
- `boringNotch/components/Notch/BoringHeader.swift` — show tabs when clipboard enabled

## Как решён блокер Swift 6.1
1. **KeyboardShortcuts**: exact pin **2.3.0** (tools 5.11; 2.4.0 требовал tools 6.1).
2. **MacroVisionKit**: remote 0.2.0 (tools 6.1) → **local vendored** copy of v0.2.0 at `Vendor/MacroVisionKit` with `swift-tools-version: 5.9`; API `FullScreenMonitor` сохранён.
3. **Sauce**: exact **2.4.1** (master/v2.5.x Package.swift невалиден на SwiftPM 5.9 из-за trailing comma).
4. **fuse-swift**: upToNextMajor from 1.4.0.

## Финальная сборка
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/boringNotch-dd build
```
Последние строки:
```
Validate /tmp/boringNotch-dd/Build/Products/Debug/boringNotch.app ...
** BUILD SUCCEEDED **
```
exit 0.

## Smoke-запуск
- `open /tmp/boringNotch-dd/Build/Products/Debug/boringNotch.app`
- Процесс `boringNotch` жив ≥4s (PID наблюдён), крэша нет.
- Завершён kill (osascript quit не сработал мгновенно — app menubar-only, force kill OK).

## Отклонения от спецификации
1. **Имена типов**: `ClipboardService` / `ClipboardHistoryManager` / `ClipboardStorage` вместо `Clipboard`/`History`/`Storage`, чтобы не конфликтовать с чужими символами; логика Maccy сохранена.
2. **UI Maccy / HistoryItemDecorator / Notifier / pin shortcuts a–z** не переносились (по спеке UI Maccy не портировать). Pin — boolean-like `"•"`.
3. **`clipboardPasteAutomatically`**: в UI есть toggle; Enter/double-click всегда paste (по приёмке п.5). Single click = copy.
4. **2 ряда карточек** не реализованы (высота notch ~190; 1 ряд LazyHStack; WASD/стрелки ↑↓ действуют как горизонтальный сдвиг).
5. **Pow** остаётся orphan package ref (как было); не трогали.

## Не проверено / риски
- Полный UX: Cmd+Shift+C → вкладка clipboard, навигация WASD, paste в другое приложение — требует ручного GUI + Accessibility permission (AXIsProcessTrusted).
- Paste (CGEvent Cmd+V) без Accessibility может молча не работать.
- SwiftData на macOS 14: insert path simplified (всегда insert+save), без Maccy dual-path macOS 14/15.
- Debounce/throttling поиска упрощён (applySearch синхронно).
- Multi-display: hotkey открывает notch на экране с курсором (как toggleNotchOpen).
- Принудительный kill smoke: app как MenuBarExtra не отвечает на «quit» через AppleScript всегда.
