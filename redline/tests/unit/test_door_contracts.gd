extends RedlineTestCase
## M7 door contracts: every door of the new and re-plumbed rooms stays exactly
## where the world graph put it (plan door_contracts). The world map offsets
## were computed from these rects and spawns, so a room task that moves a
## door, an entry spawn or the bounds while replacing its stub breaks the map
## (test_world_map) and its neighbours' routes. This test names the drift.
##
## requires_flag is asserted exactly, empty included: a main-path door must
## stay open. Three doors get their flag later, from the task that adds the
## flag's producer, and that task updates its row here in the same PR:
##   CollectorBay -> EscapeTunnel      collector_drone_defeated  (CollectorBay)
##   PowerBlock -> SecurityStation     lowlight_power_rerouted   (PowerBlock)
##   SmugglerRoute -> ApartmentStack   shortcut_smuggler_route   (SmugglerRoute)
##   ApartmentStack -> SmugglerRoute   shortcut_smuggler_route   (D2b/D7b)
## A room may not add a door that is not listed here.

const ROOMS := "res://world/rooms/"

## Room -> [bounds, default spawn id].
const ROOM_TABLE := {
	"undercity/Wake": [Rect2(-64, -300, 1344, 396), &"start"],
	"undercity/MedicalRuin": [Rect2(-64, -360, 2064, 456), &"from_wake"],
	"undercity/MaintenanceShaft": [Rect2(-64, -980, 704, 1076), &"from_medical"],
	"undercity/FirstPursuit": [Rect2(-64, -420, 4224, 516), &"from_shaft"],
	"undercity/BrokenLift": [Rect2(-64, -800, 704, 896), &"from_pursuit"],
	"undercity/CollectorBay": [Rect2(0, -240, 480, 270), &"from_lift"],
	"undercity/EscapeTunnel": [Rect2(-64, -560, 2064, 656), &"from_bay"],
	"lowlight/Relay": [Rect2(-64, -360, 1100, 424), &"start"],
	"lowlight/NeonRoofs": [Rect2(-64, -500, 2500, 596), &"from_stack"],
	"lowlight/PowerBlock": [Rect2(-64, -240, 1088, 1104), &"from_roofs"],
	"lowlight/SecurityStation": [Rect2(-64, -560, 1312, 800), &"from_power"],
	"lowlight/RainlineChase": [Rect2(-64, -300, 4224, 500), &"from_security"],
	"lowlight/SmugglerRoute": [Rect2(-64, -540, 2500, 700), &"from_power"],
	"lowlight/ApartmentStack": [Rect2(-64, -960, 704, 1056), &"from_market"],
	"lowlight/BellTower": [Rect2(-64, -1250, 704, 1346), &"from_rainline"],
	"lowlight/WardenTower": [Rect2(-64, -300, 544, 364), &"from_bell"],
}

## Spawns that are not the entry of a listed door: [room, id, position, facing].
const EXTRA_SPAWNS := [
	["undercity/Wake", &"start", Vector2(40, 0), 1],
	["lowlight/Relay", &"start", Vector2(140, 0), 1],
]

