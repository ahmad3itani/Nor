extends Node
## Dynamic music (bible §28): one set of synced stems whose layer volumes
## follow game state. Title/exploration stay sparse, Flow Zones add rhythm,
## bosses add everything, and a critical core ducks the mix under the
## heartbeat. Music never sits at full intensity for long.
##
## Track mode (presentation overhaul, SOUND_DIRECTION section 8): when the
## music library (data/audio/music/music_library.tres) has a full track for
## the state in the room's music district (or the default set), two decks
## crossfade it in with equal power and the synth stems fade out. States and
## districts without a track (MEMORY, SILENT, Relay explore, the Deep Rig's
## explore) keep the stem mix below, unchanged. In the Relay only the
## arrhythmic growth stems (lead, pad) stay over the track. Explore tracks
## resume where they left off; flow and boss restart. Headless runs create no
## players and render nothing.

## MEMORY stays last: sequences store states as ints, so existing values
## never move.
enum State { SILENT, TITLE, HUB, EXPLORE, FLOW, BOSS, AFTERMATH, MEMORY }

const LAYERS: Array[StringName] = [&"pad", &"bass", &"drums", &"arp", &"lead"]
const MIX := {
	State.SILENT: {},
	State.TITLE: {&"pad": 0.55},
	State.HUB: {&"pad": 0.7},
	State.EXPLORE: {&"pad": 0.7, &"arp": 0.25},
	State.FLOW: {&"pad": 0.5, &"bass": 0.8, &"drums": 0.7, &"arp": 0.45},
	State.BOSS: {&"pad": 0.5, &"bass": 0.9, &"drums": 0.9, &"arp": 0.5, &"lead": 0.7},
	State.AFTERMATH: {&"pad": 0.6},
	# Memory scenes: the world drops away to a thin pad (bible §18/§28).
	State.MEMORY: {&"pad": 0.35},
}
const FADE_TIME := 1.6
const AFTERMATH_TIME := 18.0
const MUSIC_BUS := &"Music"
const LIBRARY_PATH := "res://data/audio/music/music_library.tres"
## MusicSet slot per state (SILENT has none).
const SLOTS := {
	State.TITLE: &"title", State.HUB: &"hub", State.EXPLORE: &"explore", State.FLOW: &"flow",
	State.BOSS: &"boss", State.AFTERMATH: &"aftermath", State.MEMORY: &"memory",
}
## Growth stems that stay over the Relay track: free-time textures only; the
## rhythmic arp, bass and drums would drift against a track they are not
## sample-locked to.
const TRACK_HUB_STEMS: Array[StringName] = [&"lead", &"pad"]
## Crossfade seconds for the tracks, per transition (SOUND_DIRECTION 8).
const FADE_BOSS := 0.6
const FADE_FLOW := 1.0
const FADE_FLOW_TO_EXPLORE := 3.0
const FADE_AFTERMATH := 2.5
const FADE_MEMORY := 1.2
const FADE_DEFAULT := 2.0

var state: State = State.SILENT
var _players: Dictionary = {}
var _ready_streams: bool = false
var _boss_active: bool = false
var _aftermath: float = 0.0
var _district: String = ""
## A scripted state a sequence forces (SeqMusic); -1 = none. Wins over
## everything, so a cinematic can hold silence through a boss room.
var _override: int = -1
## True while a memory playback runs (memory_scene_started ..
## memory_playback_finished, wired in _ready).
var _memory_active: bool = false
## Relay growth table (D-125). Loaded in _ready, not preloaded (CLAUDE.md
## typed-const pitfall).
var _hub_layers: HubMusicLayers = null
## Track library, loaded in _ready (same pitfall).
var _library: MusicLibrary = null
## The current room's music district (RoomPresentation.music_district) and
## scene path, set on room_loaded.
var _music_district: StringName = &""
var _room_path: String = ""
## Background stem renders requested (at most one) and renders that ran on
## the main thread (must stay 0: a render there hitches the frame).
var _stem_requests: int = 0
var _main_thread_renders: int = 0

