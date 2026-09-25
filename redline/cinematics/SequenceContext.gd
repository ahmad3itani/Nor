class_name SequenceContext
extends RefCounted
## Where a sequence plays: the room, Rook, the camera, and for boss intros the
## arena and its boss. resolve() turns step actor ids into nodes.

var room: Node = null
var player: Player = null
var camera: PlayerCamera = null
var arena: BossArena = null
var boss: Node = null
## -1 = unset (Cinematics.first_view(seq) decides), 0 = repeat, 1 = first.
## Boss arenas set it: BossArena marks <boss>_intro_seen before the fight
## starts, so the seen flag alone would call every intro a repeat.
var first_view: int = -1
## Overlay-only plays (endings, journal replays): Rook is locked but no actor
## resolves, so nothing in the room is touched.
var overlay_only: bool = false


static func for_room(r: Room) -> SequenceContext:
	var c := SequenceContext.new()
	c._bind_room(r)
	return c


static func for_arena(a: BossArena, is_first_view: bool) -> SequenceContext:
	var c := SequenceContext.new()
	var r: Node = a
	while r != null and not (r is Room):
		r = r.get_parent()
	c._bind_room(r as Room if r else SceneRouter.current_room as Room)
	c.arena = a
	c.boss = a.boss if is_instance_valid(a.boss) else null
	c.first_view = 1 if is_first_view else 0
	return c


## Works with r == null (a menu, a test): nothing is locked then.
static func for_overlay(r: Room) -> SequenceContext:
	var c := SequenceContext.new()
	c._bind_room(r)
	c.camera = null
	c.overlay_only = true
	return c


func _bind_room(r: Room) -> void:
	if r == null or not is_instance_valid(r):
		return
	room = r
	player = r.player if is_instance_valid(r.player) else null
	camera = r.camera if is_instance_valid(r.camera) else null


## Node for an actor id, or null (with a warning: a missing actor is a no-op,
## never a crash; the validator makes it an error for room-bound data).
func resolve(actor: String) -> Node:
	var n: Node = null
	if not overlay_only:
		match actor:
			"@rook":
				n = player
			"@camera":
				n = camera
			"@boss":
				n = boss
			"@arena":
				n = arena
			_:
				if is_instance_valid(room) and actor != "" and not actor.begins_with("@"):
					n = room.get_node_or_null(NodePath(actor))
	if n == null or not is_instance_valid(n):
		push_warning("SequenceContext: actor '%s' did not resolve" % actor)
		return null
	return n
