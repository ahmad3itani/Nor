class_name BuildProbe
extends RefCounted
## `--print-build-info` (Main.gd): prints one JSON line about the build and
## quits, so the build script can smoke-test an exported binary without a
## display or any network (M9 D6). T05 extends info().


static func info() -> Dictionary:
	return {"version": BuildInfo.version(), "kind": BuildInfo.kind()}


static func run(tree: SceneTree) -> void:
	print("BUILD_INFO " + JSON.stringify(info()))
	tree.quit(0)
