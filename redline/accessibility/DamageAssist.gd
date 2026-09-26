class_name DamageAssist
extends RefCounted
## Damage assist (bible §24, D4 §8.2, D-152): scales the pips Rook loses.
## Health is whole pips and most attacks cost 1, so a plain multiply would
## round away to nothing or back to 1. A carry keeps the remainder instead:
## at 0.5 a run of 1-pip hits costs 0, 1, 0, 1; at 0.25 it costs 0, 0, 0, 1.
## A hit that rounds to 0 still knocks back, grants i-frames and emits
## player_damaged(0, ...), so readability, style breaks and the no-hit rule
## are unchanged (a hit is a hit). Separate from the Core mode, so a Normal
## Core player can take it and an Assist Core player can refuse it.

## Float noise guard: 0.5 + 0.5 must count as one whole pip.
const EPSILON := 0.0001


## Returns [pips_to_take: int, new_carry: float]; `carry` (0..1) is the part
## of a pip taken but not yet removed.
static func scale(amount: int, carry: float, factor: float) -> Array:
	if amount <= 0:
		return [maxi(amount, 0), carry]
	if factor >= 1.0:
		return [amount, carry]
	var total := float(amount) * maxf(factor, 0.0) + carry
	var pips := int(floor(total + EPSILON))
	return [pips, clampf(total - float(pips), 0.0, 1.0 - EPSILON)]


## The scale for a hit at a Settings.damage_assist index: 1.0 when Off, for
## an exempt source (burnout: the Core setting covers it) and, in a
## bosses-only mode, for anything but a boss's own hit.
static func factor_for(index: int, cfg: AccessibilityConfig, source: String, from_boss: bool) -> float:
	if cfg == null or index <= 0 or index >= cfg.damage_scale.size():
		return 1.0
	for s in cfg.damage_exempt_sources:
		if source == s or source.begins_with(s + "/"):
			return 1.0
	if index < cfg.damage_bosses_only.size() and cfg.damage_bosses_only[index] and not from_boss:
		return 1.0
	return cfg.damage_scale[index]
