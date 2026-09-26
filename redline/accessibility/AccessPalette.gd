class_name AccessPalette
extends Resource
## One colour set for state cues (bible §24 colour-blind-safe indicators, D4
## §7.3, D-161). Settings.colorblind_mode picks default / protan_deutan /
## tritan (data/accessibility/palettes/); Palette.color(key) reads it.
##
## Colour is never the only cue: the shape cues (scanner dash patterns, chase
## chevrons, lamp ring vs disc, hollow empty pips, elite notches) are always
## on. A palette only moves hues so the states that share a shape family
## (danger / warning / info) stay apart for the eyes it targets.
##
## Keys:
## - SEMANTIC keys: every palette defines all of them (AC-1).
## - ROLE keys: one consumer's authored colour (e.g. the Security scanner's
##   FULL red, 1/255 off the telegraph red). The default palette defines every
##   role with the exact old constant, so the default look is unchanged; the
##   other palettes may leave a role out and it falls back to its semantic key.

## Telegraphs, enemy shots, FULL beams / warnings (amber states) / info (cyan:
## gates, notes, HIGH beams) / injectors / Scrap / UI red / Anchors.
const SEMANTIC_KEYS: Array[StringName] = [&"danger", &"warning", &"info", &"heal", &"currency", &"accent", &"safe"]
## The state colours that must stay apart under each palette's own CVD
## simulation (AC-3).
const STATE_KEYS: Array[StringName] = [&"danger", &"warning", &"info"]
## role -> the semantic key it falls back to.
const ROLES := {
	&"scanner_full": &"danger",
	&"chase_warning": &"warning",
	&"chase_danger": &"danger",
	&"collector_warning": &"warning",
	&"ammo": &"currency",
	&"map_gate": &"info",
	&"map_note": &"info",
}
## Localization (D5): ids and simulation names, never shown.
const LOC_EXEMPT := ["id", "simulations"]

@export var id: StringName = &""
## The ColorVision modes this palette is built for (AC-3 checks the state
## keys under each); empty = typical colour vision (checked unsimulated).
@export var simulations: PackedStringArray = []
## key (StringName) -> Color.
@export var colors: Dictionary = {}
## Minimum pairwise OKLab distance of the STATE_KEYS under each simulation.
@export var min_state_distance: float = 0.10


## The colour for `key`: its own entry, else the role's semantic key, else
## magenta (a missing key is loud, and AC-1 reports it).
func resolve(key: StringName) -> Color:
	if colors.has(key):
		return colors[key]
	if ROLES.has(key) and colors.has(ROLES[key]):
		return colors[ROLES[key]]
	return Color.MAGENTA


## Every key this palette defines, for the contrast rule.
func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in colors:
		out.append(StringName(k))
	return out


## Single-file checks (ContentValidator resource protocol): every semantic key
## present and every value a colour; roles named here must be known roles.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for k in SEMANTIC_KEYS:
		if not colors.has(k):
			out.append("palette %s has no '%s' colour" % [id, k])
	for k in colors:
		if not (colors[k] is Color):
			out.append("palette %s: '%s' is not a colour" % [id, k])
		if not SEMANTIC_KEYS.has(StringName(k)) and not ROLES.has(StringName(k)):
			out.append("palette %s: unknown key '%s'" % [id, k])
	for s in simulations:
		if not ColorVision.MATRICES.has(StringName(s)):
			out.append("palette %s: unknown simulation '%s'" % [id, s])
	if min_state_distance <= 0.0:
		out.append("palette %s: min_state_distance must be positive" % id)
	return out
