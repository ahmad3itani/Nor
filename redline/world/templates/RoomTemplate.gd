@tool
class_name RoomTemplate
extends Node2D
## Base for reusable room pieces (bible §36 M6 "room templates"). A template
## generates ordinary nodes (GrayboxBlocks, exits, spawns...) from a few
## exported numbers. In the editor the generated children are *baked* into
## the scene (owned by it), so maps, validators, heatmaps and the game see
## plain nodes; change a number and the piece rebuilds. Code (tests, room
## scripts) calls build() directly.

const METRICS_PATH := "res://data/level/traversal_default.tres"
const GENERATED_META := &"template_generated"


func _ready() -> void:
	# Saved without baked children (e.g. written by a script): build now.
	if not has_generated():
		build()


func has_generated() -> bool:
	for c in get_children():
		if c.has_meta(GENERATED_META) or c.owner != null:
			return true
	return false


## Tools that read room scenes without adding them to the tree (map index,
## validators, heatmaps) call this so templates count like baked geometry.
static func expand_all(root: Node) -> void:
	for n in root.find_children("*", "RoomTemplate", true, false):
		if not (n as RoomTemplate).has_generated():
			(n as RoomTemplate).build()


## Clears the generated children and makes them again.
func build() -> void:
	for c in get_children():
		if c.has_meta(GENERATED_META):
			remove_child(c)
			c.queue_free()
	_generate()
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root:
		for c in get_children():
			_own(c, get_tree().edited_scene_root)
	update_configuration_warnings()


func _generate() -> void:
	pass


func metrics() -> TraversalMetrics:
	return load(METRICS_PATH) as TraversalMetrics


func add_block(rect: Rect2, one_way := false, block_name := "") -> GrayboxBlock:
	var b := GrayboxBlock.new()
	b.position = rect.position
	b.size = rect.size
	b.one_way = one_way
	b.name = block_name if block_name != "" else "Block%d" % get_child_count()
	return _add(b) as GrayboxBlock


func _add(n: Node) -> Node:
	n.set_meta(GENERATED_META, true)
	add_child(n)
	return n


func _rebuild_later() -> void:
	if is_inside_tree():
		build.call_deferred()


static func _own(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(c, root)
