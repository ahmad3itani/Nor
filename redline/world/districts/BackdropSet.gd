class_name BackdropSet
extends Resource
## A backdrop kind's painted layer stack and atmosphere (ART_DIRECTION
## section 4): planes back to front, two fog bands, light shafts, the
## background-only grade (F11), the vignette, ambient particles and life.
## One file per kind in data/presentation/backdrops/<kind>.tres, picked by
## PresentationIndex (RoomPresentation.backdrop_kind). Visual only: nothing
## here collides or reaches gameplay.

const DIR := "res://data/presentation/backdrops"
## Rows of assets/vfx/ambient_particles (the spec's names).
const PARTICLE_KINDS: Array[StringName] = [&"mote", &"spore", &"ash", &"drip"]
## Life kinds AmbientLife knows.
const LIFE_KINDS: Array[StringName] = [&"moth", &"rat", &"gull", &"eel", &"drip", &"steam", &"train"]

## Back to front. A plane with is_foreground is drawn in front of the world.
@export var planes: Array[PlaneSpec] = []

@export_group("Fog")
## Fog tint; the band textures carry their own 4 alpha steps (peak ~31 %).
@export var fog_color: Color = Color("2b3d38")
## Fog band A (between far and mid) modulate alpha; 0 = no band.
@export_range(0.0, 1.0) var fog_alpha_a: float = 0.0
## Fog band B (between near and the world) modulate alpha; 0 = no band.
@export_range(0.0, 1.0) var fog_alpha_b: float = 0.0
## Drift in px/s; the sign is the wind direction.
@export var fog_drift_a: float = -3.0
@export var fog_drift_b: float = -6.0
## Band bottoms relative to the view bottom at the resting camera.
@export var fog_anchor_a: float = -110.0
@export var fog_anchor_b: float = -84.0
## Fog band A goes in front of planes[0 .. index-1] (-1 = before the first
## plane that moves at 0.2 or more: between far and mid).
@export var fog_a_index: int = -1

@export_group("Light")
## Background modulate (assets/vfx/atmos/district_grades.json bg_modulate).
## Backdrop layer only, never the world, characters or HUD (F11).
@export var grade: Color = Color.WHITE
## Peak darkness of the vignette (0 = none). Skipped under high contrast.
@export_range(0.0, 1.0) var vignette_alpha: float = 0.0
## Light shafts placed from the room seed (0 = none).
@export_range(0, 4) var shaft_count: int = 0
@export var shaft_color: Color = Color("9eccb8")
## Sky-only lightning tint (roofs, title).
@export var lightning: bool = false
## Seconds between flashes (min, max).
@export var lightning_period: Vector2 = Vector2(8, 15)

@export_group("Life")
## ambient_particles row (mote/spore/ash/drip; "dust" reads as mote).
@export var ambient_particle: StringName = &""
@export_range(0, 24) var particle_count: int = 0
@export var particle_color: Color = Color("9eccb8")
## LIFE_KINDS this kind hosts.
@export var life: Array[StringName] = []
## Seconds between far-plane train passes (min, max).
@export var train_period: Vector2 = Vector2(40, 70)
## Rain drops instead of the theme's (-1 = the theme's, 0 = none).
@export var rain_override: int = -1


## The set for `kind`, or null (no file: the procedural backdrop stays).
static func for_kind(kind: StringName) -> BackdropSet:
	if kind == &"":
		return null
	var path := "%s/%s.tres" % [DIR, kind]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as BackdropSet


## The ambient_particles row this set uses ("dust" maps to mote).
func particle_row() -> StringName:
	if ambient_particle == &"dust":
		return &"mote"
	return ambient_particle


func background_planes() -> Array[PlaneSpec]:
	var out: Array[PlaneSpec] = []
	for p in planes:
		if p and not p.is_foreground:
			out.append(p)
	return out


func foreground_planes() -> Array[PlaneSpec]:
	var out: Array[PlaneSpec] = []
	for p in planes:
		if p and p.is_foreground:
			out.append(p)
	return out


## ContentValidator resource protocol.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for i in planes.size():
		var p := planes[i]
		if p == null:
			out.append("plane %d is empty" % i)
			continue
		for path in p.paths():
			if path == "" or not ResourceLoader.exists(path):
				out.append("plane %d: missing texture '%s'" % [i, path])
	var row := particle_row()
	if row != &"" and not PARTICLE_KINDS.has(row):
		out.append("unknown ambient particle '%s'" % ambient_particle)
	for l in life:
		if not LIFE_KINDS.has(l):
			out.append("unknown life kind '%s'" % l)
	return out
