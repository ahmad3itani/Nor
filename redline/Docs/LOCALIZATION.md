# REDLINE Localization (M9)

How player-facing text is written, catalogued and translated. English is the source language; no real translation ships in M9. What M9 delivers is the plumbing: a catalog, a runtime lookup, a generated pseudo-locale, lints and tests, so that adding a language later is a `.po` file and one data row, with no code changes. Everything is local files: no networking, no platform service (§29, §37.7). Every command below runs from `redline/`.

## The model in one paragraph

Catalogs are gettext PO files (D-162). The lookup key is the **English source text** (`msgid`) plus an optional context (`msgctxt`) for short ambiguous words ("On" as a toggle value vs "On" as a preposition). Every string also gets a stable **location key** such as `data/sequences/uc_opening.tres::steps[3].text`, written into the catalog as a `#.` comment: tools use it for traceability and to carry a translation across an English edit (as a fuzzy entry). Data files keep their English text, so the knowledge lint, the length validators, roomgen `--check` and the tests keep reading English. Text is translated **at the edge**: where it becomes pixels or where a display-only string is composed. Resources, EventBus identity payloads (`room_entered`, `boss_started`, `dialogue_requested`) and Playtest events carry the English source, so logic never depends on the language.

## Files

| Path | What |
|---|---|
| `l10n/Loc.gd` | Runtime: `t`, `f`, `tn`, `upper`, `set_locale`, `available_locales`, `info`, `parse_locale_arg`. |
| `l10n/LocaleInfo.gd`, `l10n/LocaleTable.gd` | One language row; the table (`data/l10n/locales.tres`). |
| `l10n/L10nConfig.gd` | Extractor and lint settings (`data/l10n/l10n_config.tres`). |
| `l10n/LocFields.gd` | The `LOC_FIELDS` protocol: reads declarations, walks resources and scene states. |
| `l10n/PoFile.gd`, `l10n/CatalogEntry.gd`, `l10n/Pseudo.gd` | PO reader/writer, catalog entries, the pseudo-locale. |
| `devtools/l10n/ExtractStrings.gd` + `.tscn` | The extractor CLI. `GdSource.gd` is its GDScript tokenizer. |
| `devtools/content/rules/StringRules.gd` | Lints L-1..L-9 (a ContentValidator rule module). |
| `locale/redline.pot` | The template. **Generated, checked in.** |
| `locale/en_XA.po` | The pseudo-locale. **Generated, checked in, dev builds only.** |
| `locale/<code>.po` | Future translator files (hand-edited msgstr, updated by `--merge`). |

## Commands

```bash
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write           # regenerate redline.pot + en_XA.po
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --check           # exit 1 if either is stale or a lint errors
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --merge           # update every locale/<code>.po from the catalog
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --merge --new=fr  # start locale/fr.po, then merge
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --stats           # per-locale coverage (Markdown)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=l10n  # the localization tests
godot res://Main.tscn -- --locale=en_XA                                        # play in the pseudo-locale (session only)
```

`--locale=<code>` is a session override: Settings never saves it. The test runner pins English before the first suite and after every test, so a developer's saved language never reaches a test. The DevConsole "Endgame & build… → Locale…" page cycles the language, marks untranslated text as `‹…›` and prints a catalog report (session only, never saved).

**Status in M9 (warn mode).** Until the late M9 migration (T13) moves the pre-M9 strings to `Loc`, `StringRules.ENFORCE` is false: the catalog check, field coverage, hard-coded literals, source limits and `%` templates are *warnings* (the migration worklist), and `test_catalog_up_to_date` is skipped. PO integrity (placeholder parity, duplicates, headers) and the pseudo-locale glyph check are errors from the start. Only the first l10n task and the migration regenerate the checked-in catalogs; no other branch runs `--write`. After the migration, run `--write` whenever you add or change player text, and `--check` before committing.

## For authors: writing player text

