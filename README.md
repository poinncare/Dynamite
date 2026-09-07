<p align="center">
  <img src="docs/app-icon.png" alt="Иконка Dynamite" width="180">
</p>

<h1 align="center">Dynamite</h1>

<p align="center">
  Умная macOS-шторка для MacBook с выемкой: музыка, live activities, буфер обмена, файловая полка и usage AI-сервисов в одном месте.
</p>

<p align="center">
  <a href="https://github.com/poinncare/Dynamite/releases/latest"><img src="https://img.shields.io/github/v/release/poinncare/Dynamite?display_name=tag&label=релиз" alt="Последний релиз"></a>
  <a href="https://github.com/poinncare/Dynamite/actions/workflows/cicd.yml"><img src="https://github.com/poinncare/Dynamite/actions/workflows/cicd.yml/badge.svg" alt="Сборка и тесты"></a>
  <a href="https://github.com/poinncare/Dynamite/blob/main/DynamiteApp/LICENSE"><img src="https://img.shields.io/badge/лицензия-MIT-blue.svg" alt="Лицензия MIT"></a>
</p>

> Dynamite превращает выемку MacBook в компактный центр управления системой. Проект также известен как Pocket — название, которое используется в отдельных экранах и внутренних компонентах приложения.

## Возможности

- Управление музыкой и Now Playing прямо из шторки.
- Live activities: проигрывание, загрузки, батарея, громкость, яркость и другие системные события.
- Календарь и напоминания без переключения между окнами.
- Shelf — файловая полка с drag-and-drop и поддержкой AirDrop.
- Clipboard — локальная история буфера обмена с быстрым поиском и вставкой.
- Space — usage Claude, Codex и Grok; установленные CLI-агенты определяются автоматически.
- Настройка жестов, размера шторки, внешнего вида и поведения на нескольких дисплеях.
- Заменяемый системный HUD для громкости, яркости и подсветки клавиатуры.

<p align="center">
  <img src="DynamiteApp/docs/clipboard-ui-iter7-home.png" alt="Главный экран Dynamite" width="48%">
  <img src="DynamiteApp/docs/clipboard-ui-iter7-clip.png" alt="История буфера обмена Dynamite" width="48%">
</p>

## Установка

### Готовое приложение

Скачайте последнюю версию на странице [Releases](https://github.com/poinncare/Dynamite/releases/latest), откройте DMG и переместите `Dynamite.app` в `/Applications`.

Так как приложение пока не подписано аккаунтом Apple Developer, macOS может показать предупреждение о неизвестном разработчике. Если приложение не открывается, выполните:

```bash
xattr -dr com.apple.quarantine /Applications/Dynamite.app
```

### Homebrew

```bash
brew install --cask TheBoredTeam/dynamite/dynamite
```

## Системные требования

- macOS 14 Sonoma или новее.
- Apple Silicon или Intel.

## Сборка из исходников

Нужны macOS 15.6 или новее и Xcode 26 или новее.

```bash
git clone https://github.com/poinncare/Dynamite.git
cd Dynamite/DynamiteApp
xcodebuild -project Dynamite.xcodeproj \
  -scheme Dynamite \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Также проект можно открыть в Xcode:

```bash
open Dynamite.xcodeproj
```

## Приватность

Dynamite работает локально. История буфера обмена хранится на этом Mac, а usage читается из локальных сессий CLI-провайдеров. Подробнее — в [политике безопасности](DynamiteApp/SECURITY.md).

## Участие в разработке

Идеи, баг-репорты и pull request приветствуются. Перед началом работы ознакомьтесь с [CONTRIBUTING.md](DynamiteApp/CONTRIBUTING.md).

## Ключевые слова

`macOS notch` · `Dynamic Island для Mac` · `MacBook notch app` · `menubar app` · `clipboard manager` · `clipboard history` · `file shelf` · `AirDrop shelf` · `live activities` · `SwiftUI` · `Claude usage` · `Codex usage` · `Grok usage`

## Благодарности

- [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter) — источник Now Playing для новых версий macOS.
- [NotchDrop](https://github.com/Lakr233/NotchDrop) — вдохновение для первой версии Shelf.
- [Maccy](https://github.com/p0deje/Maccy) — донор ядра истории буфера обмена.

Полный список лицензий и атрибуций находится в [THIRD_PARTY_LICENSES](DynamiteApp/THIRD_PARTY_LICENSES).

Если Dynamite оказался полезен, поставьте ⭐ репозиторию и поделитесь им с другими пользователями MacBook.
