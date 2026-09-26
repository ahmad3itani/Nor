extends Node
## Player-facing settings, persisted to user://settings.cfg (global, not per
## profile: D-156).
##
## M0 started with the values the Movement Lab consumed (shake, hitstop,
## flash) plus audio levels; M8 added the subtitle and scene values (bible
## §24, D-110). M9 (T03, D4 §3.1) makes load/save catalog-driven: every stored
## key is one SettingDef row in data/settings/pages/*.tres, so adding an
## option is one data row plus one clamped property here. Every M8 key keeps
## its name, section, cfg key and default, so an old settings.cfg still loads.
## Three keys stay hand-written: [input] bindings (a Dictionary), [ui] locale
## (a string) and [meta] version.
## The settings file is not a save file (D-087/D-090 do not apply), but it
## carries [meta] version so a later change of meaning has a migration hook.

const SETTINGS_PATH := "user://settings.cfg"
## settings.cfg format: 1 = M8 (no [meta]), 2 = M9 catalog keys.
const VERSION := 2

## 0 disables camera shake entirely; 1 is the authored intensity.
var screen_shake_scale: float = 1.0:
	set(v): screen_shake_scale = clampf(v, 0.0, 1.5)
## Reserved for M2 hitstop. 0 disables freeze frames.
var hitstop_scale: float = 1.0:
	set(v): hitstop_scale = clampf(v, 0.0, 1.0)
var flash_reduction: bool = false
var vibration_strength: float = 1.0:
	set(v): vibration_strength = clampf(v, 0.0, 1.0)
var master_volume: float = 1.0:
	set(v): master_volume = clampf(v, 0.0, 1.0)
var sfx_volume: float = 0.8:
	set(v): sfx_volume = clampf(v, 0.0, 1.0)
var music_volume: float = 0.6:
	set(v): music_volume = clampf(v, 0.0, 1.0)
## Off by default for playtesters; F1 toggles it (labs and slice).
var show_debug_overlay: bool = false
## Accessibility (bible §24): dropping unbanked Scrap on death can be disabled.
var currency_loss: bool = true
## M4: record this run for the playtest (local file only, never uploaded).
var playtest_recording: bool = true
## M4: force a playtest variant id ("" = rotate automatically per session).
var playtest_variant: String = ""
## Redline Core difficulty (bible §6): 0 Normal, 1 Story/Assist, 2 Redline Challenge.
var reactor_mode: int = 0:
	set(v): reactor_mode = clampi(v, 0, 2)
## --- Subtitles & scenes (M8) ---
## 0 Small / 1 Medium / 2 Large (SubtitleStyle.SIZES). Read through
## effective_subtitle_size(), which honours the --subtitle-size= capture arg.
var subtitle_size: int = 0:
	set(v): subtitle_size = clampi(v, 0, 2)
## 0 Outline (no box) / 1 Box / 2 Solid (SubtitleStyle.box_alpha/subtitle_alpha).
var subtitle_background: int = 1:
	set(v): subtitle_background = clampi(v, 0, 2)
var speaker_labels: bool = true
## Reading speed of timed scene lines: 0 Normal x1.0 / 1 Slow x1.5 / 2 Slower x2.0
## (SubtitleStyle.time_scale()).
var subtitle_speed: int = 0:
	set(v): subtitle_speed = clampi(v, 0, 2)
## true = hold to skip scenes; false = "Press twice" (SkipGate).
var cinematic_skip_hold: bool = true
## Memory vignettes play when resting at an Anchor (off = journal only).
var memories_at_anchors: bool = true

## --- M9 keys (T03: catalog rows) ---
# The setters keep the clamps the rows' choice counts rely on (SE-2).
# Consumers: T11 (assists), T12 (visual, haptics), T02/T07 (toasts),
# T04/T08 (challenges), T06/T13 (locale).
## [audio] Menu and UI sounds (the "UI" bus).
var ui_volume: float = 0.8:
	set(v): ui_volume = clampf(v, 0.0, 1.0)
## [accessibility] High-contrast UI and world cues.
var high_contrast: bool = false
## [accessibility] 0 Off / 1 Red-green / 2 Blue-yellow (shape cues + palette).
var colorblind_mode: int = 0:
	set(v): colorblind_mode = clampi(v, 0, 2)
