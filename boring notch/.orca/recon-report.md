# Разведка: boring notch (клон boring.notch)

Репозиторий: `/Users/user/Dev/vibecode/Pocket/boring notch`  
Режим: read-only. Пути относительно корня клона.

---

## 1) Xcode-проект / схема / macOS / зависимости

| Факт | Координаты |
|------|------------|
| Xcode project | `boringNotch.xcodeproj` |
| Workspace | `boringNotch.xcodeproj/project.xcworkspace` (SPM) |
| Targets | `boringNotch` (app), `BoringNotchXPCHelper` (xpc) — `boringNotch.xcodeproj/project.pbxproj:762–821` |
| App product | `boringNotch.app`; `productName = dynamicNotch` — pbxproj:818–819 |
| Bundle ID app | `theboringteam.boringnotch` — pbxproj:1252 / 1305 |
| Bundle ID XPC | `theboringteam.boringnotch.BoringNotchXPCHelper` — pbxproj:1053 / 1078 |
| Shared `.xcscheme` в репо | **нет** (нет `xcshareddata/xcschemes/`) — схема по умолчанию совпадает с target name `boringNotch` (автоген Xcode) |
| MACOSX_DEPLOYMENT_TARGET | **14.0** — pbxproj:1051, 1076, 1141, 1201, 1250, 1303 |
| Менеджер зависимостей | **SPM** через Xcode project (`XCRemoteSwiftPackageReference` + `Package.resolved`) |
| Локальный Package.swift | **нет** |
| Embedded binary | `mediaremote-adapter/MediaRemoteAdapter.framework` — pbxproj:200 |
| System frameworks | IOKit, ApplicationServices — pbxproj:265–266 |

### SPM-продукты, прилинкованные к target `boringNotch` (pbxproj:804–817)

| Product | Package | Resolved version (`Package.resolved`) |
|---------|---------|----------------------------------------|
| LaunchAtLogin | LaunchAtLogin-Modern | 1.1.0 |
| Sparkle | Sparkle | 2.9.1 (exact) |
| KeyboardShortcuts | KeyboardShortcuts | 2.4.0 |
| Collections | swift-collections | 1.3.0 |
| Defaults | Defaults | 9.0.6 |
| SwiftUIIntrospect | swiftui-introspect | 1.3.0 |
| SkyLightWindow | SkyLightWindow | 1.0.0 |
| Lottie | lottie-spm | 4.5.2 |
| AsyncXPCConnection | AsyncXPCConnection | 1.3.0 |
| MacroVisionKit (×3 product refs) | MacroVisionKit | 0.2.0 |

- **Pow** объявлен как remote package (pbxproj:855, 1407–1413) и pin 1.0.5, но **не** в `packageProductDependencies` target; `import Pow` в Swift-исходниках **не найден**.
- Transitive pin: `swift-syntax` 602.0.0 (через MacroVisionKit и т.п.).

---

## 2) Точка входа и окно-шторка (notch)

### Entry
- `@main struct DynamicNotchApp: App` — `boringNotch/boringNotchApp.swift:15–16`
- `AppDelegate` через `@NSApplicationDelegateAdaptor` — `boringNotchApp.swift:17`, класс:52
- MenuBarExtra «boring.notch» — `boringNotchApp.swift:32–48`
- Lifecycle: `applicationDidFinishLaunching` — `boringNotchApp.swift:282+`

### Создание notch-окна
- `createBoringNotchWindow(for:with:)` — `boringNotchApp.swift:234–265`
  - `BoringNotchSkyLightWindow` (subclass `NSPanel`) — `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:34`
  - styleMask: `.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow` — App:236
  - `contentView = NSHostingView(rootView: ContentView().environmentObject(viewModel))` — App:247–250
  - Вставка в `NotchSpaceManager.shared.notchSpace.windows` — App:254
- Позиционирование top-center экрана: `positionWindow` — App:268–279
- Размеры: `openNotchSize` / `windowSize` — `boringNotch/sizing/matters.swift:16–17` (640×190 / +shadow)
- UI root: `ContentView` — `boringNotch/ContentView.swift`
- Multi-display: `windows: [String: NSWindow]`, `viewModels: [String: BoringViewModel]` — App:54–55; single: `window` + `vm` — App:56–57

