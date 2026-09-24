extends Node
## Dynamic music (bible §28): one set of synced stems whose layer volumes
## follow game state. Title/exploration stay sparse, Flow Zones add rhythm,
## bosses add everything, and a critical core ducks the mix under the
## heartbeat. Music never sits at full intensity for long.

enum State { SILENT, TITLE, HUB, EXPLORE, FLOW, BOSS, AFTERMATH }

const LAYERS: Array[StringName] = [&"pad", &"bass", &"drums", &"arp", &"lead"]
const MIX := {
	State.SILENT: {},
	State.TITLE: {&"pad": 0.55},
	State.HUB: {&"pad": 0.7},
	State.EXPLORE: {&"pad": 0.7, &"arp": 0.25},
	State.FLOW: {&"pad": 0.5, &"bass": 0.8, &"drums": 0.7, &"arp": 0.45},
	State.BOSS: {&"pad": 0.5, &"bass": 0.9, &"drums": 0.9, &"arp": 0.5, &"lead": 0.7},
	State.AFTERMATH: {&"pad": 0.6},
}
const FADE_TIME := 1.6
const AFTERMATH_TIME := 18.0
const MUSIC_BUS := &"Music"

var state: State = State.SILENT
var _players: Dictionary = {}
var _ready_streams: bool = false
var _boss_active: bool = false
var _aftermath: float = 0.0
var _district: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	EventBus.room_entered.connect(func(d: String, _r: String) -> void: _district = d)
	EventBus.room_loaded.connect(func(_r: Node) -> void: _boss_active = false)
	EventBus.boss_started.connect(func(_b: Node2D, _t: String) -> void: _boss_active = true)
	EventBus.boss_defeated.connect(func(_id: String) -> void:
		_boss_active = false
		_aftermath = AFTERMATH_TIME)
	# No audio device in headless runs (tests, probes): track state, skip synthesis.
	if DisplayServer.get_name() != "headless":
		WorkerThreadPool.add_task(_render_all)


func _render_all() -> void:
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
	_apply(true)


func _process(delta: float) -> void:
	_aftermath = maxf(_aftermath - delta, 0.0)
	var next := _pick_state()
	if next != state:
		state = next
		_apply(false)
	_duck_for_critical()


func _pick_state() -> State:
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
	if s == State.HUB:
		if Game.has_flag("dead_air_complete"):
			mix[&"arp"] = 0.35
		if Game.has_flag("warden_krail_defeated"):
			mix[&"bass"] = 0.45
	return mix


func _apply(instant: bool) -> void:
	if not _ready_streams:
		return
	var mix := _mix_for(state)
	for layer: StringName in _players:
		var target := linear_to_db(maxf(float(mix.get(layer, 0.0)), 0.0001))
		var p: AudioStreamPlayer = _players[layer]
		if instant:
			p.volume_db = target
		else:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", target, FADE_TIME)


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
