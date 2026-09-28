@tool
class_name Anchor
extends Interactable
## Anchor (bible §7): rest to refill health, injectors and core, bank Scrap,
## set the respawn point and save. Opens the loadout menu (Circuits, weapons).
## The spawn marker with the same id must exist in the room (Room validates).

const CORE_COLOR := Color("e8283c")

@export var anchor_id: StringName = &"anchor"

var _pulse: float = 0.0
## Presentation (T06): the looping rest embers and who they follow.
var rest_embers: VfxOneShot
var _rest_player: Player
var _rest_at: Vector2
var _bloom: VfxOneShot
var _bloom_pending: bool = false
var _resting: bool = false

## Rook still counts as resting while in one of these states and within
## REST_RADIUS of where he rested (there is no rest state or rest-ended
## signal; the embers are polled away, T06 REPAIR).
const REST_STATES: Array[StringName] = [&"idle", &"crouch"]
const REST_RADIUS := 12.0


func _ready() -> void:
	prompt_verb = "Rest"  # l10n
	super._ready()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()
	if not Engine.is_editor_hint():
		_poll_rest_vfx()


func is_active_respawn() -> bool:
	if Engine.is_editor_hint():
		return false
	return Game.state.last_anchor_id == String(anchor_id) and Game.state.last_anchor_room == SceneRouter.current_room_path


func interact(player: Player) -> void:
	Game.rest_at_anchor(SceneRouter.current_room_path, String(anchor_id))
	player.combat.rest()
	player.reactor.charge = player.reactor.config.max_charge
	AudioManager.play_sfx(&"anchor")
	rest_vfx(player)
	EventBus.anchor_rested.emit(self)
	# M8 (D-112): recovered memories surface here, where the world is already
	# safe, then the loadout opens as before. Never on pickup, never in danger.
	var ids := MemoryLibrary.pending_for_rest()
	if ids.is_empty() or not Settings.memories_at_anchors or not is_instance_valid(MemoryScenePlayer.active_instance):
		EventBus.menu_requested.emit(&"loadout")
		return
	# Connected before the request: INSTANT playback finishes inside the emit.
	EventBus.memory_playback_finished.connect(_after_memories, CONNECT_ONE_SHOT)
	EventBus.memory_playback_aborted.connect(_memories_aborted, CONNECT_ONE_SHOT)
	EventBus.memory_playback_requested.emit(ids, &"anchor")


func _after_memories(_source: StringName) -> void:
	if EventBus.memory_playback_aborted.is_connected(_memories_aborted):
		EventBus.memory_playback_aborted.disconnect(_memories_aborted)
	# rest_at_anchor saved before the vignettes ran: save again so the flags
	# they set (mem_seen_*, details, arc stages they unlock) survive a quit.
	Game.save_game()
	if not MemoryLibrary.pending().is_empty():
		EventBus.hint_requested.emit(Loc.t(MemoryLibrary.config().more_waiting_hint), 3.0)
	EventBus.menu_requested.emit(&"loadout")


## An aborted playback remembers nothing and opens nothing: drop the pending
## follow-up so it never fires on a later, unrelated playback.
func _memories_aborted(_source: StringName) -> void:
	if EventBus.memory_playback_finished.is_connected(_after_memories):
		EventBus.memory_playback_finished.disconnect(_after_memories)


## The rest bloom (roots light up to the socket), then embers looping on
## Rook while he rests; the old core sparks when the sheet is missing.
func rest_vfx(player: Player) -> void:
	stop_rest_vfx()
	_rest_player = player
	_resting = player != null
	_rest_at = player.global_position if player else global_position
	_bloom = VfxOneShot.spawn(get_parent(), &"anchor_rest", &"bloom", global_position)
	_bloom_pending = _bloom != null
	if _bloom == null:
		HitSpark.spawn(get_parent(), global_position + Vector2(0, -20), Vector2.UP, CORE_COLOR, 18, 120.0)
		_start_embers()


func _start_embers() -> void:
	if is_instance_valid(rest_embers) or not is_instance_valid(_rest_player) or not _rest_player.is_inside_tree():
		return
	rest_embers = VfxOneShot.spawn(get_parent(), &"anchor_rest", &"embers", _rest_player.global_position,
		{"follow": _rest_player})


func is_resting(player: Player) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and REST_STATES.has(player.current_state_id()) \
		and player.global_position.distance_to(_rest_at) <= REST_RADIUS


func stop_rest_vfx() -> void:
	if is_instance_valid(rest_embers):
		rest_embers.stop()
	rest_embers = null
	_bloom = null
	_bloom_pending = false


## Embers start when the bloom ends and stop once Rook stops resting.
func _poll_rest_vfx() -> void:
	if not _resting:
		return
	if not is_resting(_rest_player):
		stop_rest_vfx()
		_resting = false
		_rest_player = null
		return
	if _bloom_pending and not is_instance_valid(_bloom):
		_bloom_pending = false
		_start_embers()


func _draw() -> void:
	# Pedestal + floating core; brighter when it is the current respawn point.
	draw_rect(Rect2(-7, -6, 14, 6), Color("4a4458"))
	draw_rect(Rect2(-3, -22, 6, 16), Color("6b6380"))
	var glow := 0.55 + 0.45 * sin(_pulse * 3.0)
	var c := CORE_COLOR
	c.a = 0.5 + 0.5 * glow if is_active_respawn() else 0.35
	draw_rect(Rect2(-4, -34 + sin(_pulse * 2.0), 8, 8), c)