### Open / close шторки
| Действие | Механизм | Координаты |
|----------|----------|------------|
| State | `NotchState` `.closed` / `.open` | `enums/generic.swift:22–25` |
| open() | `notchSize = openNotchSize`, `notchState = .open` | `models/BoringViewModel.swift:192–198` |
| close() | restore closed size, reset UI, tab default | `BoringViewModel.swift:200–218` |
| Hover open | `handleHover` + `Defaults[.openNotchOnHover]` + delay | `ContentView.swift:513–541`, `doOpen` 506–508 |
| Hover close | mouse leave → `vm.close()` | ContentView:542–556 |
| Tap open | `.onTapGesture { doOpen() }` | ContentView:135–136 |
| Down gesture open | pan down when closed | ContentView:137–141, 562–582 |
| Up gesture close | pan up when open | ContentView:143–147, 585+ |
| Global hotkey toggle | `KeyboardShortcuts.onKeyDown(.toggleNotchOpen)` Cmd+Shift+I | App:368–411; default `Shortcuts/ShortcutConstants.swift:17` |
| Drag-over open → shelf | drag enter notch region | App:222–231; drop UI ContentView:217–224, 491+ |
| Auto-close after hotkey | Task.sleep 3s then close | App:396–404 |

Окно живёт постоянно (panel); «открытие» — анимация/resize content, не отдельный window show.

---

## 3) Вкладки / секции контента

**Только 2 вкладки: Home, Shelf.** Tray как отдельной вкладки **нет** (иконка shelf = `tray.fill`).

| Что | Где |
|-----|-----|
| Enum вкладок | `NotchViews { home, shelf }` — `enums/generic.swift:27–30` |
| Реестр UI-табов | `let tabs = [Home, Shelf]` — `components/Tabs/TabSelectionView.swift:17–20` |
| Tab UI | `TabSelectionView` + `TabButton` — `components/Tabs/` |
| Текущая вкладка | `BoringViewCoordinator.currentView` — `BoringViewCoordinator.swift:53` |
| Switch контента | `ContentView` switch — `ContentView.swift:347–351` → `NotchHomeView` / `ShelfView` |
| Показ табов в header | `BoringHeader` если shelf не пуст или `alwaysShowTabs` — `components/Notch/BoringHeader.swift:19–20` |
| Home view | `components/Notch/NotchHomeView.swift` (struct ~421) |
| Shelf view | `components/Shelf/Views/ShelfView.swift` |

### Как добавить новую вкладку
1. `case foo` в `NotchViews` — `enums/generic.swift:27–30`
2. `TabModel(..., view: .foo)` в `tabs` — `TabSelectionView.swift:17–20`
3. `case .foo: FooView()` в switch — `ContentView.swift:347–351`
4. (опц.) дефолт currentView при open/close — `BoringViewModel.close` / coordinator

---

## 4) Clipboard / Shelf для файлов

### Shelf (полноценный file tray) — **да**
Каталог `boringNotch/components/Shelf/`:

| Слой | Файлы |
|------|-------|
| Models | `Models/ShelfItem.swift` (kinds: file/text/link), `Models/Bookmark.swift` |
| VM | `ViewModels/ShelfStateViewModel.swift`, `ShelfItemViewModel.swift`, `ShelfSelectionModel.swift` |
| Views | `Views/ShelfView.swift`, `ShelfItemView.swift`, `DragPreviewView.swift`, `FileShareView.swift` |
| Services | `ShelfDropService.swift`, `ShelfPersistenceService.swift` (Application Support `boringNotch/Shelf/items.json`), `ShelfActionService.swift` (copy to NSPasteboard), `QuickLookService`, `QuickShareService`, `ShareServiceFinder`, `TemporaryFileStorageService`, `ThumbnailService`, `ImageProcessingService` |
| Drag open | `observers/DragDetector.swift` (global NSEvent mouse + drag pasteboard) |
| Drop on ContentView | ContentView drop delegates ~618+; `onDrop` 364 |
| Settings keys | `Constants.swift:165–172` (`boringShelf`, `openShelfByDefault`, …) |

`ShelfItemKind`: `.file(bookmark)`, `.text(string)`, `.link(url)` — `ShelfItem.swift:11–14`.

### Clipboard history panel — **не реализован как фича**
- Shortcut name `clipboardHistoryPanel` (Cmd+Shift+C) — `ShortcutConstants.swift:12`
- **Нет** `KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel)`
- Tip-текст «Clipboard Manager» — `components/Tips/TipStore.swift:35` (маркетинг/tip, не код)
- Helpers pasteboard → attributed string: `helpers/Clipboard+Content.swift` (утилиты, не history manager)

