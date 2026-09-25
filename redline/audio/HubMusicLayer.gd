class_name HubMusicLayer
extends Resource
## One step of the Relay theme growing with the settlement (bible §13, §28):
## while `condition` holds (Game.check_condition grammar), the hub mix plays
## `layer` at `volume`. Data, so a new act adds a line instead of code (D-125).

@export var condition: String = ""
@export var layer: StringName = &""
@export_range(0.0, 1.0) var volume: float = 0.3


func content_flags() -> Dictionary:
	return {"conditions": [condition]}


func content_check() -> PackedStringArray:
	var out := PackedStringArray()
	if not ContentValidator.is_valid_condition(condition):
		out.append("hub music layer condition '%s' is not valid" % condition)
	if not MusicDirector.LAYERS.has(layer):
		out.append("hub music layer '%s' is not a music stem" % layer)
	return out
