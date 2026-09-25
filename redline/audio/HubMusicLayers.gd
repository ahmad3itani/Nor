class_name HubMusicLayers
extends Resource
## The Relay theme's growth table (data/audio/hub_music.tres, D-125):
## MusicDirector applies every entry whose condition holds on top of the HUB
## base mix. Later entries win when two name the same stem.

@export var layers: Array[HubMusicLayer] = []


## Stem -> volume for the entries that pass right now.
func active_mix() -> Dictionary:
	var mix := {}
	for l in layers:
		if l != null and Game.check_condition(l.condition):
			mix[l.layer] = l.volume
	return mix


func content_flags() -> Dictionary:
	var conditions: Array = []
	for l in layers:
		if l != null:
			conditions.append_array(l.content_flags().get("conditions", []))
	return {"conditions": conditions}


func content_check() -> PackedStringArray:
	var out := PackedStringArray()
	for i in layers.size():
		if layers[i] == null:
			out.append("hub music entry %d is empty" % i)
			continue
		out.append_array(layers[i].content_check())
	return out
