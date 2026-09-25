extends Node
## Player-facing settings, persisted to user://settings.cfg.
##
## M0 skeleton: only values the Movement Lab already consumes (shake, hitstop,
## flash) plus audio levels. Full accessibility menu arrives with M9, but the
## values live here from day one so systems read them instead of hardcoding.
## M8 adds the subtitle and scene values (bible §24: subtitle size, background,
## speaker labels, cinematic skip) plus reading speed and memories-at-Anchors;
## their "Subtitles & scenes" menu rows land in M8 (D-110, FLAG), the rest of
## the settings menu stays M9 work.

const SETTINGS_PATH := "user://settings.cfg"

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

var _path: String = SETTINGS_PATH
## Session-only subtitle size from `--subtitle-size=N` (captures, -1 = none).
## Never saved, so SettingsMenu.close_menu cannot persist a CLI value.
var _subtitle_size_override: int = -1


func _ready() -> void:
	load_settings()
	var arg := parse_subtitle_size_arg(OS.get_cmdline_user_args())
	if arg >= 0:
		_subtitle_size_override = arg


## `--subtitle-size=N` from user args, clamped 0..2; -1 when absent.
static func parse_subtitle_size_arg(args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--subtitle-size="):
			return clampi(a.trim_prefix("--subtitle-size=").to_int(), 0, 2)
	return -1


## The size subtitles render at: the session override when set, else the stored one.
func effective_subtitle_size() -> int:
	return _subtitle_size_override if _subtitle_size_override >= 0 else subtitle_size


func load_settings(path: String = SETTINGS_PATH) -> void:
	_path = path
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	screen_shake_scale = cfg.get_value("accessibility", "screen_shake_scale", screen_shake_scale)
	hitstop_scale = cfg.get_value("accessibility", "hitstop_scale", hitstop_scale)
	flash_reduction = cfg.get_value("accessibility", "flash_reduction", flash_reduction)
	vibration_strength = cfg.get_value("accessibility", "vibration_strength", vibration_strength)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	show_debug_overlay = cfg.get_value("debug", "show_debug_overlay", show_debug_overlay)
	reactor_mode = cfg.get_value("gameplay", "reactor_mode", reactor_mode)
	currency_loss = cfg.get_value("accessibility", "currency_loss", currency_loss)
	playtest_recording = cfg.get_value("playtest", "recording", playtest_recording)
	playtest_variant = cfg.get_value("playtest", "variant", playtest_variant)
	subtitle_size = cfg.get_value("accessibility", "subtitle_size", subtitle_size)
	subtitle_background = cfg.get_value("accessibility", "subtitle_background", subtitle_background)
	speaker_labels = cfg.get_value("accessibility", "speaker_labels", speaker_labels)
	subtitle_speed = cfg.get_value("accessibility", "subtitle_speed", subtitle_speed)
	cinematic_skip_hold = cfg.get_value("accessibility", "cinematic_skip_hold", cinematic_skip_hold)
	memories_at_anchors = cfg.get_value("accessibility", "memories_at_anchors", memories_at_anchors)


func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	cfg.set_value("accessibility", "hitstop_scale", hitstop_scale)
	cfg.set_value("accessibility", "flash_reduction", flash_reduction)
	cfg.set_value("accessibility", "vibration_strength", vibration_strength)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("debug", "show_debug_overlay", show_debug_overlay)
	cfg.set_value("gameplay", "reactor_mode", reactor_mode)
	cfg.set_value("accessibility", "currency_loss", currency_loss)
	cfg.set_value("playtest", "recording", playtest_recording)
	cfg.set_value("playtest", "variant", playtest_variant)
	cfg.set_value("accessibility", "subtitle_size", subtitle_size)
	cfg.set_value("accessibility", "subtitle_background", subtitle_background)
	cfg.set_value("accessibility", "speaker_labels", speaker_labels)
	cfg.set_value("accessibility", "subtitle_speed", subtitle_speed)
	cfg.set_value("accessibility", "cinematic_skip_hold", cinematic_skip_hold)
	cfg.set_value("accessibility", "memories_at_anchors", memories_at_anchors)
	return cfg.save(_path)
