class_name CoreAura
extends Node2D
## Rook's Core while he is in Flow (inside a Flow Zone, ReactorCore.in_flow()):
## three 1 px Pulse motes orbit the chest seam and the seam brightens. At
## critical charge a slow, seam-coloured ember drips from it. JuiceDirector
## adds it on entering Flow and frees it on leaving (it exists only then).
##
## Never afterimages: those keep meaning dodge/dash i-frames (T06 spec).
## Flash reduction: the seam holds one brightness and the drip becomes a
## static ember. Visual only: a plain Node2D, no collision.
##
## Hook: a visual with a `set_seam_boost(amount: float)` method (the sprite
## mask overlay) is brightened through it instead of the drawn seam glow.

const SEAM := Vector2(0, -24)
const ORBIT_RADIUS := Vector2(7, 4)
const ORBIT_SPEED := 2.4
const ORBIT_MOTES := 3
const DRIP_INTERVAL := 0.55
const DRIP_TIME := 0.8
const DRIP_FALL := 14.0

var player: Player
var _t: float = 0.0
var _drip_timer: float = 0.0
## Each: seconds since the ember left the seam.
var _drips: Array[float] = []


static func attach(p: Player) -> CoreAura:
	var a := CoreAura.new()
	a.name = "CoreAura"
	a.player = p
	a.z_index = 1
	p.add_child(a)
	a._boost(1.0)
	return a


func _exit_tree() -> void:
	_boost(0.0)


func _boost(amount: float) -> void:
	if is_instance_valid(player) and player.visual and player.visual.has_method(&"set_seam_boost"):
		player.visual.call(&"set_seam_boost", amount)


## The visual brightens its own seam mask (set_seam_boost), so no drawn glow.
func _visual_overlay() -> bool:
	if not (is_instance_valid(player) and player.visual and player.visual.has_method(&"set_seam_boost")):
		return false
	if player.visual.has_method(&"has_seam_overlay"):
		return bool(player.visual.call(&"has_seam_overlay"))
	return true


func critical() -> bool:
	return is_instance_valid(player) and player.reactor != null and player.reactor.config != null \
		and player.reactor.is_critical()


func _process(delta: float) -> void:
	_t += delta
	for i in _drips.size():
		_drips[i] += delta
	_drips = _drips.filter(func(a: float) -> bool: return a < DRIP_TIME)
	if critical() and not Settings.flash_reduction:
		_drip_timer -= delta
		if _drip_timer <= 0.0:
			_drip_timer = DRIP_INTERVAL
			_drips.append(0.0)
	queue_redraw()


func _draw() -> void:
	var accent := Palette.color(&"accent")
	var reduced := Settings.flash_reduction
	if not _visual_overlay():
		var glow := 0.4 if reduced else 0.3 + 0.15 * sin(_t * 5.0)
		draw_rect(Rect2(SEAM + Vector2(-1, -3), Vector2(2, 6)), Color(accent, glow))
	for i in ORBIT_MOTES:
		var a := _t * ORBIT_SPEED + i * TAU / ORBIT_MOTES
		var p := (SEAM + Vector2(cos(a) * ORBIT_RADIUS.x, sin(a) * ORBIT_RADIUS.y)).round()
		# Motes behind Rook (upper half of the orbit) dim a little: depth.
		draw_rect(Rect2(p, Vector2.ONE), Color(accent, 0.55 if sin(a) < 0.0 else 0.9))
	if critical():
		if reduced:
			draw_rect(Rect2(SEAM + Vector2(0, 4), Vector2.ONE), Color(accent, 0.8))
		else:
			for age in _drips:
				var k := age / DRIP_TIME
				draw_rect(Rect2((SEAM + Vector2(0, 3 + DRIP_FALL * k * k)).round(), Vector2.ONE), Color(accent, 1.0 - k))
