extends Node
## Placeholder audio service. M1 has no sounds yet; this exists so later
## systems depend on one entry point (bible §28: readable, layered audio).


func _ready() -> void:
	apply_volume()


func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(Settings.master_volume))


## Intended API for M2+. Currently a no-op so callers can be written now.
func play_sfx(_id: StringName, _position: Vector2 = Vector2.INF) -> void:
	pass
