# Pocket — независимая приёмка (verification)

Дата: 2026-07-20  
Проект: `/Users/user/Dev/vibecode/Pocket/boring notch`  
Спека: `docs/pocket-spec.md` § «Приёмка»  
Отчёт исполнителя: `boring notch/.orca/implementation-report.md` (перепроверен, не принят на слово)

**Итоговый вердикт: ПРИНЯТЬ С ЗАМЕЧАНИЯМИ**

Критерии 1–6 по **коду + чистой сборке + smoke** закрыты. Runtime UX (WASD/Cmd+Shift+C/paste в другое app) **не гонялся GUI** — отмечен как НЕПРОВЕРЯЕМО. Найдены реальные дефекты, не блокирующие приёмку по тексту спеки, но требующие follow-up.

---

## 1) Чистая сборка

Команда (из корня `boring notch`):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/pocket-verify-dd build
```

**Результат: exit 0, `** BUILD SUCCEEDED **`**

Последние строки:
```
Validate /tmp/pocket-verify-dd/Build/Products/Debug/boringNotch.app ...
Touch /tmp/pocket-verify-dd/Build/Products/Debug/boringNotch.app ...
RegisterWithLaunchServices ... boringNotch.app
note: Disabling hardened runtime with ad-hoc codesigning.
** BUILD SUCCEEDED **
```

Продукт: `/tmp/pocket-verify-dd/Build/Products/Debug/boringNotch.app`  
SPM resolved: KeyboardShortcuts **2.3.0**, Sauce **2.4.1**, fuse-swift **1.4.0**, Defaults 9.0.6; MacroVisionKit local Vendor.

| Пункт | Вердикт |
|---|---|
| Приёмка 1 (build) | **PASS** |

---

## 2) Приёмка 2–6 по коду (file:line)

### 2. Вкладка clipboard
| Требование | Координаты | Вердикт |
|---|---|---|
| `NotchViews.clipboard` | `boringNotch/enums/generic.swift:27-30` | **PASS** |
| TabSelectionView | `TabSelectionView.swift:17-20` — TabModel Clipboard `doc.on.clipboard` | **PASS** |
| ContentView switch | `ContentView.swift:357-363` — `case .clipboard: ClipboardHistoryView()` | **PASS** |

### 3. Ядро: poll / SwiftData / dedup / limit / pin / delete / clear
| Требование | Координаты | Вердикт |
|---|---|---|
| Старт поллинга из AppDelegate при enabled | `boringNotchApp.swift:443-447` — `if Defaults[.clipboardEnabled] { ClipboardHistoryManager.shared.start() }` | **PASS** |
| start → Timer | `ClipboardHistoryManager.swift:28-40` → `ClipboardService.start()`; timer `ClipboardService.swift:52-63` interval `Defaults[.clipboardCheckInterval]` | **PASS** |
| Типы string/rtf/html/png/tiff/fileURL | supported `ClipboardService.swift:24-26`; default enabled `Constants.swift:181-183` + `ClipboardStorageType.all`; запись `contents.append` `ClipboardService.swift:175-176` | **PASS** |
| SwiftData storage path | `ClipboardStorage.swift:26-33` → `Application Support/boringNotch/ClipboardHistory.sqlite`; models `HistoryItem`/`HistoryItemContent` | **PASS** |
| supersedes dedup | `HistoryItem.supersedes` `HistoryItem.swift:41-49`; `findSimilarItem` `ClipboardHistoryManager.swift:258-263`; merge+delete existing `94-109` | **PASS** |
| limit unpinned | `limitHistorySize` `ClipboardHistoryManager.swift:247-256`; default 200 `Constants.swift:178` | **PASS** |
| pin/unpin | `togglePin` `ClipboardHistoryManager.swift:145-154` pin=`"•"`; UI context menu `ClipboardCardView.swift:48` | **PASS** |
| delete | `delete`/`deleteSelected` `121-132`; key `ClipboardKeyboardMonitor.swift:62-65` | **PASS** |
| clear unpinned | `clearUnpinned` `134-143`; Settings button `SettingsView.swift:1784-1786` | **PASS** |

### 4. Copy / Paste (Sauce + CGEvent + AX)
| Требование | Координаты | Вердикт |
|---|---|---|
| Клик = copy | `ClipboardHistoryView.swift:78-80` → `ClipboardService.shared.copy(item)`; copy writes pasteboard `ClipboardService.swift:75-103` | **PASS** |
| Enter / double-click = paste | Enter `ClipboardHistoryView.swift:131-133`; doubleTap `82-85`; `pasteSelected`/`pasteItem` `161-185` | **PASS** |
| CGEvent Cmd+V via Sauce | `ClipboardService.paste()` `106-128`: Sauce `keyCode(for: .v)`, CGEvent keyDown/Up, `.cgSessionEventTap` | **PASS** |
| AX check | `ClipboardAccessibility.check()` `ClipboardAccessibility.swift:13-16` via `AXIsProcessTrustedWithOptions`; called `ClipboardService.swift:107` | **PASS** (как Maccy: check **не блокирует** paste и **не промптает**; `requestIfNeeded` **нигде не вызывается**) |

### 5. Навигация клавиатурой
| Требование | Координаты | Вердикт |
|---|---|---|
| Стрелки + WASD | `ClipboardKeyboardMonitor.swift:84-115`; move → `manager.moveSelection` `ClipboardHistoryView.swift:128-129` | **PASS** (код) |
| Enter=paste, Delete=delete, Escape=close | `56-65`, handlers `131-139` | **PASS** (код) |
| WASD не перехват при фокусе поиска | `setSearchFocused` `31-32` / `23-25`; early return `76-78` если search focused && !arrow | **PASS** (код) |
| canBecomeKey + makeKey | `BoringNotchSkyLightWindow.swift:36-37,89-96,125`; post `.clipboardTabKeyFocus` `ClipboardHistoryView.swift:151-157`; cleanup `ContentView.swift:169-178` | **PASS** (код) |
| Runtime key delivery | Local monitor only (`addLocalMonitorForEvents`) — **без** global/CGEvent-tap fallback из спеки | **НЕПРОВЕРЯЕМО ЗДЕСЬ** (нет GUI-автоматизации); риск: local monitor может не получать keyDown, если app/window не key |

### 6. Хоткей Cmd+Shift+C
| Требование | Координаты | Вердикт |
|---|---|---|
| Default shortcut | `ShortcutConstants.swift:12` — `.c` + shift+command | **PASS** |
| Handler opens notch on clipboard tab | `boringNotchApp.swift:413-440` — `currentView = .clipboard` + `viewModel.open()` | **PASS** (код) |
| Runtime hotkey | — | **НЕПРОВЕРЯЕМО ЗДЕСЬ** (нужен живой GUI + Accessibility/KeyboardShortcuts) |

---

## 3) Сверка порта с Maccy (read-only `/Users/user/Dev/vibecode/Pocket/Maccy`)

| Поведение Maccy | В порте | Вердикт |
|---|---|---|
| changeCount detection | `ClipboardService.swift:138-140` | **сохранено** |
| ignoredTypes autoGenerated/concealed/transient | `ClipboardService.swift:27-29` + `PasteboardTypes.swift` | **сохранено** |
| ignoredApps | `shouldIgnore(bundle)` `197-199` + `Defaults.clipboardIgnoredApps` | **сохранено** (только blacklist) |
| ignoreRegexp | `shouldIgnore(item)` `201-214` + `clipboardIgnoreRegexp` | **сохранено** (ключ есть; UI для regex **не найден**) |
| multi-item merge (forEach pasteboardItems) | `ClipboardService.swift:155-178` | **сохранено** |
| skip own writes (.fromMaccy) | `142-145` | **сохранено** |
| dyn./microsoft source strip | `166-173` | **сохранено** |
| ignoreAllAppsExceptListed (whitelist mode) | **отсутствует** | **потеряно** |
| ignoreEvents / ignoreOnlyNextEvent | **отсутствует** | **потеряно** |
| sessionLog + modified pasteboard type | **отсутствует** | **потеряно** (advanced dedup edge) |
| KeyChord paste from Edit menu | hardcode Key.v + command | **упрощено** (приемлемо) |
| AX check empty when untrusted | same no-op pattern | **как Maccy** |

---

## 4) Smoke

```
open /tmp/pocket-verify-dd/Build/Products/Debug/boringNotch.app
# wait 5s
```

Наблюдение:
- PID `boringNotch` жив ≥5s (state S), путь `/private/tmp/pocket-verify-dd/.../boringNotch`
- XPC helper + mediaremote-adapter.pl тоже живы
- kill -9 по имени `boringNotch` — чисто

| Приёмка 7 (запуск без крэша) | **PASS** (smoke ≥5s) |
| Шторка отображается | **НЕПРОВЕРЯЕМО ЗДЕСЬ** (menubar/notch, нет визуальной проверки) |

---

## 5) Найденные дефекты / мёртвый код

| # | Severity | Факт |
|---|---|---|
| D1 | Medium | **`clipboardPasteAutomatically` мёртвый**: toggle в `SettingsView.swift:1751-1753`, key `Constants.swift:179`, **нет чтений** в paste/Enter path. Enter всегда paste. Toggle вводит в заблуждение («Paste automatically on Enter»). |
| D2 | Medium | **Delete при фокусе поиска** перехватывается до check search: `ClipboardKeyboardMonitor.swift:62-65` **до** `76-78`. В поле поиска Delete не удаляет символы query — всегда `deleteSelected`. Спека явно требует только WASD passthrough; Delete — usability bug. |
| D3 | Low | **`ClipboardAccessibility.requestIfNeeded()`** (`ClipboardAccessibility.swift:18-21`) **нигде не вызывается**. `check()` не промптает. Paste без AX может молча noop (как Maccy). |
| D4 | Low/Port | Потеря Maccy: `ignoreEvents`, `ignoreAllAppsExceptListed`, `sessionLog`/modified. |
| D5 | Risk | Только **local** key monitor; fallback global/CGEvent tap из спеки **не реализован**. Cleanup monitor OK: `stop()` + `removeMonitor`, `[weak self]` — **retain-цикла монитора нет**. Timer `target: self` на singleton — OK при `stop()`. |
| D6 | Nit | `BoringNotchWindow.canBecomeKey` всегда false (`BoringNotchWindow.swift:43-45`); фактическое окно — SkyLight — OK. |
| D7 | Nit | `clipboardPasteAutomatically` label vs behavior mismatch; 2-row cards not implemented (reported by executor, height OK). |

Заглушек типа `// TODO` / empty stub handlers в clipboard path **не найдено**. Handlers Enter/Delete/Escape/WASD **привязаны** в `setupKeyboard` при `onAppear` вкладки — не «мёртвые» callbacks.