## [accessibility] 0 Off / 1 Some / 2 Strong dimming of the backdrop.
var background_dim: int = 0:
	set(v): background_dim = clampi(v, 0, 2)
## [accessibility] 0 100 % / 1 125 % / 2 150 % UI scale.
var ui_scale: int = 0:
	set(v): ui_scale = clampi(v, 0, 2)
## [accessibility] 0 Off / 1 On: scene lines advance on their own (D-110).
## Not an assist: never tagged.
var text_auto_advance: int = 0:
	set(v): text_auto_advance = clampi(v, 0, 1)
## [assist] 0 Off / 1 Light / 2 Strong aim cone.
var aim_assist: int = 0:
	set(v): aim_assist = clampi(v, 0, 2)
## [assist] 0 Off / 1 Bosses reduced / 2 All reduced / 3 All greatly reduced.
var damage_assist: int = 0:
	set(v): damage_assist = clampi(v, 0, 3)
## [assist] Burnout (Core overheat) costs health.
var burnout_hurts: bool = true
## [assist] Respawn at the last room entry instead of the last Anchor.
var generous_checkpoints: bool = false
## [assist] 0 Hold for height / 1 Always full height (never tagged, D-149).
var jump_hold_mode: int = 0:
	set(v): jump_hold_mode = clampi(v, 0, 1)
## [assist] 0 Minimal / 1 Standard / 2 Guided map hints.
var map_hints: int = 1:
	set(v): map_hints = clampi(v, 0, 2)
## [assist] Offer assists after repeated deaths (§23: offered, never applied).
var assist_suggestions: bool = true
## [input] 0 Auto / 1 Xbox / 2 PlayStation / 3 Nintendo prompts.
var pad_glyphs: int = 0:
	set(v): pad_glyphs = clampi(v, 0, 3)
## [input] How long a rebind capture listens: 0 = 5 s, 1 = 10 s, 2 = no limit
## (AccessibilityConfig.rebind_timeout_sec, R03.7).
var rebind_wait: int = 1:
	set(v): rebind_wait = clampi(v, 0, 2)
## [input] action -> {"key": [...], "pad": [...]}: saved events, only where they
## differ from project.godot (InputBindings). Hand-written, not a catalog row.
var bindings: Dictionary = {}
## [ui] Achievement toasts on screen.
var achievement_toasts: bool = true
## [ui] Display language code ("" = automatic). Hand-written (a string, not a
## choice index) and excluded from every Reset (D5 §12.1).
var locale: String = ""
## [challenges] 0 Off / 1 IGT / 2 IGT + splits.
var speedrun_timer: int = 0:
	set(v): speedrun_timer = clampi(v, 0, 2)
## [challenges] Ghost shown in runs: 0 Off / 1 Personal best / 2 Rig ghost / 3 Both.
var challenge_ghost: int = 1:
	set(v): challenge_ghost = clampi(v, 0, 3)
## [challenges] Fast reset needs a hold (no accidental restarts).
var fast_reset_hold: bool = true
## Session only (never saved): no settings.cfg existed at boot, so the title
## offers the comfort & accessibility row once (D-168).
var first_run: bool = false

## Tuning behind the indices above (AccessibilityConfig, bible §31). load()ed
## in _ready, never a preload const (CLAUDE.md pitfall).
var access_config: AccessibilityConfig
## Every page and row (data/settings/catalog.tres).
var catalog: SettingsCatalog

var _path: String = SETTINGS_PATH
## Session-only subtitle size from `--subtitle-size=N` (captures, -1 = none).
## Never saved, so SettingsMenu.close_menu cannot persist a CLI value.
var _subtitle_size_override: int = -1
## Session-only locale from `--locale=` (T06); never saved.
var _locale_override: String = ""
## The startup steps _ready ran, in order (tests check the locale calls).
var _ready_trace: PackedStringArray = []

## Properties snapshot()/apply_defaults()/restore() skip: session-only state
## that is never a stored setting (R01.22).
const _SESSION_ONLY := ["_path", "_subtitle_size_override", "_locale_override", "first_run"]
## Script variables that are runtime helpers, not settings.
const _RUNTIME := ["access_config", "catalog", "_ready_trace"]
## Stored settings that are not catalog rows (hand-written in load/save).
const HAND_WRITTEN := ["bindings", "locale"]
## key -> default, read once from a fresh instance of this script, so the
## declarations above stay the only place a default is written.
static var _defaults: Dictionary = {}


