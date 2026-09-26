class_name RemixLibrary
extends RefCounted
## NG+ room remixes (M9 D3, D-153): data ops (enemy swaps, hazard changes)
## applied to a room instance between instantiate() and add_child() in
## SceneRouter.goto_room. 0 ops unless a remix is active.
##
## stub: filled by T09.

## Room path -> ops applied on its last load (tests and the dev page read it).
static var last_applied: Dictionary = {}


## Applies the active remix ops for `path` to `inst`; returns how many ran.
static func apply(_inst: Node, _path: String) -> int:
	return 0


static func clear_cache() -> void:
	last_applied = {}
