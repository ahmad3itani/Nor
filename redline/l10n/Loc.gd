class_name Loc
extends RefCounted
## Runtime string lookup (M9 D5, D-162): gettext PO catalogs, msgid = the
## English source text, optional msgctxt. Every player-facing literal goes
## through t()/f()/tn()/upper() at the edge (where text becomes pixels or a
## display-only string is composed); resources, EventBus identity payloads
## and logic keep the English source, so nothing ever compares display text.
##
## Catalog registration (R06.1): only the ACTIVE locale's Translation is on
## the TranslationServer. Godot matches "en" to "en_XA" by language, so with
## the pseudo-locale registered even an English session would show pseudo
## text in every Label that calls tr() on its own. English registers nothing.

const SOURCE_LOCALE := "en"
const CATALOG_DIR := "res://locale"
const DEV_ACTIONS_PATH := "res://devtools/DevActions.gd"

## Dev: wrap text with no translation in the current (non-source) locale as
## ‹…›, so uncatalogued strings stand out under the pseudo-locale.
static var flag_missing: bool = false

static var _locale: String = SOURCE_LOCALE
## Fast path: the source locale translates nothing.
static var _identity: bool = true
## code -> Translation, loaded but not registered (see the header).
static var _catalogs: Dictionary = {}
static var _loaded: bool = false
## The one Translation Loc registered with the TranslationServer (or null).
static var _active: Translation = null


## English source text -> the current locale; missing -> the source.
static func t(msg: String, ctx: String = "") -> String:
	if _identity or msg == "":
		return msg
	var r := String(TranslationServer.translate(msg, ctx))
	if flag_missing and r == msg:
		return "‹" + msg + "›"
	return r


## t() then String.format(args). Named placeholders ("{seen}/{total}") let a
## translator reorder them: Loc.f("Continue ({cycle})", {"cycle": "NG+"}).
static func f(msg: String, args: Dictionary, ctx: String = "") -> String:
	return t(msg, ctx).format(args)


## Plural form through the catalog's Plural-Forms; {n} is always available.
static func tn(singular: String, plural: String, n: int, args: Dictionary = {}, ctx: String = "") -> String:
	var base := singular if n == 1 else plural
	if not _identity:
		var r := String(TranslationServer.translate_plural(singular, plural, n, ctx))
		base = "‹" + r + "›" if flag_missing and (r == singular or r == plural) else r
	var all := args.duplicate()
	all["n"] = n
	return base.format(all)


## Upper-cases after translation (never pre-uppercase a translated string).
static func upper(msg: String, ctx: String = "") -> String:
	return t(msg, ctx).to_upper()


## Applies a locale and returns the code actually applied. "" = auto (the OS
## language when a catalog exists, else English); an unknown or unavailable
## code falls back to English. Emits EventBus.locale_changed only when the
## locale really changed. Session only: Settings persists the choice.
static func set_locale(code: String) -> String:
	if not _loaded:
		load_catalogs()
	var resolved := _resolve(code)
	var want: Translation = _catalogs.get(resolved) if resolved != SOURCE_LOCALE else null
	if resolved == _locale and want == _active and TranslationServer.get_locale() == resolved:
		return resolved
	if _active != null:
		TranslationServer.remove_translation(_active)
		_active = null
	if want != null:
		TranslationServer.add_translation(want)
		_active = want
	TranslationServer.set_locale(resolved)
	var changed := resolved != _locale
	_locale = resolved
	_identity = resolved == SOURCE_LOCALE
	# Font chain and size floors follow the locale (LocaleInfo rows).
	UiTheme.invalidate()
	if changed:
		EventBus.locale_changed.emit(resolved)
	return resolved


static func locale() -> String:
	return _locale


## Codes offered in Settings: enabled rows with a catalog (English always);
## dev-only rows (the pseudo-locale) only when DevActions.available().
static func available_locales() -> PackedStringArray:
	if not _loaded:
		load_catalogs()
	var dev := _dev_available()
	var out := PackedStringArray()
	for r in LocaleTable.shared().rows:
		if r == null or not r.enabled or (r.dev_only and not dev):
			continue
		if r.code == SOURCE_LOCALE or _catalogs.has(r.code):
			out.append(r.code)
	if not out.has(SOURCE_LOCALE):
		out.insert(0, SOURCE_LOCALE)
	return out


