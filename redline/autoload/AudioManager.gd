extends Node
## Single entry point for sound (bible §28). M1 plays synthesized placeholder
## SFX from data/audio/placeholder_sfx.tres through a small voice pool on the
## "SFX" bus, whose volume follows Settings. M9 (D4 §9): menu and prompt sounds
## (ui_* ids, the achievement chime) play on a separate "UI" bus with its own
## slider, so a player can quiet combat without losing menu feedback.

const BANK_PATH := "res://data/audio/placeholder_sfx.tres"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"
const VOICES := 8

var _streams: Dictionary = {}      # id -> AudioStream
var _defs: Dictionary = {}         # id -> SfxDefinition
var _last_played: Dictionary = {}  # id -> msec
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	_ensure_bus()
	load_bank(load(BANK_PATH) as SfxBank)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
	apply_volume()


func load_bank(bank: SfxBank) -> void:
	_streams.clear()
	_defs.clear()
	if bank == null:
		push_error("AudioManager: missing SFX bank")
		return
	for def in bank.sounds:
		_defs[def.id] = def
		_streams[def.id] = SfxSynth.render(def, hash(def.id))


func has_sfx(id: StringName) -> bool:
	return _streams.has(id)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(Settings.master_volume))
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(Settings.sfx_volume))
	var music := AudioServer.get_bus_index(&"Music")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(Settings.music_volume))
	var ui := AudioServer.get_bus_index(UI_BUS)
	if ui >= 0:
		AudioServer.set_bus_volume_db(ui, linear_to_db(Settings.ui_volume))


## The bus a sound id plays on: interface sounds on "UI", the rest on "SFX".
static func bus_for(id: StringName) -> StringName:
	return UI_BUS if String(id).begins_with("ui_") or id == &"achievement" else SFX_BUS


## volume_scale: 0..1+ multiplier (e.g. landing impact). Unknown ids warn once.
func play_sfx(id: StringName, volume_scale: float = 1.0) -> void:
	if not _streams.has(id):
		push_warning("AudioManager: unknown sfx %s" % id)
		_streams[id] = null
		return
	var stream: AudioStream = _streams[id]
	if stream == null or volume_scale <= 0.0:
		return
	var def: SfxDefinition = _defs[id]
	var now := Time.get_ticks_msec()
	if def.cooldown > 0.0 and now - int(_last_played.get(id, -100000)) < int(def.cooldown * 1000.0):
		return
	_last_played[id] = now
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.bus = bus_for(id)
	voice.volume_db = def.volume_db + linear_to_db(volume_scale)
	voice.pitch_scale = 1.0 + randf_range(-def.pitch_jitter, def.pitch_jitter)
	voice.play()


func _ensure_bus() -> void:
	for bus_name: StringName in [SFX_BUS, UI_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")


func _exit_tree() -> void:
	# Stop voices so playbacks aren't leaked when the game quits mid-sound.
	for v in _voices:
		v.stop()
		v.stream = null
