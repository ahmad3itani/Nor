class_name RemixLibrary
extends RefCounted
## NG+ room remixes (M9 D3 §2.5, D-154): data ops (enemy swaps, hazard
## changes, boss knobs) applied to a room instance between instantiate() and
## add_child() in SceneRouter.goto_room, so every _ready reads the remixed
## values. 0 ops unless the room's RoomRemix is active (flag ng_remix).
##
## Pitfalls (D3 §5.14): never call apply() on a node already in the tree
## (REMOVE frees the node at once), and never from _enter_tree/_ready.

const DEFAULT_DIR := "res://data/remix"

## Where the remix files live (tests point it at fixtures and restore it).
static var data_dir: String = DEFAULT_DIR
## Tests and the dev page: apply every remix as if its condition held.
static var force_active: bool = false
## Room path -> ops applied on its last load (tests and the dev page read it).
static var last_applied: Dictionary = {}
## Room path -> whether its remix ran on the last load (DebugOverlay line).
static var _last_active: Dictionary = {}
## basename -> RoomRemix (null = no file), built once per data_dir.
static var _index: Dictionary = {}
static var _index_dir: String = ""
## Per-room ADD counters so added names never collide ("NeedleR1", ...).
static var _added: Dictionary = {}


## The remix for a room path, or null (file name == room basename, RM-1).
static func for_room(path: String) -> RoomRemix:
	_ensure_index()
	return _index.get(path.get_file().get_basename()) as RoomRemix


## Every remix file, by path (RemixRules, EconomyAudit, the dev report).
static func all_paths() -> PackedStringArray:
	return DataDir.list(data_dir)


static func _ensure_index() -> void:
	if _index_dir == data_dir:
		return
	_index = {}
	_index_dir = data_dir
	for p in DataDir.list(data_dir):
		var r := load(p) as RoomRemix
		if r != null:
			_index[p.get_file().get_basename()] = r


## Applies the active remix ops for `path` to `inst`; returns how many ran.
## `force` bypasses the activation condition (EconomyAudit, dev report).
static func apply(inst: Node, path: String, force: bool = false) -> int:
	var remix := for_room(path)
	var active := remix != null and (force or force_active or remix.is_active())
	var n := 0
	if active:
		n = apply_ops(inst, remix)
	last_applied[path] = n
	_last_active[path] = active
	_register_overlay()
	return n


## Runs every op of `remix` on `inst` (the caller decided it is active).
## A bad op (stale name, class outside the whitelist) is skipped with an
## error; RemixRules reports the same op as a content error.
static func apply_ops(inst: Node, remix: RoomRemix) -> int:
	var n := 0
	var key := remix.room
	_added[key] = 0
	for op in remix.ops:
		if op != null and _apply_op(inst, op, key):
			n += 1
	return n


static func _apply_op(inst: Node, op: RemixOp, key: String) -> bool:
	var node := inst.get_node_or_null(op.target)
	if node == null:
		push_error("RemixLibrary: %s: no node %s" % [key.get_file(), op.target])
		return false
	match op.kind:
		RemixOp.Kind.REMOVE_ENEMY:
			if not node is Enemy:
				push_error("RemixLibrary: REMOVE %s is not an Enemy" % op.target)
				return false
			node.get_parent().remove_child(node)
			node.free()
			return true
		RemixOp.Kind.SWAP_ENEMY:
			if not node is Enemy:
				push_error("RemixLibrary: SWAP %s is not an Enemy" % op.target)
				return false
			var old := node as Enemy
			var fresh := _spawn(op)
			if fresh == null:
				return false
			fresh.name = String(old.name) + "R"
			fresh.position = old.position
			fresh.facing = op.facing if op.facing != 0 else old.facing
			fresh.ai_enabled = old.ai_enabled
			# R09.11: a replacement pays what the enemy it replaced paid.
			fresh.data = with_drop(op.data, old.data.scrap_drop if old.data else 0)
			var parent := old.get_parent()
			var at := old.get_index()
			parent.remove_child(old)
			old.free()
			parent.add_child(fresh)
			parent.move_child(fresh, at)
			return true
		RemixOp.Kind.ADD_ENEMY:
			var enemies := inst.get_node_or_null("Enemies")
			if enemies == null or not node is Node2D:
				push_error("RemixLibrary: ADD beside %s needs an Enemies group and a positioned target" % op.target)
				return false
			var added := _spawn(op)
			if added == null:
				return false
			_added[key] = int(_added.get(key, 0)) + 1
			added.name = "%sR%d" % [op.scene_kind, _added[key]]
			added.position = (node as Node2D).position + op.offset
			var target_facing: int = node.get("facing") if node.get("facing") != null else -1
			added.facing = op.facing if op.facing != 0 else target_facing
			# ADD-only spawns keep the variant's 0 Scrap (RM-5).
			added.data = op.data
			enemies.add_child(added)
			return true
	# SET
	if not RemixOp.settable(node, op.property):
		push_error("RemixLibrary: %s.%s is not whitelisted (%s)" % [op.target, op.property, ", ".join(RemixOp.class_names(node))])
		return false
	var v: Variant = op.value
	if op.property == &"data" and node is Enemy and v is EnemyData:
		var e := node as Enemy
		v = with_drop(v as EnemyData, e.data.scrap_drop if e.data else 0)
	var cur: Variant = node.get(op.property)
	if cur is Array and v is Array:
		# Keep the property's element type (a typed export rejects a plain Array).
		var arr: Array = (cur as Array).duplicate()
		arr.clear()
		arr.append_array(v as Array)
		v = arr
	node.set(op.property, v)
	return true


static func _spawn(op: RemixOp) -> Enemy:
	var scene := load(String(RemixOp.SCENES.get(op.scene_kind, ""))) as PackedScene if RemixOp.SCENES.has(op.scene_kind) else null
	if scene == null:
		push_error("RemixLibrary: unknown scene_kind '%s'" % op.scene_kind)
		return null
	return scene.instantiate() as Enemy


## A duplicate of `variant` that drops `drop` Scrap (R09.11). The file keeps
## scrap_drop 0 (RM-5) so an ADD never pays.
static func with_drop(variant: EnemyData, drop: int) -> EnemyData:
	if variant == null or variant.scrap_drop == drop:
		return variant
	var d := variant.duplicate() as EnemyData
	d.scrap_drop = drop
	return d


## "REMIX <room> ops=<n> active|off" for the F1 overlay.
static func debug_lines() -> PackedStringArray:
	var path := SceneRouter.current_room_path
	if path == "" or for_room(path) == null:
		return PackedStringArray()
	return PackedStringArray(["REMIX %s ops=%d %s" % [path.get_file().get_basename(), int(last_applied.get(path, 0)),
		"active" if _last_active.get(path, false) else "off"]])


static func _register_overlay() -> void:
	var c := Callable(RemixLibrary, "debug_lines")
	if not DebugOverlay.providers.has(c):
		DebugOverlay.providers.append(c)


static func clear_cache() -> void:
	last_applied = {}
	_last_active = {}
	_index = {}
	_index_dir = ""
	_added = {}
	force_active = false
	data_dir = DEFAULT_DIR
