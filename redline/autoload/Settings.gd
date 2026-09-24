extends Node
## Player-facing settings, persisted to user://settings.cfg.
##
## M0 skeleton: only values the Movement Lab already consumes (shake, hitstop,
## flash) plus audio levels. Full accessibility menu arrives with M9, but the
## values live here from day one so systems read them instead of hardcoding.

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
var show_debug_overlay: bool = true
## Accessibility (bible §24): dropping unbanked Scrap on death can be disabled.
var currency_loss: bool = true
## Redline Core difficulty (bible §6): 0 Normal, 1 Story/Assist, 2 Redline Challenge.
var reactor_mode: int = 0:
	set(v): reactor_mode = clampi(v, 0, 2)

var _path: String = SETTINGS_PATH


func _ready() -> void:
	load_settings()


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
	show_debug_overlay = cfg.get_value("debug", "show_debug_overlay", show_debug_overlay)
	reactor_mode = cfg.get_value("gameplay", "reactor_mode", reactor_mode)
	currency_loss = cfg.get_value("accessibility", "currency_loss", currency_loss)


func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	cfg.set_value("accessibility", "hitstop_scale", hitstop_scale)
	cfg.set_value("accessibility", "flash_reduction", flash_reduction)
	cfg.set_value("accessibility", "vibration_strength", vibration_strength)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("debug", "show_debug_overlay", show_debug_overlay)
	cfg.set_value("gameplay", "reactor_mode", reactor_mode)
	cfg.set_value("accessibility", "currency_loss", currency_loss)
	return cfg.save(_path)
