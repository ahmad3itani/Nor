class_name PlaytestVariant
extends Resource
## One arm of a playtest experiment (bible §36 M4: "change design before
## scaling"). Each variant answers an open design question from DECISIONS by
## overriding data on a *copy* of the shipped resource, so the default game is
## never modified and every session records which arm it played.

@export var id: String = ""
@export var label: String = ""
## The open decision this arm tests, e.g. "D-036 slide-jump strength".
@export var question: String = ""
## PlayerMovementConfig property -> value.
@export var movement_overrides: Dictionary = {}


func apply_to_player(player: Player) -> void:
	if movement_overrides.is_empty() or player.config == null:
		return
	var cfg := player.config.duplicate() as PlayerMovementConfig
	for key: String in movement_overrides:
		cfg.set(key, movement_overrides[key])
	player.apply_config(cfg)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("variant without id")
	var probe := PlayerMovementConfig.new()
	for key: String in movement_overrides:
		if not key in probe:
			errors.append("variant %s overrides unknown movement property %s" % [id, key])
	return errors
