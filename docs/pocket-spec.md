# Pocket — спецификация интеграции (boring.notch + ядро Maccy, UI в стиле Pasta)

## Цель
Из клона boring.notch (`/Users/user/Dev/vibecode/Pocket/boring notch`) сделать умный буфер обмена в шторке нотча:
история буфера обмена с функциональностью Maccy, отображаемая карточками в стиле Pasta, с навигацией стрелками и W/A/S/D.

Рабочая директория (единственный владелец записи): `/Users/user/Dev/vibecode/Pocket/boring notch`.
Клон Maccy (`/Users/user/Dev/vibecode/Pocket/Maccy`) — ТОЛЬКО читать/копировать из него, не изменять.

## Подтверждённые факты (из разведки)

### boring.notch
- Проект: `boringNotch.xcodeproj`, targets `boringNotch` + `BoringNotchXPCHelper`, macOS 14.0, SPM.
- Entry: `@main DynamicNotchApp` + AppDelegate — `boringNotch/boringNotchApp.swift:15–52`; окно создаётся в `createBoringNotchWindow` (App:234–265), класс `BoringNotchSkyLightWindow` (NSPanel, styleMask `.borderless,.nonactivatingPanel,.utilityWindow,.hudWindow`) — `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:34`.
- Открытие/закрытие: `BoringViewModel.open()/close()` — `models/BoringViewModel.swift:192–218`; hover/gesture в `ContentView.swift:506–582`; глобальный хоткей toggleNotchOpen (Cmd+Shift+I) — App:368–411.
- Вкладки: enum `NotchViews { home, shelf }` — `enums/generic.swift:27–30`; реестр `tabs` — `components/Tabs/TabSelectionView.swift:17–20`; switch контента — `ContentView.swift:347–351`; текущая вкладка `BoringViewCoordinator.currentView` — `BoringViewCoordinator.swift:53`.
- Shelf (файловый трей) уже есть: `components/Shelf/**`. Истории буфера обмена НЕТ; есть только незанятый shortcut name `clipboardHistoryPanel` (Cmd+Shift+C) — `Shortcuts/ShortcutConstants.swift:12`, обработчик не зарегистрирован.
- Настройки: пакет Defaults, ключи в `models/Constants.swift:71–202`; Settings UI `components/Settings/SettingsView.swift`.
- Клавиатурного focus-роутера внутри шторки нет (только hover/gesture/global shortcuts).
- БЛОКЕР: на Xcode 16.1 (Swift tools 6.0) `xcodebuild -list` падает: пакеты `keyboardshortcuts @ 2.4.0` и `macrovisionkit @ 0.2.0` требуют Swift tools 6.1.
- Уже прилинкованы SPM: LaunchAtLogin, Sparkle 2.9.1, KeyboardShortcuts 2.4.0, swift-collections, Defaults 9.0.6, SwiftUIIntrospect, SkyLightWindow, Lottie, AsyncXPCConnection, MacroVisionKit.

### Maccy (донор ядра)
- Ядро: `Maccy/Clipboard.swift` (Timer-поллинг NSPasteboard.general, интервал `Defaults[.clipboardCheckInterval]` = 0.5s, сравнение changeCount; copy(item) — запись в pasteboard; paste() — CGEvent Cmd+V через Sauce + AXIsProcessTrusted, `Clipboard.swift:113–139`).
- Модели SwiftData: `Models/HistoryItem.swift` (application, firstCopiedAt, lastCopiedAt, numberOfCopies, pin, title, contents; computed: text/rtf/html/image/fileURLs), `Models/HistoryItemContent.swift` (type, value, item). Схема: `Storage.xcdatamodeld`.
- Хранилище: `Storage.swift` → SQLite в Application Support.
- Дедуп: `History.add` + `HistoryItem.supersedes` (`History.swift:138–172`, `HistoryItem.swift:78–87`); лимит: `History.limitHistorySize` (только незапиненные, default 200); pin: `History.togglePin`; игнор приложений/типов/regex: `Clipboard.shouldIgnore*` (`Clipboard.swift:233–263`); поиск: `Search.swift` (exact/fuzzy/regexp, Fuse).
- Переиспользуемые без UI файлы: `Clipboard.swift`, `Accessibility.swift`, `Models/*`, `Storage.swift`, `Storage.xcdatamodeld`, `Extensions/Defaults.Keys+Names.swift`, `Extensions/NSPasteboard.PasteboardType+Types.swift`, `KeyChord.swift`, `KeyboardLayout.swift`, `Extensions/Sauce+KeyboardShortcuts.swift`, `Extensions/String+Shortened.swift`, `Sorter.swift`, `HistoryItemAction.swift`, `Throttler.swift`, `Search.swift` (там `typealias Searchable = HistoryItemDecorator` — заменить на свой тип).
- Логику add/dedup/limit из `Observables/History.swift` извлечь в headless-менеджер (без AppState/popup).

