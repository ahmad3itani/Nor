class_name Palette
extends RefCounted
## Runtime access to the colour-blind palettes (bible §24, D4 §7.3, D-161).
## Every state colour that used to be a per-file constant (telegraphs, scanner
## modes, chase meter, Collector lamp, HUD pips, map icons, the UI accent) is
## read through Palette.color(key), so Settings.colorblind_mode swaps them all
## at once. The default palette holds the old constants exactly, so with the
## setting off nothing on screen changes.
##
## Safe in the editor and in tools: without the Settings autoload it reads the
## default palette (ScannerBeam and ChaseDirector are @tool scripts).

const PATHS: PackedStringArray = [
	"res://data/accessibility/palettes/default.tres",
	"res://data/accessibility/palettes/protan_deutan.tres",
	"res://data/accessibility/palettes/tritan.tres",
]

## mode index -> AccessPalette (loaded once).
static var _palettes: Dictionary = {}
## key -> Color for _resolved_mode (the per-frame draw path).
static var _resolved: Dictionary = {}
static var _resolved_mode: int = -1
static var _listening: bool = false


## The colour for a semantic or role key (AccessPalette) in the palette the
## player chose.
static func color(key: StringName) -> Color:
	var m := mode()
	if m != _resolved_mode:
		_resolved.clear()
		_resolved_mode = m
		_listen()
	if not _resolved.has(key):
		_resolved[key] = palette(m).resolve(key)
	return _resolved[key]


## Settings.colorblind_mode (0 default, 1 protan/deutan, 2 tritan); 0 when
## Settings is not running (editor, tools).
static func mode() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	if s == null:
		return 0
	return clampi(int(s.get("colorblind_mode")), 0, PATHS.size() - 1)


## The palette for a mode index (default on a bad index or a missing file).
static func palette(m: int) -> AccessPalette:
	m = clampi(m, 0, PATHS.size() - 1)
	if not _palettes.has(m):
		var p: AccessPalette = null
		if ResourceLoader.exists(PATHS[m]):
			p = load(PATHS[m]) as AccessPalette
		if p == null and m != 0:
			p = palette(0)
		if p == null:
			p = AccessPalette.new()
		_palettes[m] = p
	return _palettes[m]


static func all() -> Array[AccessPalette]:
	var out: Array[AccessPalette] = []
	for i in PATHS.size():
		out.append(palette(i))
	return out


## Drops the resolved colours (settings_changed): the next color() re-reads.
static func invalidate() -> void:
	_resolved.clear()
	_resolved_mode = -1


## Cinematics._exit_tree (the M9 static-cache rule): drops the loaded files too.
static func clear_cache() -> void:
	invalidate()
	_palettes.clear()


## Resolved colours are also keyed by mode, so a test that sets
## Settings.colorblind_mode directly still sees the new palette; the signal
## covers palette edits through the settings menu.
static func _listen() -> void:
	if _listening:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = tree.root.get_node_or_null("EventBus") if tree and tree.root else null
	if bus == null or not bus.has_signal("settings_changed"):
		return
	bus.connect("settings_changed", Palette.invalidate)
	_listening = true
