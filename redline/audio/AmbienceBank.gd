class_name AmbienceBank
extends Resource
## Ambience beds and emitters (data/audio/ambience/beds.tres, SOUND_DIRECTION
## section 7). Bed id (PresentationIndex.BED_IDS) -> stream path String and a
## mix offset. Paths are Strings guarded by ResourceLoader.exists, so a build
## may leave a bed out; an empty or missing path plays silence (there is no
## synth ambience: silence is the honest placeholder).

## bed id (StringName) -> an OGG path, or "" (planned, not shipped).
@export var paths: Dictionary = {}
## bed id (StringName) -> player volume offset in dB (manifest mix_db).
@export var mix_db: Dictionary = {}

@export_group("Drip emitter")
## Random one-shots (AmbientEmitter) while one of these beds plays.
@export var drip_beds: Array[StringName] = []
@export_file("*.tres", "*.ogg") var drip_path: String = ""
@export var drip_mix_db: float = -18.0
## Seconds between drips (min, max).
@export var drip_interval: Vector2 = Vector2(4.0, 11.0)
## +/- dB and +/- pan per drip.
@export var drip_volume_jitter: float = 3.0
@export_range(0.0, 1.0) var drip_pan_jitter: float = 0.6


## The bed's path, or "" when unmapped or its file is missing.
func path_for(bed: StringName) -> String:
	var p := str(paths.get(bed, ""))
	return p if p != "" and ResourceLoader.exists(p) else ""


func volume_for(bed: StringName) -> float:
	return float(mix_db.get(bed, 0.0))


## ContentValidator resource protocol.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for bed: Variant in paths:
		var p := str(paths[bed])
		if p != "" and not ResourceLoader.exists(p):
			out.append("bed '%s': missing stream %s" % [bed, p])
	if drip_path != "" and not ResourceLoader.exists(drip_path):
		out.append("drip emitter: missing stream %s" % drip_path)
	if drip_interval.x <= 0.0 or drip_interval.y < drip_interval.x:
		out.append("drip emitter: bad interval %s" % drip_interval)
	return out
