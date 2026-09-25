class_name StoryPresets
extends Resource
## The Act I story presets in play order (design_world §7.6). apply() goes
## through Game.set_flag / Game.set_ability, so switches, NPC posts and map
## pins update live exactly as they do in play.

const PATH := "res://data/dev/story_presets.tres"

@export var presets: Array[StoryPreset] = []


static func all() -> Array[StoryPreset]:
	var list := load(PATH) as StoryPresets
	var out: Array[StoryPreset] = []
	if list != null:
		out.assign(list.presets)
	return out


static func by_id(id: String) -> StoryPreset:
	for p in all():
		if p.id == id:
			return p
	return null


## Applies every preset up to and including `id`, in order. An unknown id
## warns and changes nothing.
static func apply(id: String) -> void:
	var list := all()
	if not list.any(func(p: StoryPreset) -> bool: return p.id == id):
		push_warning("StoryPresets.apply: unknown preset '%s'" % id)
		return
	for p in list:
		for f in p.flags:
			Game.set_flag(f, true)
		for a in p.abilities:
			Game.set_ability(StringName(a), true)
		if p.id == id:
			return
