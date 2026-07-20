# Pocket iteration 2 — независимая приёмка

Проект: `/Users/user/Dev/vibecode/Pocket/boring notch`  
Спека: `docs/pocket-iteration2-spec.md` § Приёмка (1–8) + i18n  
Отчёты исполнителя: `.orca/iteration2-report.md`, `.orca/i18n-complete-report.md` (факты перепроверены)

**Итог: ПРИНЯТЬ С ЗАМЕЧАНИЯМИ**

---

## 1. Чистая сборка — PASS
```
DEVELOPER_DIR=... xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination platform=macOS -derivedDataPath /tmp/pocket-verify3-dd build
```
Exit 0. Хвост:
```
Validate /tmp/pocket-verify3-dd/Build/Products/Debug/boringNotch.app
...
** BUILD SUCCEEDED **
```

## 2. Поиск удалён / нет isSearchFocused — PASS
| Проверка | Факт |
|---|---|
| UI поиска | `ClipboardHistoryView` — нет TextField/search bar; full-height cards (`:59-72`, body only strip) |
| `isSearchFocused` | `rg` по `boringNotch` → **0** совпадений |
| Residual (замечание) | `ClipboardHistoryManager.searchQuery` + `applySearch` + `ClipboardSearch.swift`/`fuse` ещё в target (пустой query → all items). Не isSearchFocused; dead-ish backend. Спека допускает оставить fuse. |

## 3. Хоткей = toggle, без 3с autoclose — PASS
`boringNotchApp.swift:413-447`:
- `closeNotchTask?.cancel(); closeNotchTask = nil` — **нет** sleep(3) (в отличие от `toggleNotchOpen` `:396-404`)
- closed → `currentView = .clipboard` + `open()`
- open + clipboard → `close()`
- open + other → switch to clipboard only

## 4. Space-попап + блок навигации — PASS
| | |
|---|---|
| Popup UI | `ClipboardHistoryView.swift:36-38, 146-191` — 80% size, scroll, dimmed tap outside |
| Toggle Space | `onSpace` → `togglePopup()` `:233-234`; monitor `:100-104` |
| Close Escape | `:226-231` closePopup if open |
| Close click outside | `:163-164` |
| Text/link only | `popupText` `.text`/`.link` only `:148-155` |
| Nav blocked | monitor `popupOpen` `:91-98` — no nav callbacks; `onMove` guard `:210-212`; delete guard `:222-224` |

## 5. Футер: иконка L / time R / now·Nm·Nh·Nd + refresh — PASS
| | |
|---|---|
| Icon bottom-left | `ClipboardCardView.swift:30-50` HStack footer |
| Time bottom-right | `footerTrailing` `:80-91` |
| No content-type glyph | нет systemImage type в header/body |
| Format | `ClipboardRelativeTime.swift:9-24` — `<60→now`, `Nm`, `Nh`, `Nd` |
| Refresh | `ClipboardHistoryView.swift:51-53` Timer **30s** updates `now` |
| Screenshot | `docs/clipboard-ui-iter2.png` — icons BL, `4m`/`10m`/`11m` BR, green ring, no search |

## 6. hjkl + WASD + arrows — один handler — PASS
`ClipboardKeyboardMonitor.navigationDelta` `:131-147` — single map; called once `:123-125`.  
a/h left, d/l right, w/k up, s/j down + arrow keycodes.

## 7. ⌘ hold → ⌘N; ⌘1–9 paste visible index — PASS
| | |
|---|---|
| flagsChanged | monitor `:39-42, 58-63` → `isCommandHeld` |
| Badge | `ClipboardHistoryView:91` `commandIndex: isCommandHeld && index < 9 ? index+1 : nil` — **visible order** |
| Digit paste | monitor `:72-79` digit→`onPasteIndex(index)` 0-based |
| Paste path | `:236-241` `visibleItems[index]` → pasteItem + close |

Runtime ⌘-hold screenshot: **НЕПРОВЕРЯЕМО** (как у исполнителя); code path OK.

## 8. Language picker + L() / strings — PASS (с notes)
| | |
|---|---|
| Default EN | `AppLanguage.swift:25` `default: .english` |
| Picker | `SettingsView.swift:163-168` `Picker(L("Language"))` English/Русский |
| L() | `AppLanguage.swift:50-64` table **`Pocket`** (не Localizable — конфликт с xcstrings; допустимо, работает) |
| Clipboard L() | Pin/Copy/Paste/Delete/empty/File — Card/HistoryView |
| Immediate refresh | `.id(language.revision)` HistoryView `:42`; Settings onChange setLanguage |

### i18n completeness (extra)
| Metric | Value |
|---|---|
| EN keys | **190** |
| RU keys | **190** |
| missing | **0** |
| empty RU | **0** |
| RU == EN | **3** only: `English`, `GitHub`, `Русский` (brands — OK) |
| bare Picker/Toggle/Button strings | **0** (кроме `Defaults.Toggle("", …)` empty) |
| Residual English `Text("…\(…)")` | **~8** dynamic templates still English, e.g. `SettingsView.swift:243,272,355,674,1010,1345` — **minor gap** vs strict «нет литералов вне L()» |

---

## Smoke — PASS
`open /tmp/pocket-verify3-dd/.../boringNotch.app` — process alive ≥5s (PID observed), kill clean.

## Screenshot acceptance (п.9) — PASS partial
- `docs/clipboard-ui-iter2.png` exists, matches layout claims
- ⌘-hold second shot: not produced — marked by executor

---

## Сводка

| # | Критерий | Вердикт |
|---|---|---|
| 1 | Build | **PASS** |
| 2 | No search UI / no isSearchFocused | **PASS** |
| 3 | Hotkey toggle, no 3s close | **PASS** |
| 4 | Space popup + nav lock | **PASS** |
| 5 | Footer icon/time format + 30s tick | **PASS** |
| 6 | hjkl/WASD/arrows one handler | **PASS** |
| 7 | ⌘N badges + ⌘1–9 visible index | **PASS** (code) |
| 8 | Language EN default + Pocket.strings | **PASS** |
| i18n full | keys 190/190, brands only same | **PASS** with **minor** bare interpolations |
| Smoke | ≥5s | **PASS** |

### Замечания (не блокер)
1. `searchQuery`/`ClipboardSearch`/fuse still wired for empty query — remove later if desired.
2. ~8 Settings `Text("English template \(value)")` not via L().
3. Strings table name `Pocket` not `Localizable` (documented).
4. Runtime ⌘-hold UI not re-captured.

**Решение: ПРИНЯТЬ С ЗАМЕЧАНИЯМИ.**