## Принятые решения (не пересматривать)
1. Основа — существующий проект `boringNotch.xcodeproj`; НЕ создавать новый проект, НЕ переименовывать targets/bundle id.
2. Ядро Maccy портировать копированием файлов в новую папку `boringNotch/components/ClipboardHistory/` (подпапки Core/, Models/, Views/), адаптируя под Defaults 9.x и существующие конвенции проекта. UI Maccy не портировать.
3. Новая вкладка `clipboard` в шторке: case в `NotchViews`, TabModel в `TabSelectionView` (иконка например `doc.on.clipboard`), case в switch `ContentView.swift:347–351`.
4. Хранилище: SQLite в `Application Support/boringNotch/ClipboardHistory.sqlite` (не Maccy).
5. Новые SPM-зависимости: добавить Sauce (для paste) и fuse-swift (fuzzy поиск). Конфликтные дубликаты не добавлять — использовать уже имеющиеся Defaults/KeyboardShortcuts из boring.notch.
6. Разблокировка сборки на Xcode 16.1 / Swift 6.0: понизить пин KeyboardShortcuts до последней версии с tools ≤ 6.0 (например 2.3.x или 2.0.2 — проверить резолв); MacroVisionKit 0.2.0 → понизить до совместимой версии, а если её нет — свендорить пакет локально (скопировать исходники в проект или local SPM package с пониженным swift-tools-version) без изменения поведения. Функциональность не удалять.
7. Ключи настроек clipboard-фичи добавить в `Defaults.Keys` в `Constants.swift` с префиксом `clipboard*` (enabled, checkInterval, historySize default 200, pasteAutomatically, ignoredApps). Секция настроек в SettingsView — минимальная.
8. Хоткей: зарегистрировать обработчик существующего `clipboardHistoryPanel` (Cmd+Shift+C) в AppDelegate по образцу toggleNotchOpen (App:368–411): открыть шторку сразу на вкладке clipboard.

## UI — карточки в стиле Pasta
- Внутри вкладки clipboard: горизонтально скроллируемая лента карточек (LazyHGrid, 1 ряд при текущей высоте шторки; если помещается — допустимо 2 ряда для компактных карточек).
- Карточка (~140×120, скругление, тёмный материал в стиле boring.notch):
  - шапка: иконка приложения-источника (по bundle id из `HistoryItem.application`) + тип контента; индикатор pin;
  - тело: превью — текст (несколько строк), изображение (thumbnail), файл (имя+иконка), ссылка;
  - низ: относительное время копирования.
- Поле поиска в ряду с табами или над лентой (появляется на вкладке clipboard); фильтрация через портированный Search.
- Взаимодействия: клик по карточке = скопировать в буфер; двойной клик или Enter = вставить в активное приложение (copy + paste через CGEvent); контекстное меню: Pin/Unpin, Copy, Paste, Delete; Delete-клавиша удаляет выбранную; Escape закрывает шторку.
- Выделенная карточка подсвечивается рамкой/scale-эффектом.

## Клавиатурная навигация (критично)
- Стрелки ←→ (и ↑↓ при 2 рядах) И клавиши W/A/S/D перемещают выделение: A/← влево, D/→ вправо, W/↑ вверх/ряд выше, S/↓ вниз. Автопрокрутка к выделенной карточке (ScrollViewReader).
- Проблема: окно — nonactivating NSPanel, key-события в него не приходят. Решение: когда шторка открыта И активна вкладка clipboard — разрешить панели становиться key (override `canBecomeKey` в BoringNotchSkyLightWindow / условно) и вызвать `makeKey`; поставить локальный NSEvent monitor `keyDown` (W/A/S/D, стрелки, Enter, Delete, Escape) только на время видимости вкладки; при закрытии шторки/смене вкладки — снять монитор и вернуть key-статус прежнему приложению (важно: paste должен уйти в предыдущее frontmost-приложение — перед синтезом Cmd+V вернуть фокус, как делает Maccy: панель nonactivating + запомнить/не красть activation, либо resignKey перед paste).
- Если canBecomeKey ломает hover-UX или события не приходят — fallback: глобальный CGEvent tap keyDown (Accessibility уже нужна для paste), перехватывающий эти клавиши только при открытой вкладке clipboard.
- Поиск-поле: при фокусе в поле поиска W/A/S/D вводятся как текст (не перехватывать), стрелки/Enter продолжают работать для навигации.

## Границы
- Не менять функциональность Home/Shelf/медиа-фич boring.notch.
- Не трогать репозиторий Maccy.
- Не делать git commit/push, не создавать PR.
- Не переименовывать проект/target/bundle.
- Sparkle-автообновления и App Intents Maccy не переносить.

## Приёмка (проверяемые критерии)
1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "boringNotch.xcodeproj" -scheme boringNotch -configuration Debug build` завершается успешно (exit 0), из корня `boring notch`.
2. В коде: `NotchViews` содержит case clipboard; TabSelectionView регистрирует вкладку; ContentView switch рендерит ClipboardHistoryView.
3. Ядро: сервис поллинга запускается из AppDelegate при `Defaults[.clipboardEnabled]`; новые копии (string/rtf/html/png/tiff/fileURL) сохраняются в SwiftData; дедуп supersedes; лимит незапиненных; pin/unpin; delete; clear.
4. Paste: выбор карточки → запись в NSPasteboard; Enter/двойной клик → синтез Cmd+V (через Sauce) с проверкой AXIsProcessTrusted.
5. Навигация: обработчик клавиш реагирует на стрелки И на W/A/S/D; Enter=paste, Delete=удалить, Escape=закрыть.
6. Хоткей Cmd+Shift+C открывает шторку на вкладке clipboard.
7. Приложение запускается (open build product или xcodebuild + запуск) без крэша в первые секунды; шторка отображается.

## Отчёт исполнителя (обязательный формат)
- Список изменённых/добавленных файлов.
- Как решён блокер Swift 6.1 (какие пины/вендоринг).
- Вывод финальной команды сборки (последние строки с BUILD SUCCEEDED).
- Отклонения от спецификации и почему.
- Что не удалось проверить и оставшиеся риски.
Если реальность противоречит спецификации — остановиться и вернуть расхождение через ask, не принимать продуктовые решения самостоятельно.