var _headless: bool = false
var _decks: Array[AudioStreamPlayer] = []
var _deck_path: PackedStringArray = PackedStringArray(["", ""])
var _deck_resumable: Array[bool] = [false, false]
var _active_deck: int = 0
var _deck_gain: float = 0.0
var _deck_tween: Tween = null
## Explore track path -> playback seconds, so EXPLORE resumes after a Flow Zone.
var _resume: Dictionary = {}
var _streams: Dictionary = {}  # path -> AudioStream (lazy)
## HUB extras (MusicSet.extras): stem -> player.
var _extra_players: Dictionary = {}
var _applied_district: StringName = &""
var _last_state: State = State.SILENT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	_ensure_bus()
	_hub_layers = load("res://data/audio/hub_music.tres") as HubMusicLayers
	if ResourceLoader.exists(LIBRARY_PATH):
		_library = load(LIBRARY_PATH) as MusicLibrary
	EventBus.room_entered.connect(func(d: String, _r: String) -> void: _district = d)
	EventBus.room_loaded.connect(func(r: Node) -> void:
		_boss_active = false
		_note_room(r))
	EventBus.boss_started.connect(func(_b: Node2D, _t: String) -> void: _boss_active = true)
	EventBus.boss_defeated.connect(func(_id: String) -> void:
		_boss_active = false
		_aftermath = AFTERMATH_TIME)
	# Memory vignettes (T04): MEMORY from the first scene until the whole
	# request is over (a queue of scenes never dips back to the room's mix).
	EventBus.memory_scene_started.connect(func(_id: String, _s: StringName) -> void: _memory_active = true)
	EventBus.memory_playback_finished.connect(func(_s: StringName) -> void: _memory_active = false)
	EventBus.memory_playback_aborted.connect(func(_s: StringName) -> void: _memory_active = false)
	# No audio device in headless runs (tests, probes): track state, skip synthesis.
	if not _headless:
		for i in 2:
			var deck := AudioStreamPlayer.new()
			deck.bus = MUSIC_BUS
			deck.volume_db = -80.0
			add_child(deck)
			_decks.append(deck)
		# Stems render eagerly in the background, never when a stem state is
		# first requested (a render on demand would hitch that frame).
		_stem_requests += 1
		WorkerThreadPool.add_task(_render_all)


func _render_all() -> void:
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		_main_thread_renders += 1
	var streams := {}
	for layer in LAYERS:
		streams[layer] = MusicSynth.render(layer)
	_install.call_deferred(streams)


func _install(streams: Dictionary) -> void:
	for layer: StringName in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[layer]
		p.bus = MUSIC_BUS
		p.volume_db = -80.0
		add_child(p)
		_players[layer] = p
	for p: AudioStreamPlayer in _players.values():
		p.play()
	_ready_streams = true
	_apply_stems(true)


func _note_room(room: Node) -> void:
	_room_path = room.scene_file_path if room != null and is_instance_valid(room) else ""
	var pres := PresentationIndex.for_room_node(room) if room != null and is_instance_valid(room) else null
	_music_district = pres.music_district if pres != null else &""


func _process(delta: float) -> void:
	_aftermath = maxf(_aftermath - delta, 0.0)
	var next := _pick_state()
	if next != state or _music_district != _applied_district:
		_last_state = state
		state = next
		_applied_district = _music_district
		_apply(false)
	_duck_for_critical()


func set_override(s: int) -> void:
	_override = s


func clear_override() -> void:
	_override = -1


func _pick_state() -> State:
	if _override >= 0:
		return _override as State
	if _memory_active:
		return State.MEMORY
	var room := SceneRouter.current_room
	if room == null:
		return State.SILENT
	if not room is Room:
		return State.TITLE
	var player := (room as Room).player
	if _boss_active:
		return State.BOSS
	if _aftermath > 0.0:
		return State.AFTERMATH
	if player and is_instance_valid(player) and player.reactor.in_flow():
		return State.FLOW
	if (room as Room).district_name == "The Relay":
		return State.HUB
	return State.EXPLORE


## The Relay's theme grows with the settlement (bible §13, §28).
func _mix_for(s: State) -> Dictionary:
	var mix: Dictionary = MIX[s].duplicate()
	if s == State.HUB and _hub_layers != null:
		mix.merge(_hub_layers.active_mix(), true)
	return mix


## Stem mix while a track plays: silence, except the Relay's arrhythmic
## growth stems over the hub track.
func _track_stem_mix(s: State) -> Dictionary:
	var mix := {}
	if s == State.HUB and _hub_layers != null:
		var grown := _hub_layers.active_mix()
		for stem: StringName in grown:
			if TRACK_HUB_STEMS.has(stem):
				mix[stem] = grown[stem]
	return mix


## {path, gain, resumable} for a state in a music district (gain: the set's
## MusicSet.gain_for level, times aftermath_gain for AFTERMATH); path "" means
## "no track here: play the stems". Asks the district's set, then the
## default set; a path whose file is missing counts as none.
func _track_for(s: int, district: StringName = _music_district, room_path: String = _room_path) -> Dictionary:
	var none := {"path": "", "gain": 0.0, "resumable": false}
	if _library == null or not SLOTS.has(s):
		return none
	var chain := _library.chain(district)
	if s == State.BOSS and room_path != "":
		for ms in chain:
			var p := str(ms.boss_by_room.get(room_path, ""))
			if _exists(p):
				return {"path": p, "gain": ms.gain_for(&"boss"), "resumable": false}
	var slot: StringName = SLOTS[s]
	for ms in chain:
		var p := ms.slot(slot)
		if _exists(p):
			# Explore and the hub resume where they left off; flow and boss restart.
			return {"path": p, "gain": ms.gain_for(slot), "resumable": s == State.HUB or s == State.EXPLORE}
	if s == State.AFTERMATH:
		for ms in chain:
			var p := ms.slot(&"explore")
			if _exists(p):
				return {"path": p, "gain": ms.gain_for(&"explore") * ms.aftermath_gain, "resumable": true}
	return none


static func _exists(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path)


