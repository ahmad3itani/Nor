extends Node
## Single entry point for sound (bible §28). Plays the SFX bank
## (data/audio/placeholder_sfx.tres) through a voice pool on the "SFX" bus,
## whose volume follows Settings. M9 (D4 §9): menu and prompt sounds (ui_*
## ids, the achievement chime) play on a separate "UI" bus with its own
## slider, so a player can quiet combat without losing menu feedback.
##
## Presentation overhaul (SOUND_DIRECTION sections 3, 6, 7):
## - each id plays its real asset (`override_stream`: an OGG or an
##   AudioStreamRandomizer of takes) and falls back to the SfxSynth render of
##   its parameters when there is none, so a missing file never goes silent;
## - 16 voices; when all are busy a sound takes the least important
##   (SfxDefinition.priority), oldest voice, never a more important one;
## - an "Ambience" bus (sfx_volume x ambience_volume) with the
##   AmbienceDirector child (beds per room, drip emitter) and a
##   FootstepDirector child (steps per surface);
## - a mild duck of the Music bus under loud SFX (a sidechained compressor).
## Pitch jitter uses this node's own RandomNumberGenerator, never the global
## one, so sound never shifts gameplay randomness.

const BANK_PATH := "res://data/audio/placeholder_sfx.tres"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"
const MUSIC_BUS := &"Music"
const AMBIENCE_BUS := &"Ambience"
const AMBIENCE_FX_BUS := &"AmbienceFx"
const VOICES := 16
## Seconds a voice counts as busy when its stream has no known length.
const UNKNOWN_LENGTH := 1.0

var ambience: AmbienceDirector = null
var footsteps: FootstepDirector = null

var _streams: Dictionary = {}      # id -> AudioStream
var _defs: Dictionary = {}         # id -> SfxDefinition
var _lengths: Dictionary = {}      # id -> seconds (0 = unknown)
var _last_played: Dictionary = {}  # id -> msec
var _voices: Array[AudioStreamPlayer] = []
## Per voice: the playing id, its priority, start and expected end (msec).
var _voice_id: Array[StringName] = []
var _voice_priority: PackedInt32Array = PackedInt32Array()
var _voice_start: PackedInt64Array = PackedInt64Array()
var _voice_end: PackedInt64Array = PackedInt64Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5f3a
	_ensure_bus()
	_setup_mix()
	load_bank(load(BANK_PATH) as SfxBank)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
		_voice_id.append(&"")
	_voice_priority.resize(VOICES)
	_voice_start.resize(VOICES)
	_voice_end.resize(VOICES)
	_voice_end.fill(0)
	ambience = AmbienceDirector.new()
	ambience.name = "Ambience"
	add_child(ambience)
	footsteps = FootstepDirector.new()
	footsteps.name = "Footsteps"
	add_child(footsteps)
	# Stingers the bus already announces (SOUND_DIRECTION section 5, C5).
	EventBus.boss_defeated.connect(func(_id: String) -> void: play_sfx(&"boss_defeat"))
	EventBus.secret_found.connect(func(_id: String) -> void: play_sfx(&"secret_found"))
	apply_volume()


## The real asset when the definition has one, else the synth render.
func load_bank(bank: SfxBank) -> void:
	_streams.clear()
	_defs.clear()
	_lengths.clear()
	if bank == null:
		push_error("AudioManager: missing SFX bank")
		return
	for def in bank.sounds:
		_defs[def.id] = def
		_streams[def.id] = def.override_stream if def.override_stream else SfxSynth.render(def, hash(def.id))
		_lengths[def.id] = stream_length(_streams[def.id])


func has_sfx(id: StringName) -> bool:
	return _streams.has(id)


## The stream an id plays (override or synth), or null.
func stream_for(id: StringName) -> AudioStream:
	return _streams.get(id) as AudioStream


