class_name WorldMapData
extends Resource
## The world map layout and discovery rules (bible §20). One resource for the
## whole city; districts are just tags on rooms.

@export var rooms: Array[MapRoomData] = []
## Fog of discovery granularity (world px) and how far Rook "sees" (world px).
@export var cell_size: float = 64.0
@export var reveal_radius: float = 112.0
## Exits that are allowed to be far apart on the map (lifts, transit lines),
## written "FromRoom>ToRoom". Drawn as dashed lines instead of doorways.
@export var transit_links: PackedStringArray = []
## Exploring this share of a district's cells sets "map_charted_<district>".
## The fallback for districts without their own entry below.
@export_range(0.1, 1.0) var charted_threshold: float = 0.7
## Per-district chart thresholds, district -> share in (0, 1]. Districts
## differ in how many of their cells a path can reach at all (tall shafts,
## sealed walls), so one global share would make some charts impossible.
@export var district_thresholds: Dictionary = {}
## Player pins per profile (bible §20 "player pins").
@export var max_pins: int = 12
## District display names for the map legend.
@export var district_names: Dictionary = {"relay": "The Relay", "lowlight": "Lowlight"}


func room(room_id: String) -> MapRoomData:
	for r in rooms:
		if r.room_id() == room_id:
			return r
	return null


## The share of a district's cells that charts it.
func threshold_for(district: String) -> float:
	return float(district_thresholds.get(district, charted_threshold))


func rooms_in(district: String) -> Array[MapRoomData]:
	var out: Array[MapRoomData] = []
	for r in rooms:
		if r.district == district:
			out.append(r)
	return out


func districts() -> PackedStringArray:
	var out := PackedStringArray()
	for r in rooms:
		if not out.has(r.district):
			out.append(r.district)
	return out