## The LocaleInfo of `code` (default: the current locale). Never null: an
## unknown code gets the source row, and a missing table a default row.
static func info(code: String = "") -> LocaleInfo:
	var table := LocaleTable.shared()
	var r := table.by_code(code if code != "" else _locale)
	if r == null:
		r = table.by_code(SOURCE_LOCALE)
	if r == null:
		r = LocaleInfo.new()
		r.code = SOURCE_LOCALE
		r.language = SOURCE_LOCALE
		r.endonym = "English"
	return r


## `--locale=xx` from user args ("" when absent). A session override that
## Settings never saves (like --subtitle-size).
static func parse_locale_arg(args: PackedStringArray) -> String:
	for a in args:
		if a.begins_with("--locale="):
			return a.trim_prefix("--locale=").strip_edges()
	return ""


## Loads every locale/*.po once (DataDir.list_files, so exported builds list
## them too), skipping rows that are disabled, unknown, or dev-only in a
## release build. Nothing is registered here (see the header).
static func load_catalogs() -> void:
	_catalogs.clear()
	var table := LocaleTable.shared()
	var dev := _dev_build()
	for path in DataDir.list_files(CATALOG_DIR, "po"):
		var code := path.get_file().get_basename()
		var row := table.by_code(code)
		if row == null or not row.enabled or (row.dev_only and not dev) or code == SOURCE_LOCALE:
			continue
		var tr := load(path) as Translation
		if tr != null:
			_catalogs[code] = tr
	_loaded = true


## Tests and tools: offers a catalog loaded from elsewhere under `code` until
## the next load_catalogs()/clear_cache(). Nothing is registered until
## set_locale(code).
static func register_catalog(code: String, translation: Translation) -> void:
	if not _loaded:
		load_catalogs()
	_catalogs[code] = translation


## Codes with a loaded catalog (English excluded), sorted.
static func loaded_catalogs() -> PackedStringArray:
	var out := PackedStringArray(_catalogs.keys())
	out.sort()
	return out


## Back to English with nothing registered; drops the loaded catalogs (exit,
## tests). R06.4: also removes the Translation Loc added.
static func clear_cache() -> void:
	if _active != null:
		TranslationServer.remove_translation(_active)
		_active = null
	TranslationServer.set_locale(SOURCE_LOCALE)
	_catalogs.clear()
	_loaded = false
	_locale = SOURCE_LOCALE
	_identity = true
	flag_missing = false
	LocaleTable.clear_cache()
	L10nConfig.clear_cache()


static func _resolve(code: String) -> String:
	var c := code.strip_edges()
	if c == "":
		c = _auto_code()
	if c == SOURCE_LOCALE or _catalogs.has(c):
		return c
	return SOURCE_LOCALE


## The first enabled row whose code or language matches the OS language and
## has a catalog; English otherwise. Dev-only rows never win automatically.
static func _auto_code() -> String:
	var os_lang := OS.get_locale_language()
	var os_full := OS.get_locale()
	for r in LocaleTable.shared().rows:
		if r == null or not r.enabled or r.dev_only:
			continue
		if (r.code == os_full or r.language == os_lang) and (r.code == SOURCE_LOCALE or _catalogs.has(r.code)):
			return r.code
	return SOURCE_LOCALE


## Release builds never load dev-only catalogs. Kept free of DevActions so
## loading catalogs from Settings (the second autoload) compiles no Game.
static func _dev_build() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")


## DevActions.available() by path at call time (menus, dev pages): naming the
## class here would compile DevActions (and Game) whenever Loc compiles.
static func _dev_available() -> bool:
	if not ResourceLoader.exists(DEV_ACTIONS_PATH):
		return false
	var da := load(DEV_ACTIONS_PATH) as GDScript
	return da != null and bool(da.call("available"))
