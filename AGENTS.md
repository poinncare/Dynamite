# AGENTS.md — Dynamite / Pocket

Инструкции для агентов, работающих в этом репозитории.

## Что это

Умная macOS-шторка (notch) с вкладками и гибкими настройками.


| Источник                                                     | Роль                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| [Dynamite](https://github.com/poinncare/Dynamite)          | Основа приложения (`DynamiteApp/`)                       |
| [Maccy](https://github.com/p0deje/Maccy)                     | Донор ядра буфера обмена (только читать; UI не портируем)    |
| [CodexBar](https://github.com/steipete/CodexBar)             | Планируемая вкладка usage AI-подписок (ещё не интегрирована) |


## Обязательный workflow после изменений

После **каждого** изменения, которое должно быть видно пользователю:

1. Собрать Debug:
  ```bash
   cd "DynamiteApp"
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
   xcodebuild -project Dynamite.xcodeproj -scheme Dynamite \
     -configuration Debug -destination 'platform=macOS' \
     -derivedDataPath "../build/DerivedData" build
  ```
2. Задеплоить в `/Applications` и перезапустить:
  ```bash
   APP_SRC="../build/DerivedData/Build/Products/Debug/Dynamite.app"
   APP_DST="/Applications/Dynamite.app"
   pkill -x Dynamite 2>/dev/null || true
   rm -rf "$APP_DST"
   ditto "$APP_SRC" "$APP_DST"
   xattr -cr "$APP_DST" 2>/dev/null || true
   open "$APP_DST"
  ```
3. Убедиться, что процесс жив (`pgrep -x Dynamite`).

Пользователь смотрит `**/Applications/Dynamite.app**`, не build product из DerivedData.

## Вкладки шторки


| Вкладка             | Состояние                                                                                                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Home                | Медиа / live activities                                                                                                                                                                                 |
| Shelf               | Drag-and-drop файловый трей                                                                                                                                                                             |
| Clipboard           | История буфера (карточки)                                                                                                                                                                               |
| Space / Usage       | Вкладка usage в шторке (Claude / Codex / Grok); Settings → Space: agents + refresh; автодетекция CLI как в [orca](https://github.com/stablyai/orca); usage обновляется без restart |


## Границы

**Не** commit/push/PR без явной просьбы пользователя.