### In code
- Wrap every player-facing literal: `Loc.t("Resume")`. With values, use **named placeholders**: `Loc.f("Continue ({cycle})", {"cycle": label})`. Plurals: `Loc.tn("Recovered {n} Scrap", "Recovered {n} Scrap", n)` (`{n}` is filled for you). Casing: `Loc.upper(name)` (upper-cases *after* translation).
- A short word that means different things in different places gets a context: `Loc.t("On", "toggle")`.
- Constant arrays of display words: end the line with `# l10n` (or `# l10n(ctx)`) so the extractor catalogues every literal on it, and wrap each value in `Loc.t` where it is shown.
- Text that must never be translated (the brand wordmark, dev labels) is marked `# l10n: ignore(<reason>)` on the line or on the comment line above it.
- `Loc.t(data.title)` with a non-literal argument is fine: that text comes from data, which is extracted separately.
- Dev tooling (DevConsole, dev pages, DebugOverlay, CaptureTour, labs) and the playtest facilitator UI stay English (D-163); `L10nConfig.code_exempt` lists them.

### In data (Resources and Node scripts)
Every script with player-visible text declares, next to its exports:

```gdscript
## Localization (D5): player-visible text fields -> max source chars (0 = none).
## Source text stays English here; Loc.t() translates at display.
const LOC_FIELDS := {"title": 40, "description": 90}
## Text-like fields that are not shown to the player (ids, dev labels).
const LOC_EXEMPT := ["label"]
## Optional msgctxt per field.
const LOC_CONTEXT := {"verb": "verb"}
```

Supported field types: `String`, `PackedStringArray` / `Array[String]` (each element), and `Dictionary` (each value). The extractor walks sub-resources generically (sequence steps, dialogue choices and replies, quest stages…), reads room and UI scenes from their `SceneState` without instancing them, and also collects a Node script's own default text. Decor `Label`/`Button`/`RichTextLabel` text in scenes is extracted too.

Godot 4.3 does not allow a subclass to redeclare a constant its base declares, so each of these names appears once per script chain. A subclass that adds fields to a base with `LOC_FIELDS` declares `const LOC_FIELDS_EXTRA := {...}`; all of them merge up the chain.

The field coverage lint (L-2) flags any exported text-like property whose name matches `L10nConfig.text_field_pattern` (`title`, `description`, `*_name`, `*_hint`, …) that neither list mentions, so a new content type must say what the player sees.