---

## Сводка вердиктов

| # | Критерий | Вердикт |
|---|---|---|
| 1 | Clean build | **PASS** |
| 2 | Tab wiring | **PASS** |
| 3 | Core poll/storage/dedup/limit/pin/delete/clear | **PASS** |
| 4 | Copy + paste Sauce/CGEvent/AX | **PASS** (AX check no-op when untrusted) |
| 5 | Keyboard arrows/WASD/Enter/Delete/Esc + search WASD | **PASS** код; runtime **НЕПРОВЕРЯЕМО**; D2 Delete-in-search |
| 6 | Cmd+Shift+C → clipboard tab | **PASS** код; runtime **НЕПРОВЕРЯЕМО** |
| 7 | Launch smoke | **PASS** (≥5s); notch UI **НЕПРОВЕРЯЕМО** |
| Port fidelity | changeCount/ignore types/apps/regex/multi-item | **PASS** core; gaps D4 |

---

## Решение

**ПРИНЯТЬ С ЗАМЕЧАНИЯМИ.**

Обоснование: обязательные проверяемые пункты приёмки 1–6 реализованы в коде с конкретными координатами; чистая сборка и smoke без крэша прошли независимо.  

Вернуть целиком **не** требуется, но follow-up желателен:
1. Подключить или убрать `clipboardPasteAutomatically` (D1).
2. Не перехватывать Delete при `isSearchFocused` (D2).
3. Вызвать `requestIfNeeded` при первом paste или document AX requirement (D3).
4. Ручной GUI smoke: Cmd+Shift+C, WASD, paste в TextEdit.
5. (Опционально) port ignoreEvents / whitelist apps.
