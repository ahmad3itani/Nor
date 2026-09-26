class_name BuildInfo
extends RefCounted
## What kind of build this is (M9 D6): full or demo, web or desktop, its
## version label, and which rooms and features it allows. Everything that
## differs between the full game and the demo asks here, never OS feature
## tags directly, so tests can force either kind.
##
## stub: filled by T05 (DemoConfig data, the demo room list, the demo user
## dir). The stub is the full game: every room and feature allowed.

## Test seam: -1 = follow the build (--demo / feature tag), 0 = full, 1 = demo.
static var force_demo: int = -1
## Test seam: room path -> allowed (checked first by room_allowed).
static var force_allowed: Dictionary = {}


static func is_demo() -> bool:
	return force_demo == 1 if force_demo >= 0 else false


## The DemoConfig resource of a demo build (null in the full game).
static func demo() -> Resource:
	return null


static func kind() -> String:
	return "demo" if is_demo() else "full"


static func is_web() -> bool:
	return OS.has_feature("web")


## Web builds have no Quit (the browser tab owns the window).
static func can_quit() -> bool:
	return not is_web()


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


static func label() -> String:
	return version() + (" (debug)" if OS.is_debug_build() else "")


## Feature switches (&"ngplus", &"challenges", &"labs", &"relay_start",
## &"lab_cycle", ...): all on in the full game.
static func enabled(_feature: StringName) -> bool:
	return true


static func room_allowed(path: String) -> bool:
	return bool(force_allowed.get(path, true))


## Whether playtest recording defaults on in this build.
static func recording_default() -> bool:
	return true


## Appended to the title wordmark ("DEMO" in a demo build).
static func title_tag() -> String:
	return ""


## Read through the tree, not the Game identifier: Settings (the second
## autoload) compiles BuildInfo, and naming Game here would compile Game.gd
## (and preload its data) mid-cycle, leaving its resources untyped.
static func title_subtitle() -> String:
	var game := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	return str(game.get("onboarding").get("title_subtitle")) if game else ""


## The menu id slice_completed opens (the demo end card in a demo).
static func slice_card_id() -> StringName:
	return &"slice_end"


static func set_force_demo(v: int) -> void:
	force_demo = v


## Debug demos redirect saves, platform files and settings to user://demo/...
## (T05). Called first in Settings._ready; idempotent. Inert in the stub.
static func apply_demo_dirs() -> void:
	pass


static func clear_cache() -> void:
	pass
