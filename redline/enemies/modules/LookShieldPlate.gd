class_name LookShieldPlate
extends LookModule
## The shield plate on the facing side, shown while the brain's guard is up.

@export var color: Color = Color("7fb6d9")

## shield_sheet's plate, relative to the sheet origin (facing right): the
## outer outline column and the slab's top and bottom rows (bottom exclusive).
const SPRITE_RIM_X := 15.0
const SPRITE_RIM_TOP := -36.0
const SPRITE_RIM_BOTTOM := -8.0


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var guard := b.brain().guard
	if guard == null or not guard.guard_up(b):
		return
	var e := b.enemy
	var h := e.data.body_size.y
	var x := e.data.body_size.x * 0.5 if e.facing > 0 else -e.data.body_size.x * 0.5 - 4.0
	if sprite_mode(canvas):
		# Sprite: the sheet draws a plain steel slab; the guard-up cue stays a
		# code rim in guard blue on the slab's outer outline column, measured
		# from shield_sheet (idle/move/windup rows, origin (24, 46)), mirrored
		# by facing (a flipped pixel column c lands on [-c-1, -c)).
		var outer := SPRITE_RIM_X if e.facing > 0 else -SPRITE_RIM_X - 1.0
		canvas.draw_rect(Rect2(outer, SPRITE_RIM_TOP, 1.0, SPRITE_RIM_BOTTOM - SPRITE_RIM_TOP), color)
		return
	canvas.draw_rect(Rect2(x, -h + 2.0, 4.0, h - 4.0), color)
