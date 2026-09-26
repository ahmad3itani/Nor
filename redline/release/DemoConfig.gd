class_name DemoConfig
extends Resource
## One demo's scope and end card (M9 D6, D-165). The demo is the full game
## with rooms and features gated at runtime by this data; nothing is stripped.
## Text fields are English source text, shown through Loc.t at the edge and
## listed for the string extractor by LOC_FIELDS.
## The CTA copy is a placeholder (FLAG D-165): it names no store and has no
## link, and the owner approves it before any public build.

enum EndMode { BORDER, ACT_CLOSE }

## Player-visible text fields -> max characters per line (DM-6).
const LOC_FIELDS := {"title_tag": 12, "title_subtitle": 60, "end_header": 40, "end_lines": 90, "secrets_note": 90,
	"cta_lines": 110, "keep_label": 40, "quit_label": 40}
const LOC_EXEMPT := ["id"]

@export var id: String = "undercity"
## Rooms the demo may load: every scene directly in these dirs, plus allowed_rooms.
@export var allowed_room_dirs: PackedStringArray = ["res://world/rooms/undercity"]
@export var allowed_rooms: PackedStringArray = ["res://world/rooms/TitleBackdrop.tscn"]
## BORDER: the card opens at any exit into a disallowed room.
## ACT_CLOSE: the card replaces the Act I card (slice_completed).
@export var end_mode: EndMode = EndMode.BORDER
## BuildInfo.KNOWN_FEATURES this demo switches off.
@export var disabled_features: Array[StringName] = [&"labs", &"lab_cycle", &"relay_start", &"ngplus", &"null", &"transit"]
## D-039: recording is off by default in demos (a player can still turn it on).
@export var recording_default: bool = false
## Achievement ids the demo's Achievements menu lists (T14 fills it, DM-4).
@export var achievements: PackedStringArray = []
## Trigger depth in px around a border exit: the card opens before the
## barrier wall is touched.
@export var barrier_depth: float = 12.0

@export_group("Text")
@export var title_tag: String = "DEMO"
@export var title_subtitle: String = "Demo  —  The Undercity"
@export var end_header: String = "END OF THE DEMO"
@export var end_lines: PackedStringArray = []
@export var secrets_note: String = ""
@export var cta_lines: PackedStringArray = []
@export var keep_label: String = "Keep exploring"
@export var quit_label: String = "Save and quit to title"


func allows(path: String) -> bool:
	return path in allowed_rooms or path.get_base_dir() in allowed_room_dirs


## Every room scene the demo may load (allowed dirs through DataDir, so an
## exported build lists the same rooms), plus allowed_rooms.
func room_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for d in allowed_room_dirs:
		out.append_array(DataDir.list_scenes(d))
	for r in allowed_rooms:
		if not r in out:
			out.append(r)
	return out


## Structure (DM-1 id, DM-5 features, DM-6 text lengths and required text).
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
		errs.append("[DM-1] demo id '%s' must match ^[a-z0-9_]+$" % id)
	if allowed_room_dirs.is_empty() and allowed_rooms.is_empty():
		errs.append("[DM-1] the demo allows no rooms")
	for f in disabled_features:
		if not f in BuildInfo.KNOWN_FEATURES:
			errs.append("[DM-5] unknown disabled feature '%s' (BuildInfo.KNOWN_FEATURES)" % f)
	for field: String in ["end_header", "keep_label", "quit_label", "title_tag"]:
		if String(get(field)).strip_edges() == "":
			errs.append("[DM-6] %s is empty" % field)
	for line in text_lines():
		var cap: int = LOC_FIELDS[line[0]]
		if String(line[1]).length() > cap:
			errs.append("[DM-6] %s is %d characters (max %d): \"%s\"" % [line[0], String(line[1]).length(), cap, String(line[1]).left(40)])
	if barrier_depth <= 0.0:
		errs.append("[DM-2] barrier_depth must be > 0")
	return errs


## [field, text] for every player-visible line (validator, extractor).
func text_lines() -> Array:
	var out: Array = []
	for field: String in LOC_FIELDS:
		var v: Variant = get(field)
		if v is PackedStringArray:
			for s in v:
				out.append([field, s])
		elif String(v) != "":
			out.append([field, String(v)])
	return out


func content_flags() -> Dictionary:
	return {"produces": ["demo_build", "demo_end_seen"]}


## Cross-file checks (DM-1): every allowed dir has scenes and every allowed
## room exists.
func content_check() -> PackedStringArray:
	var errs := PackedStringArray()
	for d in allowed_room_dirs:
		if DataDir.list_scenes(d).is_empty():
			errs.append("[DM-1] allowed dir %s has no room scenes" % d)
	for r in allowed_rooms:
		if not ResourceLoader.exists(r):
			errs.append("[DM-1] allowed room %s does not exist" % r)
	return errs
