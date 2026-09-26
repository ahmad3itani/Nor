@tool
class_name ChallengeTerminal
extends Interactable
## The Relay's training rig (M9 D2 §6.1, T08; D-169): a lore-free placeholder
## entry to the Challenges menu, placed by tools/roomgen/lowlight.py. When
## Bramm (bible §13, the Trainer) exists in a later act he takes over this
## entry and the terminal is removed.
##
## Three looks, decided at runtime (R08.12), never by the scene:
## - rig closed (before the Act I close and outside NG+): not drawn, no
##   prompt, not interactable, so a first playthrough never sees it next to
##   Mara and Vell;
## - rig open, nothing unlocked yet: drawn dark, still no prompt;
## - something unlocked: lit, prompt "Training rig", opens the Challenges
##   list with this room's "challenges" spawn as the return point.

## The prompt is the literal in prompt_text() (Loc); nothing else is shown.
const LOC_FIELDS := {}
const LOC_EXEMPT := ["prompt_verb"]
## Where a run started here brings Rook back (a SpawnMarker in this room).
const RETURN_ENTRY := &"challenges"

const FRAME := Color("2a2530")
const SCREEN_DARK := Color("141218")
const SCREEN_LIT := Color("59e0e8")
const TRIM := Color("4a4458")

var _open: bool = false
var _lit: bool = false


func _ready() -> void:
	prompt_verb = "Training rig"
	size = Vector2(24, 32)
	super._ready()
	if Engine.is_editor_hint():
		return
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.game_state_reset.connect(refresh)
	refresh()


## Re-reads the rig state (on load, on a state reset, on every flag change:
## the Act I close can happen with Rook standing in the Relay).
func refresh() -> void:
	_open = ChallengeLibrary.rig_open()
	_lit = _open and ChallengeLibrary.any_unlocked()
	visible = _open
	# Deferred: flag changes arrive inside physics callbacks (a pickup, a
	# trigger), where an Area2D may not change its monitorable state.
	set_deferred("monitorable", _open)
	queue_redraw()


func is_lit() -> bool:
	return _lit


func _on_flag_changed(_id: String, _value: Variant) -> void:
	refresh()


func can_interact(_player: Player) -> bool:
	return not Engine.is_editor_hint() and _open and _lit


func prompt_text() -> String:
	return Loc.t("Training rig")


func interact(_player: Player) -> void:
	if not can_interact(_player):
		return
	MenuHost.context = {"room": SceneRouter.current_room_path, "entry": RETURN_ENTRY}
	EventBus.menu_requested.emit(&"challenges")


## Placeholder art (D-026): a console on the floor, its screen lit once a
## challenge is open. The lit screen also carries a bright border, so the
## state reads without colour.
func _draw() -> void:
	var lit := _lit or Engine.is_editor_hint()
	draw_rect(Rect2(-10, -30, 20, 30), FRAME)
	draw_rect(Rect2(-8, -27, 16, 11), SCREEN_LIT if lit else SCREEN_DARK)
	if lit:
		draw_rect(Rect2(-8, -27, 16, 11), Color.WHITE, false, 1.0)
		draw_line(Vector2(-5, -21), Vector2(5, -21), Color("0d3b40"), 1.0)
	draw_rect(Rect2(-6, -12, 12, 3), TRIM)
	draw_rect(Rect2(-12, -2, 24, 2), TRIM)
