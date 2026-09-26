class_name ColorVision
extends RefCounted
## Colour maths for the colour-blind checks (bible §24, D4 §7.3, D-161). Pure
## and static: AccessRules (AC-2, AC-3) and test_palette use it to prove each
## palette keeps its state colours apart for the eyes it is meant for. Nothing
## at runtime filters the screen with it: M9 has no daltonization shader
## (D-161), the palettes and the always-on shape cues do the work.

## Machado, Oliveira and Fernandes 2009, severity 1.0, applied in linear RGB.
const MATRICES := {
	&"protan": [
		Vector3(0.152286, 1.052583, -0.204868),
		Vector3(0.114503, 0.786281, 0.099216),
		Vector3(-0.003882, -0.048116, 1.051998)],
	&"deutan": [
		Vector3(0.367322, 0.860646, -0.227968),
		Vector3(0.280085, 0.672501, 0.047413),
		Vector3(-0.011820, 0.042940, 0.968881)],
	&"tritan": [
		Vector3(1.255528, -0.076749, -0.178779),
		Vector3(-0.078411, 0.930809, 0.147602),
		Vector3(0.004733, 0.691367, 0.303900)],
}


static func modes() -> Array[StringName]:
	return [&"protan", &"deutan", &"tritan"]


static func to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func to_srgb(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return 12.92 * v if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


## How `c` looks to a dichromat of `mode` (&"protan", &"deutan", &"tritan");
## any other mode returns `c` unchanged. Alpha is kept.
static func simulate(c: Color, mode: StringName) -> Color:
	if not MATRICES.has(mode):
		return c
	var m: Array = MATRICES[mode]
	var lin := Vector3(to_linear(c.r), to_linear(c.g), to_linear(c.b))
	return Color(to_srgb((m[0] as Vector3).dot(lin)), to_srgb((m[1] as Vector3).dot(lin)),
		to_srgb((m[2] as Vector3).dot(lin)), c.a)


## OKLab (Ottosson 2020) of an sRGB colour: x = L, y = a, z = b.
static func oklab(c: Color) -> Vector3:
	var r := to_linear(c.r)
	var g := to_linear(c.g)
	var b := to_linear(c.b)
	var l := _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	var m := _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	var s := _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


## Euclidean OKLab distance (about 0.02 is a just-noticeable difference).
static func oklab_distance(a: Color, b: Color) -> float:
	return oklab(a).distance_to(oklab(b))


## WCAG 2 relative luminance.
static func luminance(c: Color) -> float:
	return 0.2126 * to_linear(c.r) + 0.7152 * to_linear(c.g) + 0.0722 * to_linear(c.b)


## WCAG 2 contrast ratio (1..21), alpha ignored.
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _cbrt(v: float) -> float:
	return signf(v) * pow(absf(v), 1.0 / 3.0)
