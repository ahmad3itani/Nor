class_name Vignette
extends Sprite2D
## The district vignette (assets/vfx/atmos/vignette.png, 4 alpha steps). It
## is the top child of the DistrictBackdrop layer (-20): above the planes,
## fog and shafts, below the world, so gameplay pixels are never darkened
## (vignette.json "under the playfield"). Nothing on a layer >= 0 carries
## it. Hidden under high contrast.

const PATH := "res://assets/vfx/atmos/vignette.png"
## The texture's own peak alpha (130/255): strength = peak darkness.
const PEAK := 130.0 / 255.0

var strength: float = 0.0


static func create(p_strength: float) -> Vignette:
	if p_strength <= 0.0 or not ResourceLoader.exists(PATH):
		return null
	var v := Vignette.new()
	v.name = "Vignette"
	v.texture = load(PATH) as Texture2D
	v.centered = false
	v.strength = p_strength
	v.self_modulate = Color(1, 1, 1, clampf(p_strength / PEAK, 0.0, 1.0))
	v.refresh()
	return v


## Follows the high-contrast setting.
func refresh() -> void:
	visible = not Settings.high_contrast