Shelf **копирует в** pasteboard при действиях (`ShelfActionService.swift:24–25`, `ShelfItemViewModel` ~506+), но не ведёт историю буфера.

---

## 5) Клавиатура внутри шторки

| Механизм | Назначение | Координаты |
|----------|------------|------------|
| **KeyboardShortcuts** (sindresorhus) | global hotkeys: toggleNotchOpen, toggleSneakPeek | App:354–411; names: `ShortcutConstants.swift:11–17` |
| SwiftUI `.keyboardShortcut` | MenuBar Settings Cmd+,, Quit Cmd+Q; context Settings; onboarding | App:38,47; ContentView:191; OnboardingFinishView |
| **NSEvent local monitor** | scrollWheel pan-gestures open/close | `extensions/PanGesture.swift:89–93` |
| **NSEvent global monitor** | mouse drag for shelf open (не keyboard) | `DragDetector.swift:55–92` |
| **CGEvent tap** | media/brightness keys → HUD | `observers/MediaKeyInterceptor.swift` (eventTap:28, start:47+) |
| SwiftUI `onKeyPress` | **не найден** | — |

Внутри notch-контента отдельного keyboard focus-router нет; взаимодействие — hover/gesture/mouse + global shortcuts.

---

## 6) Настройки

### Основное хранилище: пакет **Defaults** (sindresorhus)
- Keys: `extension Defaults.Keys` — `models/Constants.swift:71–202`
- Чтение: `Defaults[.key]`, `@Default(.key)` (SettingsView и др.)
- Пример UI: `components/Settings/SettingsView.swift` (`@Default` ~138+)
- Settings window: `components/Settings/SettingsWindowController.swift`

### Также @AppStorage (UserDefaults) в coordinator
- `firstLaunch`, `showWhatsNew`, `musicLiveActivityEnabled`, `currentMicStatus`, `alwaysShowTabs`, `openLastTabByDefault` — `BoringViewCoordinator.swift:59–75`

### Как добавить новую настройку
1. `static let myFlag = Key<Bool>("myFlag", default: false)` в `Defaults.Keys` — `Constants.swift:71+`
2. UI: `@Default(.myFlag)` или `Defaults[.myFlag] =` в SettingsView (или отдельная секция)
3. При необходимости `Defaults.Serializable` для enum (см. enums в `Constants.swift` / `generic.swift`)

`UserDefaults.standard` напрямую: точечно (напр. MediaKeyInterceptor beep feedback, MediaKeyInterceptor:179).

---

## 7) Собираемость: `xcodebuild -list`

### Без полного Xcode (default xcode-select → CLT)
```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
'/Library/Developer/CommandLineTools' is a command line tools instance
```

### С `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Xcode: **16.1** (Build 16B40)
- Команда: `xcodebuild -list -project boringNotch.xcodeproj`
- **Exit code 74** — package resolve failed, список schemes/targets **не напечатан**

Полный релевантный вывод ошибки:
```
package 'keyboardshortcuts' @ 2.4.0 is using Swift tools version 6.1.0 but the installed version is 6.0.0
package 'macrovisionkit' @ 0.2.0 is using Swift tools version 6.1.0 but the installed version is 6.0.0
fatalError
xcodebuild: error: Could not resolve package dependencies:
  package 'keyboardshortcuts' @ 2.4.0 is using Swift tools version 6.1.0 but the installed version is 6.0.0
  package 'macrovisionkit' @ 0.2.0 is using Swift tools version 6.1.0 but the installed version is 6.0.0
  fatalError
```

**Вывод:** на текущем Xcode 16.1 / Swift 6.0.0 проект **не резолвит SPM** (нужен Swift tools ≥ 6.1, т.е. более новый Xcode). Полный build не проверялся; `-list` уже падает на resolve.

Targets из pbxproj (если resolve пройдёт): `boringNotch`, `BoringNotchXPCHelper`.

---

## Краткая карта «куда лезть»

```
boringNotchApp.swift          → @main + AppDelegate + window create + hotkeys
ContentView.swift             → notch layout, open/close UI, tab content switch
components/Notch/             → SkyLight window, header, home
components/Tabs/              → tab registry
components/Shelf/             → file/text/link shelf
models/Constants.swift        → Defaults keys
enums/generic.swift           → NotchViews / NotchState
Shortcuts/ShortcutConstants   → KeyboardShortcuts names
```