## One row per door: [room, exit rect, target room, target entry,
## requires_flag, own entry id, own entry position, own entry facing].
## An own entry id of &"" means a one-way exit with no paired spawn.
const DOORS := [
	["undercity/Wake", Rect2(1264, -96, 16, 96), "undercity/MedicalRuin", &"from_wake", "", &"from_medical", Vector2(1236, 0), -1],
	["undercity/MedicalRuin", Rect2(-64, -96, 16, 96), "undercity/Wake", &"from_medical", "", &"from_wake", Vector2(-20, 0), 1],
	["undercity/MedicalRuin", Rect2(1984, -96, 16, 96), "undercity/MaintenanceShaft", &"from_medical", "", &"from_shaft", Vector2(1956, 0), -1],
	["undercity/MaintenanceShaft", Rect2(-64, -96, 16, 96), "undercity/MedicalRuin", &"from_shaft", "", &"from_medical", Vector2(-20, 0), 1],
	["undercity/MaintenanceShaft", Rect2(624, -816, 16, 96), "undercity/FirstPursuit", &"from_shaft", "", &"from_pursuit", Vector2(596, -720), -1],
	["undercity/FirstPursuit", Rect2(-64, -96, 16, 96), "undercity/MaintenanceShaft", &"from_pursuit", "", &"from_shaft", Vector2(-20, 0), 1],
	["undercity/FirstPursuit", Rect2(4144, -96, 16, 96), "undercity/BrokenLift", &"from_pursuit", "", &"from_lift", Vector2(4116, 0), -1],
	["undercity/BrokenLift", Rect2(-64, -96, 16, 96), "undercity/FirstPursuit", &"from_lift", "", &"from_pursuit", Vector2(-20, 0), 1],
	["undercity/BrokenLift", Rect2(624, -672, 16, 96), "undercity/CollectorBay", &"from_lift", "", &"from_bay", Vector2(596, -576), -1],
	["undercity/CollectorBay", Rect2(0, -96, 16, 96), "undercity/BrokenLift", &"from_bay", "", &"from_lift", Vector2(28, 0), 1],
	# Final requires_flag: collector_drone_defeated (the CollectorBay room task).
	["undercity/CollectorBay", Rect2(464, -96, 16, 96), "undercity/EscapeTunnel", &"from_bay", "", &"from_tunnel", Vector2(436, 0), -1],
	["undercity/EscapeTunnel", Rect2(-64, -96, 16, 96), "undercity/CollectorBay", &"from_tunnel", "", &"from_bay", Vector2(-20, 0), 1],
	["undercity/EscapeTunnel", Rect2(1984, -336, 16, 96), "lowlight/Relay", &"from_undercity", "", &"from_relay", Vector2(1956, -240), -1],
	["lowlight/Relay", Rect2(-48, -240, 16, 96), "undercity/EscapeTunnel", &"from_relay", "", &"from_undercity", Vector2(0, -144), 1],
	["lowlight/Relay", Rect2(1024, -96, 16, 96), "lowlight/FloodedAlley", &"from_relay", "", &"from_alley", Vector2(960, 0), -1],
	["lowlight/Relay", Rect2(-48, -96, 16, 96), "lowlight/BellTower", &"from_lift", "shortcut_bell_lift", &"from_lift", Vector2(16, 0), 1],
	["lowlight/NeonRoofs", Rect2(2420, -186, 16, 96), "lowlight/PowerBlock", &"from_roofs", "", &"from_power", Vector2(2380, -90), -1],
	["lowlight/NeonRoofs", Rect2(-64, -196, 16, 96), "lowlight/ApartmentStack", &"from_roofs", "", &"from_stack", Vector2(20, -100), 1],
	["lowlight/PowerBlock", Rect2(-64, -96, 16, 96), "lowlight/NeonRoofs", &"from_power", "", &"from_roofs", Vector2(20, 0), 1],
	["lowlight/PowerBlock", Rect2(-64, 672, 16, 96), "lowlight/SmugglerRoute", &"from_power", "", &"from_smuggler", Vector2(20, 768), 1],
	# Final requires_flag: lowlight_power_rerouted (the PowerBlock room task).
	["lowlight/PowerBlock", Rect2(1008, 672, 16, 96), "lowlight/SecurityStation", &"from_power", "", &"from_security", Vector2(972, 768), -1],
	["lowlight/SecurityStation", Rect2(-64, -96, 16, 96), "lowlight/PowerBlock", &"from_security", "", &"from_power", Vector2(20, 0), 1],
	["lowlight/SecurityStation", Rect2(1232, -480, 16, 96), "lowlight/RainlineChase", &"from_security", "", &"from_rainline", Vector2(1200, -384), -1],
	["lowlight/RainlineChase", Rect2(-64, -96, 16, 96), "lowlight/SecurityStation", &"from_rainline", "", &"from_security", Vector2(20, 0), 1],
	["lowlight/RainlineChase", Rect2(4144, -96, 16, 96), "lowlight/BellTower", &"from_rainline", "", &"from_bell", Vector2(4100, 0), -1],
	["lowlight/SmugglerRoute", Rect2(2420, -96, 16, 96), "lowlight/PowerBlock", &"from_smuggler", "", &"from_power", Vector2(2380, 0), -1],
	# Final requires_flag: shortcut_smuggler_route (the SmugglerRoute room task).
	["lowlight/SmugglerRoute", Rect2(-64, -96, 16, 96), "lowlight/ApartmentStack", &"from_smuggler", "", &"from_stack", Vector2(20, 0), 1],
	# Final requires_flag: shortcut_smuggler_route (D2b, with the HatchGate).
	["lowlight/ApartmentStack", Rect2(624, -96, 16, 96), "lowlight/SmugglerRoute", &"from_stack", "", &"from_smuggler", Vector2(580, 0), -1],
	["lowlight/ApartmentStack", Rect2(-64, -96, 16, 96), "lowlight/MarketRun", &"from_stack", "", &"from_market", Vector2(20, 0), 1],
	["lowlight/ApartmentStack", Rect2(624, -864, 16, 96), "lowlight/NeonRoofs", &"from_stack", "", &"from_roofs", Vector2(580, -768), -1],
	["lowlight/BellTower", Rect2(-64, -96, 16, 96), "lowlight/RainlineChase", &"from_bell", "", &"from_rainline", Vector2(20, 0), 1],
	["lowlight/BellTower", Rect2(624, -1152, 16, 96), "lowlight/WardenTower", &"from_bell", "", &"from_warden", Vector2(575, -1056), -1],
	["lowlight/BellTower", Rect2(-64, -1056, 16, 96), "lowlight/Relay", &"from_lift", "shortcut_bell_lift", &"from_lift", Vector2(20, -960), 1],
	["lowlight/WardenTower", Rect2(-64, -96, 16, 96), "lowlight/BellTower", &"from_warden", "", &"from_bell", Vector2(16, 0), 1],
	# The Krail reward exit drops Rook at the Relay lift; nothing comes back.
	["lowlight/WardenTower", Rect2(464, -96, 16, 96), "lowlight/Relay", &"from_lift", "warden_krail_defeated", &"", Vector2.ZERO, 0],
]