func _ready() -> void:
	# Debug demos move saves, platform files and settings before any store
	# loads (T05 fills it; Settings is the second autoload).
	BuildInfo.apply_demo_dirs()
	# A demo build's recording default applies before the file (D-165), so a
	# stored choice still wins.
	if BuildInfo.is_demo():
		playtest_recording = BuildInfo.recording_default()
	access_config = load(AccessibilityConfig.PATH) as AccessibilityConfig
	catalog = load(SettingsCatalog.PATH) as SettingsCatalog
	load_settings()
	var arg := parse_subtitle_size_arg(OS.get_cmdline_user_args())
	if arg >= 0:
		_subtitle_size_override = arg
	_locale_override = Loc.parse_locale_arg(OS.get_cmdline_user_args())
	# Bindings go in before any gameplay autoload reads input (Settings is
	# the second autoload); defaults are snapshotted first so Reset is always
	# the shipped layout.
	InputBindings.snapshot_defaults()
	# apply() drops what no longer decodes (an old or hand-edited file); the
	# cleaned overrides are what the next save writes.
	bindings = InputBindings.apply(bindings)
	_ready_trace.append("bindings")
	Loc.load_catalogs()
	_ready_trace.append("load_catalogs")
	Loc.set_locale(effective_locale())
	_ready_trace.append("set_locale")
	EventBus.settings_changed.connect(UiTheme.invalidate)


## The config (loaded lazily when a caller runs before _ready, e.g. tests on
## a fresh instance).
func config() -> AccessibilityConfig:
	if access_config == null:
		access_config = load(AccessibilityConfig.PATH) as AccessibilityConfig
	return access_config


func settings_catalog() -> SettingsCatalog:
	if catalog == null:
		catalog = load(SettingsCatalog.PATH) as SettingsCatalog
	return catalog


## `--subtitle-size=N` from user args, clamped 0..2; -1 when absent.
static func parse_subtitle_size_arg(args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--subtitle-size="):
			return clampi(a.trim_prefix("--subtitle-size=").to_int(), 0, 2)
	return -1


## The size subtitles render at: the session override when set, else the stored one.
func effective_subtitle_size() -> int:
	return _subtitle_size_override if _subtitle_size_override >= 0 else subtitle_size


## The language in use: the --locale= override when given, else the stored one.
func effective_locale() -> String:
	return _locale_override if _locale_override != "" else locale


## The Settings language row: store, apply and save at once (a CLI override
## is never written; this replaces it for the session).
func set_locale_setting(code: String) -> void:
	locale = code
	_locale_override = ""
	Loc.set_locale(code)
	save_settings()


func load_settings(path: String = SETTINGS_PATH) -> void:
	_path = path
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		# A crash between the tmp write and the rename, or a hand edit that no
		# longer parses: the previous file is the .bak (the AtomicJson rule).
		var bak := ConfigFile.new()
		if FileAccess.file_exists(path + ".bak") and bak.load(path + ".bak") == OK:
			push_warning("Settings: %s unreadable, recovered from backup" % path)
			cfg = bak
		else:
			if path == SETTINGS_PATH:
				first_run = true
			return
	var from := int(cfg.get_value("meta", "version", 1))
	if from < VERSION:
		_migrate(cfg, from)
	for def in settings_catalog().stored_defs():
		var current: Variant = get(def.key)
		set(def.key, _coerce(cfg.get_value(def.section, def.cfg_name(), current), current))
	var saved_bindings: Variant = cfg.get_value("input", "bindings", bindings)
	bindings = (saved_bindings as Dictionary).duplicate(true) if saved_bindings is Dictionary else {}
	locale = str(cfg.get_value("ui", "locale", locale))


## v1 (M8, no [meta]) -> v2: every M8 key kept its name, section and meaning,
## so there is nothing to convert; the new keys take their defaults. Later
## versions convert here, step by step.
func _migrate(cfg: ConfigFile, from: int) -> void:
	if from < 2:
		cfg.set_value("meta", "version", 2)


## Written atomically: <path>.tmp, the previous file moves to <path>.bak, then
## the tmp is renamed into place (the AtomicJson contract, R03.3).
func save_settings() -> Error:
	var cfg := ConfigFile.new()
	for def in settings_catalog().stored_defs():
		cfg.set_value(def.section, def.cfg_name(), get(def.key))
	cfg.set_value("input", "bindings", bindings)
	cfg.set_value("ui", "locale", locale)
	cfg.set_value("meta", "version", VERSION)
	var tmp := _path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return err
	if FileAccess.file_exists(_path):
		if FileAccess.file_exists(_path + ".bak"):
			DirAccess.remove_absolute(_path + ".bak")
		err = DirAccess.rename_absolute(_path, _path + ".bak")
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, _path)


