@tool
class_name SequenceTrigger
extends Area2D
## Starts a scripted sequence (M8, D-106) in a room: on entry (autoplay: the
## Wake opening, the Relay arrival) or when Rook walks into its area.
## Origin: top-left of the area, like HintTrigger.
##
## Safety rules (A1 §4.1 as amended):
## - A locking sequence never starts while an enemy in the room is active
##   (no cheap input lock during danger); it retries every 0.5 s while the
##   room is ready (autoplay) or Rook is inside. Non-locking barks play
##   regardless (they take no control).
## - Nothing starts while a dev preview or the story tour owns Cinematics
##   (CinematicMode.theatre). While another play is running (a bark, a boss
##   intro) the trigger waits and retries every 0.5 s, like the danger rule.
## - A refused or aborted play re-arms the trigger: the seen flag is set only
##   by a finished or skipped play (SequencePlayer), so a quit replays it.

const RETRY_SECONDS := 0.5

@export var size: Vector2 = Vector2(64, 96):
	set(v):
		size = v
		queue_redraw()
@export var sequence: SequenceData
## Every entry must pass Game.check_condition (AND; NPC.present_when is OR).
@export var play_when: PackedStringArray = []
## Play when the room is ready (no body needed).
@export var autoplay: bool = false
## Only when the room was entered at this spawn (room.active_spawn()).
@export var require_spawn: StringName = &""
## Skip once the sequence's seen flag is set.
@export var once: bool = true

var _busy: bool = false
var _done: bool = false
var _pending: bool = false
var _retry: float = 0.0
var _inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(false)
	# Deferred: children are ready before their parent, so the Room builds
	# its player and camera after this _ready (world/rooms/Room.gd:_ready).
	if autoplay:
		_try_play.call_deferred()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	_inside = true
	if not autoplay:
		_try_play()


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_inside = false


## Retry loop while a locking play waits for the room to calm down.
func _process(delta: float) -> void:
	if not _pending:
		set_process(false)
		return
	if not autoplay and not _inside:
		return
	_retry -= delta
	if _retry <= 0.0:
		_try_play()


func _room() -> Room:
	var n: Node = get_parent()
	while n != null and not (n is Room):
		n = n.get_parent()
	return n as Room


## Whether this trigger would play now (ignoring enemies and other plays).
func eligible() -> bool:
	if sequence == null or _busy or _done:
		return false
	if once and Game.has_flag(sequence.effective_seen_flag()):
		return false
	for c in play_when:
		if not Game.check_condition(c):
			return false
	if require_spawn != &"":
		var room := _room()
		if room == null or room.spawns.is_empty() or room.active_spawn().spawn_id != require_spawn:
			return false
	return true


## An enemy that could hurt a locked Rook: awake, alive and doing something.
func danger() -> bool:
	var room := _room()
	if room == null:
		return false
	for n in room.find_children("*", "Enemy", true, false):
		var e := n as Enemy
		if e.ai_enabled and not e.is_dead() and e.ai != Enemy.AI.IDLE:
			return true
	return false


func _try_play() -> void:
	_pending = false
	# A dev preview or the story tour already owns the room: stay quiet.
	if CinematicMode.theatre:
		return
	if not is_inside_tree() or not eligible():
		return
	# Another play first (it ends on its own), or danger for a locking one.
	if Cinematics.is_playing() or (sequence.locks_for(Cinematics.first_view(sequence)) and danger()):
		_arm_retry()
		return
	_busy = true
	var res := await Cinematics.play(sequence, SequenceContext.for_room(_room()))
	_busy = false
	if res.refused:
		_arm_retry()
		return
	if res.aborted():
		return  # re-armed: a later entry plays it from the start
	if once:
		_done = true


func _arm_retry() -> void:
	if not is_inside_tree():
		return
	_pending = true
	_retry = RETRY_SECONDS
	set_process(true)


## ContentValidator protocol: the sequence's flags plus the play conditions.
func content_flags() -> Dictionary:
	var d := {"produces": [], "consumes": [], "conditions": Array(play_when)}
	if sequence:
		var s := sequence.content_flags()
		d["produces"].append_array(s.get("produces", []))
		d["consumes"].append_array(s.get("consumes", []))
		d["conditions"].append_array(s.get("conditions", []))
	return d


func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if sequence == null:
		out.append("SequenceTrigger has no sequence")
		return out
	if sequence.room != room.scene_file_path:
		out.append("sequence %s is authored for %s, not this room" % [sequence.id, sequence.room if sequence.room != "" else "no room"])
	if require_spawn != &"":
		var found := false
		for n in room.find_children("*", "SpawnMarker", true, false):
			if (n as SpawnMarker).spawn_id == require_spawn:
				found = true
		if not found:
			out.append("require_spawn '%s' is not a spawn in this room" % require_spawn)
	return out


func _draw() -> void:
	# Editor only: in play it is invisible.
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.45, 1.0, 0.6), false, 1.0)
