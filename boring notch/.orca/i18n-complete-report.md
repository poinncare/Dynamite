# Доперевод настроек EN/RU

## До
- EN keys: 162
- Untranslated (ru == en): **68**
- Bare UI literals in SettingsView (Picker/Toggle/Button without L): **30**

## Сделано
1. Список «отсутствующих» в RU: **0 missing keys** (все 162 уже были в файле), **68** с value == English key.
2. Допереведены все 68 + добавлены ~28 ключей для голых Picker/Toggle/Button → **EN=190, RU=190**.
3. same_as_en после правки: **0** (кроме намеренных brand-строк, оставленных как English/GitHub/Русский — они же отображаемые имена).
4. SettingsView: обёрнуты bare `Picker("…"`, `Toggle("…"`, `Button("…"` → `L("…")`.
   - Осталось: `Defaults.Toggle("", key: .hudReplacement)` — пустой label, не локализуется.
   - `Text("…\(interp)…")` с интерполяцией — динамические числа, не статические ключи.

## Статистика L()
- `L("` : 207
- `Text(L(` : 146
- `Picker(L(` : 15
- `Toggle(L(` : 8
- `Button(L(` : 9

## Непереведённых не осталось
- missing: 0
- same_as_en (требующие RU): 0

## Build
```
** BUILD SUCCEEDED **
```

## Files
- `boringNotch/en.lproj/Pocket.strings`
- `boringNotch/ru.lproj/Pocket.strings`
- `boringNotch/components/Settings/SettingsView.swift`
