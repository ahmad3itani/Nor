extends Node
## The run director (M9 D2/D3): boss rematches, time trials, no-hit and
## movement-only runs, the Pulse Pit and The Null all run here, each inside
## one ProfileSandbox with one records store and one result card.
##
## stub: filled by T04. Every body is inert with its final signature; the
## shared-file hooks (PauseMenu, TitleMenu, MenuHost, Playtest, TestRunner)
## land once in T01. No class_name (an autoload's script must not declare one).

## Test seam (kept by T04): pretend a run is live.
var force_active: bool = false
## Test seam (kept by T04; T03's Core-row test sets it): -1 = no forced mode.
var force_reactor_mode: int = -1
## Test seam (kept by T04): pretend a run just ended (result card pending).
var force_finishing: bool = false
## CaptureTour sets it so the group-open notice never draws in a tour frame.
var quiet_notices: bool = false


func active() -> bool:
	return force_active


func forced_reactor_mode() -> int:
	return force_reactor_mode


## Whether any challenge is unlocked for this save data (title row gate).
func any_unlocked_for(_data: Dictionary) -> bool:
	return false


func current_id() -> String:
	return ""


func current_title() -> String:
	return ""


## True when the live run has stages (a Null descent).
func has_stages() -> bool:
	return false


func restart(_reason: StringName = &"reset") -> void:
	pass


func restart_run() -> void:
	pass


func quit() -> void:
	pass


func ghost_mode_label() -> String:
	return ""


func cycle_ghost_mode() -> void:
	pass


func open_from_title() -> void:
	pass


## True between a run's end and its result card (T04): pause stays shut.
func finishing() -> bool:
	return force_finishing


## TestRunner teardown. T04 also quits and restores any live sandbox.
func reset_for_tests() -> void:
	force_active = false
	force_reactor_mode = -1
	force_finishing = false
	quiet_notices = false
