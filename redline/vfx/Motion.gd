class_name Motion
extends RefCounted
## Ambient motion level (Settings.ambient_motion, ART_DIRECTION F7): how
## much of the world's ambient life moves. It governs ambient particles,
## critters, fog drift, cloth and parallax bob only, never gameplay VFX,
## hit feedback or telegraphs (those follow flash reduction instead).
##
## Safe in the editor and in tools: without the Settings autoload every
## query reads the Full defaults (the Palette.mode() pattern), so @tool
## decoration scripts can call it.

const FULL := 0
const REDUCED := 1
const OFF := 2
## Particle/critter count scale per level when no AccessibilityConfig is
## reachable (data/accessibility/accessibility_config.tres holds the tuning).
const DEFAULT_COUNT_SCALES: Array[float] = [1.0, 0.5, 0.0]


## 0 Full, 1 Reduced, 2 Off.
static func level() -> int:
	var s := _settings()
	if s == null:
		return FULL
	return clampi(int(s.get("ambient_motion")), FULL, OFF)


## Multiplier for ambient particle and critter counts (1, 0.5, 0 by default).
static func count_scale() -> float:
	var lv := level()
	var s := _settings()
	if s and s.has_method("config"):
		var cfg: AccessibilityConfig = s.call("config")
		if cfg and cfg.ambient_motion_scale.size() == 3:
			return cfg.ambient_motion_scale[lv]
	return DEFAULT_COUNT_SCALES[lv]


## False at Off: ambient things hold still (static sprites only).
static func animate_ambient() -> bool:
	return level() != OFF


## Cloth, banners and cable sway move only at Full (Reduced freezes them).
static func cloth() -> bool:
	return level() == FULL


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var s: Node = tree.root.get_node_or_null("Settings")
	if s == null or not ("ambient_motion" in s):
		return null
	return s
