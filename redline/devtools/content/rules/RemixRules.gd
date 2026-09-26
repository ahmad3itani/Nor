class_name RemixRules
extends RefCounted
## NG+ remix rules (M9 D3 §2.5, D-154/D-155), a ContentValidator rule module
## over data/remix/*.tres checked against the base room scenes. RoomRemix.
## validate() covers each file alone; these are the cross-file rules:
##   RM-1 the file name equals the room basename and the room loads
##   RM-2 every op target resolves in the base room (stale names are errors)
##   RM-3 SET properties are whitelisted by class (RemixOp.SET_WHITELIST);
##        ADD/SWAP/REMOVE act on enemies only
##   RM-4 ADD offsets land inside the room bounds
##   RM-5 remix EnemyData files drop no Scrap (a SET/SWAP replacement gets
##        the replaced enemy's drop at runtime, R09.11; an ADD pays nothing)
##   RM-6 boss variants stay readable: attack startup >= min_telegraph, the
##        phase-2 telegraph scale >= TELEGRAPH_FLOOR, the Collector's
##        sag_hold >= SAG_HOLD_FLOOR
##   RM-7 no op under a WorldStateSwitch (switches are visual, D-123)
##   RM-8 active_when is a valid, non-empty condition

## Enemy._physics_process floors telegraph_scale here (D-156).
const TELEGRAPH_FLOOR := 0.6
## The Collector's low window (D-064, D3 D-156): never under 0.6 s.
const SAG_HOLD_FLOOR := 0.6
## Folders whose *_remix.tres EnemyData files RM-5 scans.
const REMIX_DATA_DIRS: PackedStringArray = ["res://data/enemies"]


static func run(v: ContentValidator) -> void:
	for path in RemixLibrary.all_paths():
		var r := load(path) as RoomRemix
		if r == null:
			v.errors.append("[RM-1] %s is not a RoomRemix" % path.get_file())
			continue
		v.errors.append_array(check(r, path))
	for dir in REMIX_DATA_DIRS:
		for path in DataDir.list(dir):
			if not path.get_file().get_basename().ends_with("_remix"):
				continue
			var d := load(path) as EnemyData
			if d != null and d.scrap_drop != 0:
				v.errors.append("[RM-5] %s: a remix EnemyData must drop 0 Scrap (has %d)" % [path.get_file(), d.scrap_drop])


## Every cross-file finding for one remix (tests pass fixtures).
static func check(r: RoomRemix, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var tag := path.get_file()
	if r.active_when == "" or not ContentValidator.is_valid_condition(r.active_when):
		out.append("[RM-8] %s: active_when '%s' is not a valid condition" % [tag, r.active_when])
	if path.get_file().get_basename() != r.room.get_file().get_basename():
		out.append("[RM-1] %s: the file name must equal the room basename (%s)" % [tag, r.room.get_file()])
	var packed := load(r.room) as PackedScene if r.room != "" and ResourceLoader.exists(r.room) else null
	var room := packed.instantiate() if packed != null else null
	if not room is Room:
		out.append("[RM-1] %s: room %s does not load as a Room" % [tag, r.room])
		if room != null:
			room.free()
		return out
	for i in r.ops.size():
		var op := r.ops[i]
		if op != null:
			out.append_array(_check_op(op, room as Room, "%s op %d (%s)" % [tag, i + 1, op.describe()]))
	room.free()
	return out


static func _check_op(op: RemixOp, room: Room, where: String) -> PackedStringArray:
	var out := PackedStringArray()
	var node := room.get_node_or_null(op.target)
	if node == null:
		out.append("[RM-2] %s: no node '%s' in the base room (renamed by a generator?)" % [where, op.target])
		return out
	var up := node.get_parent()
	while up != null and up != room:
		if up is WorldStateSwitch:
			out.append("[RM-7] %s: the target sits under WorldStateSwitch %s" % [where, up.name])
			break
		up = up.get_parent()
	match op.kind:
		RemixOp.Kind.REMOVE_ENEMY, RemixOp.Kind.SWAP_ENEMY:
			if not node is Enemy:
				out.append("[RM-3] %s: only enemies can be removed or swapped (%s)" % [where, ", ".join(RemixOp.class_names(node))])
		RemixOp.Kind.ADD_ENEMY:
			if not node is Node2D:
				out.append("[RM-3] %s: an ADD needs a positioned node to stand beside" % where)
			else:
				var at := _pos_in(room, node as Node2D) + op.offset
				if not room.bounds.has_point(at):
					out.append("[RM-4] %s: the added enemy lands at %s, outside the bounds %s" % [where, at, room.bounds])
		RemixOp.Kind.SET:
			if not RemixOp.settable(node, op.property):
				out.append("[RM-3] %s: %s is not whitelisted on %s" % [where, op.property, ", ".join(RemixOp.class_names(node))])
	if op.kind in [RemixOp.Kind.ADD_ENEMY, RemixOp.Kind.SWAP_ENEMY] and op.data != null and op.data.scrap_drop != 0:
		out.append("[RM-5] %s: %s drops %d Scrap (remix data drops 0)" % [where, op.data.resource_path.get_file(), op.data.scrap_drop])
	var variant := op.value as EnemyData if op.kind == RemixOp.Kind.SET and op.property == &"data" else null
	if variant == null and op.kind != RemixOp.Kind.SET:
		variant = op.data
	if variant != null:
		if variant.resource_path.get_file().get_basename().ends_with("_remix") and variant.scrap_drop != 0:
			out.append("[RM-5] %s: %s drops %d Scrap (remix data drops 0)" % [where, variant.resource_path.get_file(), variant.scrap_drop])
		if variant.boss:
			for a in variant.attacks:
				if a != null and a.startup < variant.min_telegraph:
					out.append("[RM-6] %s: boss attack %s telegraphs %.2f s, under min_telegraph %.2f" % [where, a.id, a.startup, variant.min_telegraph])
	if op.kind == RemixOp.Kind.SET:
		if op.property == &"phase2_telegraph_scale" and float(op.value) < TELEGRAPH_FLOOR:
			out.append("[RM-6] %s: phase2_telegraph_scale %.2f is under the %.2f floor" % [where, float(op.value), TELEGRAPH_FLOOR])
		if op.property == &"sag_hold" and float(op.value) < SAG_HOLD_FLOOR:
			out.append("[RM-6] %s: the Collector's sag_hold %.2f is under %.2f s" % [where, float(op.value), SAG_HOLD_FLOOR])
	return out


static func _pos_in(room: Node, n: Node2D) -> Vector2:
	var p := Vector2.ZERO
	var cur: Node = n
	while cur != null and cur != room:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p


## The dev report section: one line per remix (ops and intent).
static func report(_v: ContentValidator) -> String:
	var md := PackedStringArray(["## NG+ remix", ""])
	for path in RemixLibrary.all_paths():
		var r := load(path) as RoomRemix
		if r != null:
			md.append("- %s: %d ops (%s). %s" % [r.room.get_file().get_basename(), r.ops.size(), r.active_when, r.intent])
	return "\n".join(md)