## Seconds a stream lasts (the longest take of a randomizer), 0 if unknown.
static func stream_length(s: AudioStream) -> float:
	if s == null:
		return 0.0
	if s is AudioStreamRandomizer:
		var r := s as AudioStreamRandomizer
		var longest := 0.0
		for i in r.streams_count:
			longest = maxf(longest, stream_length(r.get_stream(i)))
		return longest
	return s.get_length()


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(Settings.master_volume))
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(Settings.sfx_volume))
	var music := AudioServer.get_bus_index(MUSIC_BUS)
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(Settings.music_volume))
	var ui := AudioServer.get_bus_index(UI_BUS)
	if ui >= 0:
		AudioServer.set_bus_volume_db(ui, linear_to_db(Settings.ui_volume))
	# Ambience has its own slider under the SFX one (T01): both scale it.
	var amb := AudioServer.get_bus_index(AMBIENCE_BUS)
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, linear_to_db(Settings.sfx_volume * Settings.ambience_volume))


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
	var v := pick_voice(def.priority, now)
	if v < 0:
		return
	_last_played[id] = now
	var voice := _voices[v]
	var pitch := 1.0 + _rng.randf_range(-def.pitch_jitter, def.pitch_jitter)
	voice.stream = stream
	voice.bus = bus_for(id)
	voice.volume_db = def.volume_db + linear_to_db(volume_scale)
	voice.pitch_scale = pitch
	voice.play()
	var length := float(_lengths.get(id, 0.0))
	if length <= 0.0:
		length = UNKNOWN_LENGTH
	_voice_id[v] = id
	_voice_priority[v] = def.priority
	_voice_start[v] = now
	_voice_end[v] = now + int(length / maxf(pitch, 0.01) * 1000.0)


## A free voice, else the least important (highest priority number), oldest
## busy one if it is not more important than `priority`, else -1 (dropped).
func pick_voice(priority: int, now: int) -> int:
	var best := -1
	for i in _voices.size():
		if not voice_busy(i, now):
			return i
		if best < 0 or _voice_priority[i] > _voice_priority[best] \
				or (_voice_priority[i] == _voice_priority[best] and _voice_start[i] < _voice_start[best]):
			best = i
	if best >= 0 and _voice_priority[best] < priority:
		return -1
	return best


func voice_busy(i: int, now: int) -> bool:
	return _voice_id[i] != &"" and now < _voice_end[i]


## The ids the busy voices play right now (tests, debug overlay).
func busy_ids(now: int = Time.get_ticks_msec()) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in _voices.size():
		if voice_busy(i, now):
			out.append(_voice_id[i])
	return out


## Frees every voice (tests use it between stealing checks).
func stop_all() -> void:
	for i in _voices.size():
		_voices[i].stop()
		_voice_id[i] = &""
		_voice_end[i] = 0


func _ensure_bus() -> void:
	for bus_name: StringName in [SFX_BUS, UI_BUS, MUSIC_BUS, AMBIENCE_BUS, AMBIENCE_FX_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, AMBIENCE_BUS if bus_name == AMBIENCE_FX_BUS else &"Master")


## Bus effects (SOUND_DIRECTION section 3): the drip emitter's panner, and a
## mild sidechain duck of the Music bus from SFX (3:1 above -18 dB, 5 ms
## attack, 250 ms release: about 2-3 dB on big hits). Idempotent.
func _setup_mix() -> void:
	var fx := AudioServer.get_bus_index(AMBIENCE_FX_BUS)
	if fx >= 0 and AudioServer.get_bus_effect_count(fx) == 0:
		AudioServer.add_bus_effect(fx, AudioEffectPanner.new())
	var music := AudioServer.get_bus_index(MUSIC_BUS)
	if music < 0:
		return
	for i in AudioServer.get_bus_effect_count(music):
		if AudioServer.get_bus_effect(music, i) is AudioEffectCompressor:
			return
	var duck := AudioEffectCompressor.new()
	duck.threshold = -18.0
	duck.ratio = 3.0
	duck.attack_us = 5000.0
	duck.release_ms = 250.0
	duck.sidechain = SFX_BUS
	AudioServer.add_bus_effect(music, duck)


func _exit_tree() -> void:
	# Stop voices so playbacks aren't leaked when the game quits mid-sound.
	for v in _voices:
		v.stop()
		v.stream = null