## Crossfade seconds from one state to another in track mode.
static func _fade_time(from: int, to: int) -> float:
	if to == State.BOSS:
		return FADE_BOSS
	if to == State.FLOW:
		return FADE_FLOW
	if from == State.FLOW and to == State.EXPLORE:
		return FADE_FLOW_TO_EXPLORE
	if to == State.AFTERMATH:
		return FADE_AFTERMATH
	if to == State.MEMORY:
		return FADE_MEMORY
	return FADE_DEFAULT


func _apply(instant: bool) -> void:
	var track := _track_for(state)
	var fade := 0.0 if instant else _fade_time(_last_state, state)
	if not _headless:
		_apply_decks(str(track["path"]), float(track["gain"]), bool(track["resumable"]), fade)
		_apply_extras(str(track["path"]) != "", fade)
	_apply_stems(instant, str(track["path"]) != "")


func _apply_stems(instant: bool, track_mode: bool = false) -> void:
	if not _ready_streams:
		return
	if not track_mode and _deck_path[_active_deck] != "":
		track_mode = true
	var mix := _track_stem_mix(state) if track_mode else _mix_for(state)
	for layer: StringName in _players:
		var target := linear_to_db(maxf(float(mix.get(layer, 0.0)), 0.0001))
		var p: AudioStreamPlayer = _players[layer]
		if instant:
			p.volume_db = target
		else:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", target, FADE_TIME)


func _load_track(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if _exists(path) else null
	return _streams[path]


## Equal-power crossfade between the two decks: the outgoing deck follows
## cos, the incoming sin, so the summed power stays level.
func _apply_decks(path: String, gain: float, resumable: bool, fade: float) -> void:
	if _decks.size() < 2:
		return
	var cur := _decks[_active_deck]
	if _deck_tween != null and _deck_tween.is_valid():
		_deck_tween.kill()
	if path == _deck_path[_active_deck]:
		# Same track (EXPLORE <-> AFTERMATH): only the level moves.
		var from_gain := db_to_linear(cur.volume_db)
		_deck_gain = gain
		if path == "":
			return
		_deck_tween = create_tween()
		_deck_tween.tween_method(func(g: float) -> void: cur.volume_db = linear_to_db(maxf(g, 0.0001)),
			from_gain, gain, maxf(fade, 0.01))
		return
	if _deck_path[_active_deck] != "" and _deck_resumable[_active_deck] and cur.playing:
		_resume[_deck_path[_active_deck]] = cur.get_playback_position()
	var old_gain := db_to_linear(cur.volume_db) if _deck_path[_active_deck] != "" else 0.0
	var nxt_i := 1 - _active_deck
	var nxt := _decks[nxt_i]
	nxt.stop()
	nxt.volume_db = -80.0
	_deck_path[nxt_i] = ""
	var stream := _load_track(path) if path != "" else null
	if stream != null:
		nxt.stream = stream
		var at := float(_resume.get(path, 0.0)) if resumable else 0.0
		nxt.play(at)
		_deck_path[nxt_i] = path
	_deck_resumable[nxt_i] = resumable
	_active_deck = nxt_i
	_deck_gain = gain if stream != null else 0.0
	var new_gain := _deck_gain
	if fade <= 0.0:
		cur.stop()
		nxt.volume_db = linear_to_db(maxf(new_gain, 0.0001))
		return
	_deck_tween = create_tween()
	_deck_tween.tween_method(func(t: float) -> void:
		cur.volume_db = linear_to_db(maxf(old_gain * cos(t * PI * 0.5), 0.0001))
		nxt.volume_db = linear_to_db(maxf(new_gain * sin(t * PI * 0.5), 0.0001)),
		0.0, 1.0, fade)
	_deck_tween.tween_callback(cur.stop)


## HUB extras (MusicSet.extras): free-time loops over the hub track.
func _apply_extras(track_mode: bool, fade: float) -> void:
	var extras := {}
	var extras_gain := 1.0
	if track_mode and state == State.HUB and _library != null:
		for ms in _library.chain(_music_district):
			if not ms.extras.is_empty():
				extras = ms.extras
				extras_gain = ms.gain_for(&"hub")
				break
	var mix := _mix_for(State.HUB) if state == State.HUB else {}
	for stem: Variant in extras:
		var sn := StringName(str(stem))
		if not _extra_players.has(sn):
			var stream := _load_track(str(extras[stem]))
			if stream == null:
				continue
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.bus = MUSIC_BUS
			p.volume_db = -80.0
			add_child(p)
			p.play()
			_extra_players[sn] = p
	for sn: StringName in _extra_players:
		var target := linear_to_db(maxf(float(mix.get(sn, 0.0)) * extras_gain if extras.has(sn) else 0.0, 0.0001))
		var tw := create_tween()
		tw.tween_property(_extra_players[sn], "volume_db", target, maxf(fade, 0.01))


func _duck_for_critical() -> void:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx < 0:
		return
	var room := SceneRouter.current_room as Room
	var critical := room and is_instance_valid(room.player) and room.player.reactor.is_critical() and room.player.reactor.in_flow()
	var target := linear_to_db(Settings.music_volume) - (7.0 if critical else 0.0)
	var cur := AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, lerpf(cur, target, 0.08))


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, MUSIC_BUS)
	AudioServer.set_bus_send(idx, &"Master")