func _path(room: String) -> String:
	return ROOMS + room + ".tscn"


## Position in room space (the marker and exit parents sit at the origin, but
## do not rely on it).
func _room_pos(n: Node2D, room: Node) -> Vector2:
	var p := n.position
	var parent := n.get_parent()
	while parent != room and parent is Node2D:
		p += (parent as Node2D).position
		parent = parent.get_parent()
	return p


func _instance(room: String) -> Room:
	var path := _path(room)
	check(ResourceLoader.exists(path), "%s: scene missing" % room)
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate() as Room


func _spawn(inst: Room, id: StringName) -> SpawnMarker:
	for m in inst.find_children("*", "SpawnMarker", true, false):
		if (m as SpawnMarker).spawn_id == id:
			return m as SpawnMarker
	return null


func test_bounds_and_default_spawns() -> void:
	for room: String in ROOM_TABLE:
		var inst := _instance(room)
		if inst == null:
			continue
		check(inst.bounds == ROOM_TABLE[room][0], "%s: bounds %s, contract %s" % [room, inst.bounds, ROOM_TABLE[room][0]])
		var defaults: Array[StringName] = []
		for m in inst.find_children("*", "SpawnMarker", true, false):
			if (m as SpawnMarker).is_default:
				defaults.append((m as SpawnMarker).spawn_id)
		check(defaults == [ROOM_TABLE[room][1]], "%s: default spawn %s, contract %s" % [room, defaults, ROOM_TABLE[room][1]])
		inst.free()
	for row: Array in EXTRA_SPAWNS:
		var inst := _instance(row[0])
		if inst == null:
			continue
		var m := _spawn(inst, row[1])
		check(m != null, "%s: spawn %s missing" % [row[0], row[1]])
		if m != null:
			check(_room_pos(m, inst) == row[2] and m.facing == row[3], "%s: spawn %s at %s facing %d, contract %s facing %d" % [row[0], row[1], _room_pos(m, inst), m.facing, row[2], row[3]])
		inst.free()


func test_every_door_matches_its_contract() -> void:
	for row: Array in DOORS:
		var room: String = row[0]
		var rect: Rect2 = row[1]
		var tag := "%s door %s" % [room, rect]
		var inst := _instance(room)
		if inst == null:
			continue
		var found: RoomExit = null
		for e in inst.find_children("*", "RoomExit", true, false):
			if Rect2(_room_pos(e as Node2D, inst), (e as RoomExit).size) == rect:
				found = e as RoomExit
		check(found != null, "%s: no exit with this rect" % tag)
		if found != null:
			check(found.target_room == _path(row[2]), "%s: targets %s, contract %s" % [tag, found.target_room, _path(row[2])])
			check(found.target_entry == row[3], "%s: target entry %s, contract %s" % [tag, found.target_entry, row[3]])
			check(found.requires_flag == row[4], "%s: requires_flag '%s', contract '%s'" % [tag, found.requires_flag, row[4]])
		if row[5] != &"":
			var m := _spawn(inst, row[5])
			check(m != null, "%s: own entry spawn %s missing" % [tag, row[5]])
			if m != null:
				check(_room_pos(m, inst) == row[6], "%s: entry %s at %s, contract %s" % [tag, row[5], _room_pos(m, inst), row[6]])
				check(m.facing == row[7], "%s: entry %s faces %d, contract %d" % [tag, row[5], m.facing, row[7]])
		inst.free()


## A room task may not add a door the world graph does not know about.
func test_no_undeclared_doors() -> void:
	for room: String in ROOM_TABLE:
		var inst := _instance(room)
		if inst == null:
			continue
		var listed := DOORS.filter(func(r: Array) -> bool: return r[0] == room).size()
		var exits := inst.find_children("*", "RoomExit", true, false).size()
		check(exits == listed, "%s: %d exits, %d in the contract" % [room, exits, listed])
		inst.free()
