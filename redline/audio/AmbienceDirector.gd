class_name AmbienceDirector
extends Node
## Ambience beds per room (SOUND_DIRECTION section 7), a child of
## AudioManager (no new autoload). On every room change it resolves the
## room's RoomPresentation (PresentationIndex: the room's own entry, else its
## district default) to a bed and an optional stacked layer, looks both up in
## data/audio/ambience/beds.tres and crossfades over FADE seconds on the
## "Ambience" bus. A room with the same bed as the last one keeps it playing
## (the rain carries on through the door); an unmapped room, an unset bed or a
## missing file fades to silence. Headless runs track the ids and never create
## a player.

const BANK_PATH := "res://data/audio/ambience/beds.tres"
const BUS := &"Ambience"
const FADE := 2.0
const SLOT_BED := 0
const SLOT_LAYER := 1

var bank: AmbienceBank = null
## The playing ids per slot (bed, layer); &"" is silence.
var current: Array[StringName] = [&"", &""]
## How many times a slot (re)started a stream: a room with the same bed must
## not add one (tests read it).
var starts: int = 0
var emitter: AmbientEmitter = null

var _headless: bool = false
## slot -> the AudioStreamPlayer fading in / playing (null when silent).
var _players: Array[AudioStreamPlayer] = [null, null]


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if ResourceLoader.exists(BANK_PATH):
		bank = load(BANK_PATH) as AmbienceBank
	if bank == null:
		bank = AmbienceBank.new()
	emitter = AmbientEmitter.new()
	emitter.name = "Drips"
	var drip: AudioStream = null
	if bank.drip_path != "" and ResourceLoader.exists(bank.drip_path):
		drip = load(bank.drip_path) as AudioStream
	emitter.configure(drip, bank.drip_interval, bank.drip_mix_db, bank.drip_volume_jitter, bank.drip_pan_jitter)
	add_child(emitter)
	# room_entered for world rooms (SOUND_DIRECTION), room_loaded for the
	# title and labs, which never emit it; the same-bed rule makes the pair
	# idempotent.
	EventBus.room_loaded.connect(func(_r: Node) -> void: refresh())
	EventBus.room_entered.connect(func(_d: String, _n: String) -> void: refresh())


## Re-resolves the current room (SceneRouter.current_room). SceneRouter by
## node lookup: AudioManager compiles before the later autoloads and must not
## name them (CLAUDE.md pitfall).
func refresh() -> void:
	var room := router_room(self)
	apply_presentation(PresentationIndex.for_room_node(room) if room != null else null)


## SceneRouter.current_room (null when none or freed), found by node lookup.
static func router_room(from: Node) -> Node:
	var router := from.get_node_or_null(^"/root/SceneRouter")
	if router == null:
		return null
	var room: Variant = router.get(&"current_room")
	return room as Node if is_instance_valid(room) else null


## The (bed, layer) ids a presentation asks for; both &"" for null.
static func beds_of(pres: RoomPresentation) -> Array[StringName]:
	if pres == null:
		return [&"", &""]
	return [pres.ambience, pres.ambience_layer]


func apply_presentation(pres: RoomPresentation) -> void:
	var want := beds_of(pres)
	_set_slot(SLOT_BED, want[0])
	_set_slot(SLOT_LAYER, want[1])
	emitter.set_active(want[0] != &"" and bank.drip_beds.has(want[0]))


## Only beds with a shipped file count as playing; anything else is silence.
func _playable(bed: StringName) -> StringName:
	return bed if bed != &"" and bank.path_for(bed) != "" else &""


func _set_slot(slot: int, bed: StringName) -> void:
	var id := _playable(bed)
	if id == current[slot]:
		return
	current[slot] = id
	if id != &"":
		starts += 1
	if _headless:
		return
	var old := _players[slot]
	if old != null and is_instance_valid(old):
		var out := create_tween()
		out.tween_property(old, "volume_db", -80.0, FADE)
		out.tween_callback(old.queue_free)
	_players[slot] = null
	if id == &"":
		return
	var stream := load(bank.path_for(id)) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = BUS
	p.volume_db = -80.0
	add_child(p)
	p.play()
	_players[slot] = p
	var fade_in := create_tween()
	fade_in.tween_property(p, "volume_db", bank.volume_for(id), FADE)


func _exit_tree() -> void:
	for p in _players:
		if p != null and is_instance_valid(p):
			p.stop()
