class_name LocaleInfo
extends Resource
## One display language (M9 D5, D-163): what the TranslationServer calls it,
## how the Settings row names it, and what its text needs from the font chain
## and the line timing. A new language is a `locale/<code>.po` file plus one
## of these rows in data/l10n/locales.tres; no code changes.

## The endonym is shown in its own language and never translated.
const LOC_EXEMPT := ["endonym"]

## TranslationServer code: "en", "en_XA", "fr", "zh_CN".
@export var code: String = ""
## OS match key for the automatic choice (OS.get_locale_language()): "en", "fr".
@export var language: String = ""
## Shown in the Language row, in the language itself ("Français").
@export var endonym: String = ""
@export var enabled: bool = true
## Offered only in dev builds (DevActions.available()): the pseudo-locale.
@export var dev_only: bool = false
## Right-to-left script. Documented only in M9 (D-163): menus mirror through
## layout_direction, the hand-drawn HUD does not yet.
@export var rtl: bool = false
## Floor for every UI and subtitle font size in this language (wide glyphs).
@export_range(6, 16) var min_font_size: int = 7
## D-164: multiplies the auto line time (CJK readers need longer per glyph).
@export_range(0.5, 3.0, 0.05) var reading_scale: float = 1.0
## res:// fallback fonts, guarded by ResourceLoader.exists (none bundled, D-163).
@export var font_paths: PackedStringArray = []
## SystemFont names (desktop only; never counted for glyph coverage).
@export var system_fonts: PackedStringArray = []
## Written into a new translator file by ExtractStrings --merge --new=<code>.
@export var plural_forms: String = "nplurals=2; plural=(n != 1);"
## Extra glyphs the font chain must have (the endonym is always checked).
@export var coverage_sample: String = ""
