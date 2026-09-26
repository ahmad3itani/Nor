class_name Loc
extends RefCounted
## Runtime string lookup (M9 D5, D-162): gettext PO catalogs, msgid = the
## English source text, optional msgctxt. Every player-facing literal goes
## through t()/f()/tn()/upper() at the edge; logic never compares display text.
##
## stub: filled by T06 (TranslationServer catalogs, en_XA pseudo-locale,
## --locale arg). The stub returns the English source unchanged.

const SOURCE_LOCALE := "en"


static func t(msg: String, _ctx: String = "") -> String:
	return msg


## Named placeholders: Loc.f("Continue ({cycle})", {"cycle": "NG+"}).
static func f(msg: String, args: Dictionary, _ctx: String = "") -> String:
	return msg.format(args)


## Plural form; {n} is always available to the text.
static func tn(singular: String, plural: String, n: int, args: Dictionary = {}, _ctx: String = "") -> String:
	return (singular if n == 1 else plural).format(args.merged({"n": n}))


static func upper(msg: String, _ctx: String = "") -> String:
	return msg.to_upper()


## Returns the locale actually applied.
static func set_locale(_code: String) -> String:
	return SOURCE_LOCALE


static func locale() -> String:
	return SOURCE_LOCALE


static func available_locales() -> PackedStringArray:
	return PackedStringArray([SOURCE_LOCALE])


## `--locale=xx` from user args ("" when absent).
static func parse_locale_arg(_args: PackedStringArray) -> String:
	return ""


## The LocaleInfo resource of the current locale (null in the stub).
static func info() -> Resource:
	return null


static func load_catalogs() -> void:
	pass


static func clear_cache() -> void:
	pass