### Composition rules
1. Never concatenate translated fragments into a sentence. Translate one template with named placeholders (`Loc.f`).
2. One placeholder may be `%d`/`%s`; two or more must be named `{…}` (L-9), because a translator must be able to reorder them.
3. Plurals go through `Loc.tn` (English has 2 forms; each locale declares its `Plural-Forms`).
4. Casing goes through `Loc.upper`, after translation. Never pre-uppercase a translated string in code; data may be authored in caps ("CORE ONLINE").
5. Glyph and key names come from InputGlyphs, never inline letters.
6. Numbers and time are plain digits and `mm:ss`. No locale digit or separator formatting in M9.
7. Do not compare display strings in logic (L-8); compare ids. Payloads stay English for exactly this reason.
8. Text painted into world art (signage, the scanner's "TRIPPED") is art and stays English until art localization. Decor Labels in rooms are real text and are extracted.

### The lints (`StringRules`, run by ValidateContent and `--check`)

| id | Rule | Level |
|---|---|---|
| L-1 | `redline.pot` and `en_XA.po` match a fresh extraction | enforced |
| L-2 | every text-like exported field is in `LOC_FIELDS` or `LOC_EXEMPT` | enforced |
| L-3 | no string literal with a letter reaches a screen sink (`add_label(`, `add_button(`, `draw_string(`, `.text = `, `hint_requested.emit(`, … in `L10nConfig.literal_sinks`) outside `Loc` | enforced |
| L-4 | every translation keeps the source's placeholders (order may change) | error |
| L-5 | no duplicate `(ctx, msgid)`; the `Language:` header matches the file name; the file parses | error |
| L-6 | source text within its `LOC_FIELDS` max | enforced |
| L-7 | per locale: glyphs the font chain lacks (error for the pseudo-locale), translations over max × 1.4 | warn |
| L-8 | `.title/.display_name/… == "<literal>"` in logic | warn |
| L-9 | two or more `%` specs (enforced); `Loc.f` args naming every `{placeholder}` (warn) | enforced / warn |

"Enforced" means an error once `StringRules.ENFORCE` is true (after the migration) and a warning before.

## The pseudo-locale `en_XA`

Generated by the extractor from every catalog entry (D-163): vowels and common consonants are swapped for accented forms that the default font really has, each line grows by about 35–50 % with `~` padding, and the whole string is wrapped in `[ ]`. Placeholders (`{name}`, `%d`), BBCode tags and line breaks are copied verbatim. What it reveals in a capture:
- plain ASCII text: it did not go through `Loc` (L-3 should have caught it);
- text in `‹ ›` (with "Mark untranslated" on): it went through `Loc` but is not in the catalog (a string built at runtime);
- a missing `]` or `[`: the text was clipped; overlap: it does not fit.

Godot's built-in pseudolocalization is not used: it mangles `{action}` placeholders. `en_XA` is offered only in dev builds (`LocaleInfo.dev_only`); release and demo exports leave `locale/en_XA.po` out.

## Runtime notes
- `Settings.locale` is a device setting in `settings.cfg` (`[ui] locale`, `""` = follow the OS when a catalog exists, else English). It is not part of the save and is excluded from Reset. The Language row lists `Loc.available_locales()` by endonym.
- Only the **active** locale's catalog is registered with the TranslationServer. Godot matches `en` to `en_XA` by language, so registering the pseudo catalog while English is active would leak pseudo text into every Label that calls `tr()` by itself.
- `EventBus.locale_changed(code)` fires once per real change; open menus, the HUD and the dialogue box redraw from their stored source text.
- Line timing reads the displayed (translated) text times `LocaleInfo.reading_scale`; the pacing budgets stay on the English source (D-164).

## For translators
1. Create the file: `ExtractStrings -- --merge --new=<code>` writes `locale/<code>.po` with the right header and every entry.
2. Translate `msgstr` only. Keep every `{placeholder}` and `%` spec (you may reorder them). Keep line breaks where the English has them. The `#.` lines tell you where the text appears, who says it and the length limit ("max 40 chars"); stay within about 1.4× of it.
3. Entries marked `#, fuzzy` carry an older translation whose English changed: check it, then remove the `fuzzy` flag. The game ignores fuzzy entries (it shows English until you confirm).
4. `#~` entries at the end are translations whose English was removed; they are kept for reference and ignored by the game.
5. After the English changes, a developer runs `--merge` and sends the file back to you.

## Adding a language
1. Add a `LocaleInfo` row to `data/l10n/locales.tres`: `code` (TranslationServer code, e.g. `fr`, `zh_CN`), `language` (OS match key), `endonym` ("Français"), `plural_forms`, `min_font_size`, `reading_scale` (CJK ≈ 1.8).
2. Create and translate `locale/<code>.po` (above). `LocaleTable.validate()` fails while an enabled row has no catalog.
3. Fonts: the default font covers Latin, Greek and Cyrillic, and has no CJK or Arabic. No font is bundled in M9 (D-163). For another script add an OFL font under `assets/fonts/` and list it in `font_paths` (a new dependency, §37.9); `system_fonts` help desktop builds only and never count for coverage. L-7 lists every glyph the chain lacks.
4. CJK and Thai need ICU line-break data: set `internationalization/locale/include_text_server_data = true` in the export presets and check the size cost.
5. Right-to-left scripts are documented only in M9: menus mirror through `layout_direction`, but the hand-drawn HUD, map tooltips, subtitle speaker labels and the typewriter reveal (by code point, not grapheme) need a pass first.
6. Run `--stats`, the localization tests and a CaptureTour with `--locale=<code>`; fix what overflows (shorten or wrap; an ellipsis is the last resort).
