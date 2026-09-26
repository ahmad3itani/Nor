class_name DemoDevActions
extends RefCounted
## Dev console helpers for the demo (M9 D6 §6.3). Debug builds only (the dev
## console never opens in a release export).


## A demo session in any build: forces the demo kind (saves, platform files,
## settings and playtests move under user://demo/, BuildInfo.apply_demo_dirs)
## and adds a DemoGate so border exits get their barriers from the next room
## load. Off puts every path back and takes the current room's barriers down.
## A build that is itself a demo has no session to toggle: forcing one would
## turn on the user://demo redirect inside a demo export's own user dir.
static func set_demo_session(on: bool) -> void:
	if build_is_demo():
		return
	BuildInfo.set_force_demo(1 if on else -1)
	settle_gate(Engine.get_main_loop() as SceneTree)


## After the demo kind changed: a demo keeps (or gains) its gate and border
## barriers; the full game drops them. Never strips a demo that is still one
## once the forced session is gone (a debug --demo run, review T05).
static func settle_gate(tree: SceneTree) -> void:
	if BuildInfo.is_demo():
		DemoGate.ensure(tree)
	else:
		DemoGate.remove_all(tree)


static func demo_session_on() -> bool:
	return BuildInfo.force_demo == 1


## The build itself is a demo (a demo export, debug --demo): no forced session.
static func build_is_demo() -> bool:
	return BuildInfo.force_demo < 0 and BuildInfo.is_demo()


## Opens the end card as the player would see it (the console closes first:
## MenuHost refuses while another screen is open).
static func show_demo_end() -> void:
	EventBus.menu_requested.emit(&"demo_end")


## [room, entry] next to the demo's border (EscapeTunnel, facing the Relay
## gap). A format path: the scanner skips it, the room is checked at use.
static func demo_border_target() -> Array:
	return ["res://world/rooms/%s/%s.tscn" % ["undercity", "EscapeTunnel"], &"from_relay"]


static func teleport_to_border() -> void:
	var t := demo_border_target()
	if ResourceLoader.exists(t[0]):
		SceneRouter.transition_to(t[0], t[1])


## One line per BuildInfo field, for the page and the log.
static func summary() -> String:
	var i := BuildInfo.info()
	return "%s · %s · user dir %s (expected '%s')%s · demo '%s'" % [i["label"], i["kind"], i["user_dir"],
		i["user_dir_expected"], " · redirected to user://demo" if i["redirected"] else "", i["demo_id"]]


static func print_build_info() -> String:
	var line := "BUILD_INFO " + JSON.stringify(BuildProbe.info())
	print(line)
	DisplayServer.clipboard_set(line)
	return line