## Removes a settings file and its .bak/.tmp siblings (test and tour temp
## paths; never called on SETTINGS_PATH by the game).
static func remove_settings_files(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Every stored setting's current value (catalog keys plus bindings and
## locale, never the session-only fields). CaptureTour and tests put it back
## with restore().
func snapshot() -> Dictionary:
	var out := {}
	for k: String in _default_values():
		var v: Variant = get(k)
		out[k] = v.duplicate(true) if v is Dictionary else v
	return out


## key -> default of every stored setting.
func defaults() -> Dictionary:
	return _default_values().duplicate(true)


## Every stored setting back to its declared default (session fields untouched).
func apply_defaults() -> void:
	restore(_default_values())


func restore(d: Dictionary) -> void:
	for k: String in d:
		if _SESSION_ONLY.has(k) or _RUNTIME.has(k):
			continue
		var v: Variant = d[k]
		set(k, v.duplicate(true) if v is Dictionary else v)
	if d.has("bindings"):
		InputBindings.apply(bindings)
	UiTheme.invalidate()


## Puts `keys` back to their defaults (a page's "Reset", "Reset all") and
## tells open overlays to restyle.
func reset_keys(keys: Array[StringName]) -> void:
	var defs := _default_values()
	var sub := {}
	for k in keys:
		if defs.has(String(k)):
			sub[String(k)] = defs[String(k)]
	restore(sub)
	if keys.has(&"subtitle_size"):
		_subtitle_size_override = -1
	EventBus.settings_changed.emit()


## What "Reset all settings" touches: every row of every page that has its
## own reset. Controls (bindings and the Controls rows), the playtest rows
## and the language stay (D4 §3.2, D5 §12.1).
func reset_all_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in settings_catalog().pages:
		if p == null or not p.reset_row:
			continue
		for d in p.rows:
			if d != null and d.is_stored():
				out.append(d.key)
	return out


## The assists in use, as neutral tags for records and playtests (D-149,
## D-157). Only settings that change challenge difficulty count; comfort
## options (shake, hitstop, flashes, contrast, colour, scale, subtitles, jump
## height, map hints, generous checkpoints) never do.
func active_assists() -> PackedStringArray:
	var out := PackedStringArray()
	if reactor_mode == 1:
		out.append("reactor_assist")
	if damage_assist > 0:
		out.append("damage_assist")
	if aim_assist > 0:
		out.append("aim_assist")
	if not burnout_hurts:
		out.append("no_burnout")
	return out


## Stored setting names: every script variable minus session and runtime
## fields (SE-1 compares this against the catalog).
func setting_properties() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _default_values():
		out.append(k)
	return out


func _default_values() -> Dictionary:
	if _defaults.is_empty():
		var fresh: Node = (get_script() as GDScript).new()
		for p in fresh.get_property_list():
			var k: String = p["name"]
			if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or _SESSION_ONLY.has(k) or _RUNTIME.has(k) or k == "_defaults":
				continue
			var v: Variant = fresh.get(k)
			_defaults[k] = v.duplicate(true) if v is Dictionary else v
		fresh.free()
	return _defaults


## A stored value of the wrong type (a hand-edited file) falls back to the
## current value instead of breaking a typed property.
static func _coerce(v: Variant, current: Variant) -> Variant:
	match typeof(current):
		TYPE_BOOL:
			return bool(v) if v is bool or v is int else current
		TYPE_INT:
			return int(v) if v is int or v is float else current
		TYPE_FLOAT:
			return float(v) if v is int or v is float else current
		TYPE_STRING:
			return str(v) if v is String or v is StringName else current
	return v
