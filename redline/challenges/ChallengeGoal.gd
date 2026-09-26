@tool
class_name ChallengeGoal
extends Area2D
## The end of a stage in a staged challenge (a Deep Rig stratum, M9 D3 §3.5
## folded into Challenges, D-147). Placed by roomgen (T10). Body entry reports
## to Challenges.goal_reached; with on_boss set it fires on that boss's defeat
## instead. Outside a run (a dev teleport, the editor) it only draws "Goal".
## Origin: top-left, like SliceEndTrigger.

const LOC_FIELDS := {}

@export var size: Vector2 = Vector2(32, 96):
	set(v):
		size = v
		queue_redraw()
## Matches ChallengeStage.id of the run's current stage.
@export var stage_id: String = ""
## When set, the goal fires on EventBus.boss_defeated(on_boss), not on entry.
@export var on_boss: String = ""

var _fired: bool = false


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
	if on_boss != "":
		EventBus.boss_defeated.connect(_on_boss_defeated)
	else:
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var p := body as Player
	if p == null or p.combat.dead:
		return
	_reach()


func _on_boss_defeated(boss_id: String) -> void:
	if boss_id == on_boss:
		_reach()


func _reach() -> void:
	if _fired or not Challenges.active():
		return
	_fired = true
	Challenges.goal_reached(self)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.5), false, 1.0)
	# l10n: a room-internal marker label (dev teleports and the editor only).
	draw_string(font, Vector2(2, -2), Loc.t("Goal"), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))


## Node content protocol: a stage id and, for boss goals, a matching arena.
func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if stage_id == "" or not RegEx.create_from_string("^[a-z0-9_]+$").search(stage_id):
		out.append("ChallengeGoal needs a stage_id [a-z0-9_]+ (has '%s')" % stage_id)
	if on_boss != "":
		var found := false
		for n in room.find_children("*", "BossArena", true, false):
			if (n as BossArena).boss_id == on_boss:
				found = true
		if not found:
			out.append("ChallengeGoal on_boss '%s' has no BossArena with that boss_id in the room" % on_boss)
	return out
