class_name FogBand
extends ParallaxPlane
## A drifting fog band (assets/vfx/atmos/fog_band_a/b.png, x-tileable, 4
## alpha steps) tinted by the district fog colour. The drift runs at the
## ambient motion level: full speed at Full, half at Reduced, frozen at Off
## (Motion, F7). Tint and alpha live in self_modulate so the background dim
## (DistrictBackdrop.apply_dim) can own modulate.

const PATH_A := "res://assets/vfx/atmos/fog_band_a.png"
const PATH_B := "res://assets/vfx/atmos/fog_band_b.png"

## px/s, sign = wind direction.
var drift_speed: float = 0.0


## `which` 0 = band A (between far and mid), 1 = band B (near the world).
static func create(which: int, color: Color, alpha: float, speed: float, anchor: float) -> FogBand:
	var path := PATH_A if which == 0 else PATH_B
	if alpha <= 0.0 or not ResourceLoader.exists(path):
		return null
	var band := FogBand.new()
	band.name = "FogA" if which == 0 else "FogB"
	band.setup(load(path) as Texture2D, null, Vector2(0.2, 0.05) if which == 0 else Vector2(0.6, 0.3), anchor, false)
	band.drift_speed = speed
	band.self_modulate = Color(color, alpha)
	return band


## Drift speed factor for the ambient motion level (1, 0.5, 0).
static func speed_scale() -> float:
	match Motion.level():
		Motion.FULL:
			return 1.0
		Motion.REDUCED:
			return 0.5
	return 0.0


func _process(delta: float) -> void:
	drift = fposmod(drift - drift_speed * speed_scale() * delta, cycle())
