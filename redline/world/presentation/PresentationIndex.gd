class_name PresentationIndex
extends Resource
## Room scene -> RoomPresentation (data/presentation/rooms.tres), with a
## default per district (Room.district_name) for rooms without their own
## entry. Labs and test fixtures have neither and get null: they stay
## graybox and silent.
##
##   var p := PresentationIndex.for_room(room.scene_file_path, room.district_name)
##
## Keeps later districts (Ironworks, ...) to one data row each: a district
## default plus per-room overrides, no code.

const PATH := "res://data/presentation/rooms.tres"

## Backdrop layer stacks (ART_DIRECTION section 4).
const BACKDROP_KINDS: Array[StringName] = [&"uc_ward", &"uc_pursuit", &"uc_tunnel", &"uc_shaft", &"uc_boss_bay",
	&"ll_street", &"ll_canal", &"ll_interior", &"ll_roof", &"ll_tower", &"relay_hub", &"null_rig", &"pulse_pit", &"title"]
## Every ambience bed SOUND_DIRECTION plans (sections 2 and 7), shipped or
## not; a bed without an asset plays silence. T08 checks its bed bank
## against this list.
const BED_IDS: Array[StringName] = [&"amb_undercity_ward", &"amb_undercity_shaft", &"amb_undercity_tunnel",
	&"amb_lowlight_street", &"amb_lowlight_interior", &"amb_lowlight_roof", &"amb_lowlight_power",
	&"amb_relay_hub", &"amb_deeprig_void"]
## SOUND_DIRECTION section 3 reverb presets.
const REVERB_PRESETS: Array[StringName] = [&"ward", &"shaft", &"tunnel", &"street", &"interior", &"roof", &"relay", &"void"]
## SOUND_DIRECTION section 6 surfaces.
const SURFACES: Array[StringName] = [&"concrete", &"metal", &"water", &"wood"]
const MUSIC_DISTRICTS: Array[StringName] = [&"undercity", &"lowlight", &"relay", &"deep_rig", &"title"]

## scene path (String) -> RoomPresentation
@export var rooms: Dictionary = {}
## Room.district_name (String) -> RoomPresentation
@export var districts: Dictionary = {}

static var _index: PresentationIndex
static var _scene_districts: Dictionary = {}


static func get_index() -> PresentationIndex:
	if _index == null:
		_index = load(PATH) as PresentationIndex if ResourceLoader.exists(PATH) else PresentationIndex.new()
	return _index


static func clear_cache() -> void:
	_index = null
	_scene_districts.clear()


## The room's own entry, else its district's default, else null. Without
## `district_name` the district is read from the scene file's root node.
static func for_room(scene_path: String, district_name: String = "") -> RoomPresentation:
	var idx := get_index()
	var own: Variant = idx.rooms.get(scene_path)
	if own is RoomPresentation:
		return own
	var d := district_name if district_name != "" else district_of(scene_path)
	var def: Variant = idx.districts.get(d)
	return def if def is RoomPresentation else null


static func for_room_node(room: Node) -> RoomPresentation:
	if room == null:
		return null
	return for_room(room.scene_file_path, str(room.get("district_name")) if "district_name" in room else "")


## Room.district_name as stored in the scene's root node ("" when unset or
## not a room scene). Cached per path.
static func district_of(scene_path: String) -> String:
	if _scene_districts.has(scene_path):
		return _scene_districts[scene_path]
	var d := ""
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var ps := load(scene_path) as PackedScene
		if ps:
			var st := ps.get_state()
			for i in st.get_node_property_count(0):
				if st.get_node_property_name(0, i) == &"district_name":
					d = str(st.get_node_property_value(0, i))
	_scene_districts[scene_path] = d
	return d


## ContentValidator resource protocol: entries are RoomPresentations with
## known ids, and every room key names a scene that exists.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for k in rooms:
		var p: Variant = rooms[k]
		if not (p is RoomPresentation):
			out.append("room '%s': not a RoomPresentation" % k)
			continue
		if not ResourceLoader.exists(str(k)):
			out.append("room '%s': no such scene" % k)
		for e in (p as RoomPresentation).validate():
			out.append("room '%s': %s" % [str(k).get_file(), e])
	for k in districts:
		var p: Variant = districts[k]
		if not (p is RoomPresentation):
			out.append("district '%s': not a RoomPresentation" % k)
			continue
		for e in (p as RoomPresentation).validate():
			out.append("district '%s': %s" % [k, e])
	return out
