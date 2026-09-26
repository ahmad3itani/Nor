extends RedlineTestCase
## M8 world state (T08, design_world): every WorldStateSwitch in the world,
## the Relay across the Act I story presets, the arc props, Mara's door post,
## the radio board, the map notes and the three radio barks.
## Switches are set dressing only (WorldStateSwitch.content_errors), so none of
## this can move a route, a door or the economy.

const UC := "res://world/rooms/undercity/"
const LL := "res://world/rooms/lowlight/"
const RELAY := LL + "Relay.tscn"
const ALLEY := LL + "FloodedAlley.tscn"

## The contract: [room, switch, visible_when] for every switch in every world
## room (M7 ones first, then M8). A new switch must be listed here.
const STATES := [
	# M7
	[UC + "FirstPursuit.tscn", "HatchLive", "!flag:collector_drone_defeated"],
	[UC + "FirstPursuit.tscn", "HatchDead", "flag:collector_drone_defeated"],
	[UC + "BrokenLift.tscn", "CarLit", "flag:collector_drone_defeated"],
	[UC + "CollectorBay.tscn", "BayLit", "flag:collector_drone_defeated"],
	[LL + "Relay.tscn", "RadioRestored", "flag:dead_air_complete"],
	[LL + "Relay.tscn", "KrailTrophy", "flag:warden_krail_defeated"],
	[LL + "Relay.tscn", "NixCityMap", "flag:chart_lowlight_complete"],
	[LL + "NeonRoofs.tscn", "RainlineLive", "flag:lowlight_power_rerouted"],
	[LL + "PowerBlock.tscn", "GridDown", "!flag:lowlight_power_rerouted"],
	[LL + "PowerBlock.tscn", "GridRerouted", "flag:lowlight_power_rerouted"],
	[LL + "RainlineChase.tscn", "SweeperWreck", "flag:chase_rainline_done"],
	[LL + "SecurityStation.tscn", "SignalLost", "flag:chase_rainline_done"],
	# M8: the Relay
	[LL + "Relay.tscn", "VellSignLive", "!flag:warden_krail_defeated"],
	[LL + "Relay.tscn", "GalleryDoorLit", "flag:met_orr_radio"],
	[LL + "Relay.tscn", "PipMarket", "flag:repeater_market"],
	[LL + "Relay.tscn", "PipStack", "flag:repeater_stack"],
	[LL + "Relay.tscn", "PipBell", "flag:repeater_bell"],
	[LL + "Relay.tscn", "TrainWindowsLit", "flag:lowlight_power_rerouted"],
	[LL + "Relay.tscn", "IkoStall", "flag:met_iko"],
	[LL + "Relay.tscn", "DoorWatch", "flag:act1_complete"],
	[LL + "Relay.tscn", "MaraBench", "flag:arc_mara_krail"],
	[LL + "Relay.tscn", "VellSignDry", "flag:warden_krail_defeated"],
	[LL + "Relay.tscn", "NixTowerSheet", "flag:arc_nix_krail"],
	[LL + "Relay.tscn", "IkoSpireCrates", "flag:arc_iko_krail"],
	[LL + "Relay.tscn", "OrrOnAir", "flag:orr_air_named"],
	# M8: the Undercity
	[UC + "Wake.tscn", "CollectorMarkLive", "!flag:collector_drone_defeated"],
	[UC + "Wake.tscn", "CollectorMarkDead", "flag:collector_drone_defeated"],
	[UC + "BrokenLift.tscn", "CrewRadio", "flag:dead_air_complete"],
	[UC + "CollectorBay.tscn", "CargoStranded", "flag:warden_krail_defeated"],
	# M8: Lowlight
	[LL + "FloodedAlley.tscn", "RelayMarked", "flag:met_iko"],
	[LL + "FloodedAlley.tscn", "WantedPosters", "flag:orr_air_named"],
	[LL + "FloodedAlley.tscn", "GhostTags", "flag:orr_air_ghost"],
	[LL + "MarketRun.tscn", "StallRadios", "flag:dead_air_complete"],
	[LL + "MarketRun.tscn", "MarketLate", "flag:warden_krail_defeated"],
	[LL + "ApartmentStack.tscn", "WindowsLit", "flag:lowlight_power_rerouted"],
	[LL + "SecurityStation.tscn", "CellFourKnock", "flag:mem_seen_mf_lowlight_04"],
	[LL + "BellTower.tscn", "WardenBannerUp", "!flag:warden_krail_defeated"],
	[LL + "BellTower.tscn", "WardenBannerDown", "flag:warden_krail_defeated"],
	[LL + "BellTower.tscn", "CargoLeft", "flag:warden_krail_defeated"],
	[LL + "WardenTower.tscn", "KrailBannersUp", "!flag:warden_krail_defeated"],
	[LL + "WardenTower.tscn", "KrailBannersDown", "flag:warden_krail_defeated"],
	[LL + "SmugglerRoute.tscn", "DenMovedOn", "flag:met_iko"],
]

## The Relay's visible switches after each cumulative preset. From krail_down
## the arcs enter their krail stages on their own (Mara, Vell, Nix); Iko's
## needs her met beat heard, so her Spire crates wait for play.
const RELAY_BY_PRESET := {
	"fresh": ["VellSignLive"],
	"collector_down": ["VellSignLive", "GalleryDoorLit"],
	"relay_met": ["VellSignLive", "GalleryDoorLit"],
	"repeaters_2": ["VellSignLive", "GalleryDoorLit", "PipMarket", "PipStack"],
	"dead_air_done": ["VellSignLive", "GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "RadioRestored"],
	"grid_rerouted": ["VellSignLive", "GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "RadioRestored", "TrainWindowsLit"],
	"charted": ["VellSignLive", "GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "RadioRestored", "TrainWindowsLit",
		"NixCityMap"],
	"krail_down": ["GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "RadioRestored", "TrainWindowsLit", "NixCityMap",
		"KrailTrophy", "IkoStall", "MaraBench", "VellSignDry", "NixTowerSheet"],
	"act1_complete": ["GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "RadioRestored", "TrainWindowsLit", "NixCityMap",
		"KrailTrophy", "IkoStall", "MaraBench", "VellSignDry", "NixTowerSheet", "DoorWatch"],
}

## relay_board's pick after each cumulative preset.
const BOARD_BY_PRESET := {
	"fresh": "board_dead", "collector_down": "board_dead", "relay_met": "board_counting",
	"repeaters_2": "board_counting", "dead_air_done": "board_codes", "grid_rerouted": "board_grid",
	"charted": "board_grid", "krail_down": "board_krail", "act1_complete": "board_act1",
}

## The Relay switches T08 added, and the always-on board speaker (x 290).
const RELAY_M8_SWITCHES := ["GalleryDoorLit", "PipMarket", "PipStack", "PipBell", "TrainWindowsLit", "IkoStall", "DoorWatch",
	"MaraBench", "VellSignDry", "NixTowerSheet", "IkoSpireCrates", "OrrOnAir"]
const PILLARS := [80, 340, 600, 900]
const PILLAR_W := 14.0
const WORKBENCH := Vector2(590, 630)

## [sequence id, room, entry, trigger node, flags that satisfy play_when]
const BARKS := [
	["bark_market_patrol", LL + "MarketRun.tscn", &"from_alley", "BarkMarketPatrol", ["dead_air_complete"]],
	["bark_bell_lift", LL + "BellTower.tscn", &"from_rainline", "BarkBellLift", ["dead_air_complete"]],
	["bark_tunnel_orr", UC + "EscapeTunnel.tscn", &"from_bay", "BarkTunnelOrr", ["act1_complete"]],
]

var root: Node2D
var _box: Variant = null


func before_each() -> void:
	CinematicMode.teardown()
	CinematicMode.reset()
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = null
	get_tree().paused = false
	CinematicMode.teardown()
	CinematicMode.reset()
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


# --- Helpers ------------------------------------------------------------------------

func _presets() -> Array[StoryPreset]:
	return StoryPresets.all()


func _enter(path: String, entry: StringName) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(3)
	return SceneRouter.current_room as Room


func _world_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	for r in Game.world_map.rooms:
		out.append(r.room_path)
	return out


## Every WorldStateSwitch in a room scene: {name: visible_when}.
func _switches_in(path: String) -> Dictionary:
	var inst := (load(path) as PackedScene).instantiate()
	var out := {}
	for n in inst.find_children("*", "WorldStateSwitch", true, false):
		out[String(n.name)] = (n as WorldStateSwitch).visible_when
	inst.free()
	return out


func _visible_switches(room: Room) -> Array:
	var out := []
	for n in room.find_children("*", "WorldStateSwitch", true, false):
		if (n as WorldStateSwitch).visible:
			out.append(String(n.name))
	out.sort()
	return out


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func _npc(room: Room, node_name: String) -> NPC:
	return room.find_child(node_name, true, false) as NPC


func _note(room_path: String) -> Dictionary:
	for m: Dictionary in WorldMapIndex.room_info(room_path)["markers"]:
		if int(m["kind"]) == MapMarker.Kind.NOTE:
			return m
	return {}


func _board() -> NpcProfile:
	return load("res://data/npcs/relay_board.tres") as NpcProfile


## Horizontal extent of a drawn prop (Decor is bottom-centred, NeonSign
## centred; both are size.x wide around their x).
func _span(n: Node, room: Room) -> Vector2:
	var x := WorldMapIndex.local_pos(n, room).x
	var w: float = (n.get("size") as Vector2).x
	return Vector2(x - w * 0.5, x + w * 0.5)


func _overlaps(a: Vector2, b: Vector2) -> bool:
	return a.x < b.y and b.x < a.y


# --- The contract -------------------------------------------------------------------

func test_world_state_contract() -> void:
	var expected := {}
	for row: Array in STATES:
		expected["%s|%s" % [row[0], row[1]]] = row[2]
	var found := {}
	for path in _world_rooms():
		var sw := _switches_in(path)
		for name: String in sw:
			found["%s|%s" % [path, name]] = sw[name]
	for key: String in expected:
		check(found.has(key), "switch missing: %s" % key)
		if found.has(key):
			check(found[key] == expected[key], "%s: visible_when '%s', expected '%s'" % [key, found[key], expected[key]])
	for key: String in found:
		check(expected.has(key), "switch not in the STATES table: %s (%s)" % [key, found[key]])


func test_switch_children_visual_only() -> void:
	for path in _world_rooms():
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("*", "WorldStateSwitch", true, false):
			var errors := (n as WorldStateSwitch).content_errors(inst)
			check(errors.is_empty(), "%s/%s: %s" % [path.get_file(), n.name, errors])
			check(n.get_child_count() > 0, "%s/%s is empty" % [path.get_file(), n.name])
		inst.free()


## Every switch pair on x / !x shows exactly one side under every preset.
func test_exclusive_pairs() -> void:
	var pairs := []
	for a: Array in STATES:
		for b: Array in STATES:
			if a[0] == b[0] and String(b[2]) == "!" + String(a[2]):
				pairs.append([a, b])
	# Every "!flag:x" switch has a "flag:x" partner in its room (the Bell Tower
	# banner has two: the fallen cloth and the cargo left behind).
	for a: Array in STATES:
		if String(a[2]).begins_with("!"):
			check(pairs.any(func(p: Array) -> bool: return p[1] == a), "%s has no flag:x partner" % a[1])
	check(pairs.size() >= 6, "x/!x pairs found (got %d)" % pairs.size())
	for p in _presets():
		Game.new_game()
		StoryPresets.apply(p.id)
		for pair: Array in pairs:
			var on := Game.check_condition(pair[0][2])
			var off := Game.check_condition(pair[1][2])
			check(on != off, "%s: %s/%s both %s at %s" % [String(pair[0][0]).get_file(), pair[0][1], pair[1][1], on, p.id])


# --- The Relay ----------------------------------------------------------------------

func test_relay_states_by_preset() -> void:
	var room := await _enter(RELAY, &"start")
	check(_visible_switches(room) == _sorted(RELAY_BY_PRESET["fresh"]), "fresh Relay: %s" % str(_visible_switches(room)))
	for p in _presets():
		# Cumulative: applying the next preset on top updates the room live.
		StoryPresets.apply(p.id)
		await physics_frames(1)
		var want: Array = _sorted(RELAY_BY_PRESET.get(p.id, []))
		check(_visible_switches(room) == want, "%s: visible %s, expected %s" % [p.id, _visible_switches(room), want])


func test_relay_arc_props() -> void:
	StoryPresets.apply("relay_met")
	var room := await _enter(RELAY, &"start")
	for name: String in ["MaraBench", "VellSignDry", "NixTowerSheet", "IkoSpireCrates", "OrrOnAir"]:
		check(not (room.find_child(name, true, false) as WorldStateSwitch).visible, "%s hidden before its stage" % name)
	check((room.find_child("VellSignLive", true, false) as WorldStateSwitch).visible, "Vell's sign live before Krail")
	for npc: String in ["mara", "vell", "nix", "iko"]:
		Game.arcs.force_stage(npc, "krail")
	for name: String in ["MaraBench", "NixTowerSheet", "IkoSpireCrates"]:
		check((room.find_child(name, true, false) as WorldStateSwitch).visible, "%s shows once its krail stage is reached" % name)
	# Vell's supply line is a world fact: the kill cuts it, talked to or not.
	check((room.find_child("VellSignLive", true, false) as WorldStateSwitch).visible, "the sign follows the kill, not Vell's stage")
	Game.set_flag("warden_krail_defeated")
	check((room.find_child("VellSignDry", true, false) as WorldStateSwitch).visible, "VellSignDry once Krail is down")
	check(not (room.find_child("VellSignLive", true, false) as WorldStateSwitch).visible, "the live sign goes dark with the dry one")
	Game.set_flag("orr_air_named")
	check((room.find_child("OrrOnAir", true, false) as WorldStateSwitch).visible, "OrrOnAir after the named choice")
	var alley := await _enter(ALLEY, &"from_relay")
	check((alley.find_child("WantedPosters", true, false) as WorldStateSwitch).visible, "WantedPosters after named")
	check(not (alley.find_child("GhostTags", true, false) as WorldStateSwitch).visible, "no GhostTags after named")
	Game.new_game()
	Game.set_flag("orr_air_ghost")
	alley = await _enter(ALLEY, &"from_relay")
	check((alley.find_child("GhostTags", true, false) as WorldStateSwitch).visible, "GhostTags after ghost")
	check(not (alley.find_child("WantedPosters", true, false) as WorldStateSwitch).visible, "no WantedPosters after ghost")


func test_mara_post_exclusive() -> void:
	var info := WorldMapIndex.room_info(RELAY)
	for p in _presets():
		Game.new_game()
		StoryPresets.apply(p.id)
		var room := await _enter(RELAY, &"start")
		var bench := _npc(room, "NPC_mara")
		var door := _npc(room, "NPC_mara_door")
		check(bench != null and door != null, "both Mara posts exist")
		if bench == null or door == null:
			return
		check(bench.is_present() != door.is_present(), "%s: exactly one Mara (bench %s, door %s)" % [p.id, bench.is_present(), door.is_present()])
		check(door.is_present() == Game.has_flag("act1_complete"), "%s: the door post only after the Act I close" % p.id)
		check(bench.visible == bench.is_present() and door.visible == door.is_present(), "%s: visibility follows presence" % p.id)
		var pins := MapView.visible_npcs(info).filter(func(n: Dictionary) -> bool: return n["id"] == "mara")
		check(pins.size() == 1, "%s: one Mara pin on the map (got %d)" % [p.id, pins.size()])
		if pins.size() == 1:
			check((pins[0]["pos"] as Vector2).x == (930.0 if Game.has_flag("act1_complete") else 660.0), "%s: the pin follows her post" % p.id)


## A named post never blocks and never moves the route: both RouteBot routes
## out of the Relay (test_slice_routes) still arrive with the Act I close done.
func test_relay_routes_under_act1_complete() -> void:
	var routes := [
		[[["run", 980], ["exit", 1]], "FloodedAlley"],
		[[["run", 178], ["jump", 178], ["jump", 112], ["jump", 30], ["exit", -1]], "EscapeTunnel"],
	]
	for r: Array in routes:
		Game.new_game()
		StoryPresets.apply("act1_complete")
		var room := await _enter(RELAY, &"start")
		for e in room.find_children("*", "Enemy", true, false):
			(e as Enemy).ai_enabled = false
		room.player.reactor.config = room.player.reactor.config.duplicate()
		room.player.reactor.config.drain_per_second = 0.0
		var bot := RouteBot.new(get_tree(), room.player)
		await physics_frames(10)
		var ok: bool = await bot.run(r[0])
		check(ok, "Relay -> %s under act1_complete: %s" % [r[1], bot.failure])
		if ok:
			check((SceneRouter.current_room as Room).name == r[1], "ended in %s, expected %s" % [SceneRouter.current_room.name, r[1]])


func test_relay_m8_props_clear_spawns_and_bench() -> void:
	for p in _presets():
		Game.new_game()
		StoryPresets.apply(p.id)
		# Every arc prop too, so the fullest Relay is checked at every step.
		for npc: String in ["mara", "vell", "nix", "iko"]:
			Game.arcs.force_stage(npc, "krail")
		Game.set_flag("orr_air_named")
		var room := await _enter(RELAY, &"start")
		var blockers := {}
		for s in room.find_children("*", "SpawnMarker", true, false):
			var x := WorldMapIndex.local_pos(s, room).x
			blockers["spawn %s" % (s as SpawnMarker).spawn_id] = Vector2(x - 12, x + 12)
		for x: int in PILLARS:
			blockers["pillar %d" % x] = Vector2(x - PILLAR_W * 0.5, x + PILLAR_W * 0.5)
		# Props: every drawn child of a visible M8 switch, plus the speaker.
		var props := []
		for name: String in RELAY_M8_SWITCHES:
			var sw := room.find_child(name, true, false) as WorldStateSwitch
			if sw and sw.visible:
				for c in sw.get_children():
					props.append([name, c])
		for d in room.find_children("*", "Decor", true, false):
			if (d as Decor).kind == Decor.Kind.RADIO and is_equal_approx(WorldMapIndex.local_pos(d, room).x, 290.0):
				props.append(["board speaker", d])
		check(props.size() >= 3, "%s: M8 props found (%d)" % [p.id, props.size()])
		for pr: Array in props:
			var span := _span(pr[1], room)
			for b: String in blockers:
				check(not _overlaps(span, blockers[b]), "%s: %s %s overlaps %s" % [p.id, pr[0], span, b])
			# MaraBench is Mara's own lamp on her bench; nothing else sits on it.
			if pr[0] != "MaraBench":
				check(not _overlaps(span, WORKBENCH), "%s: %s %s sits on Mara's workbench" % [p.id, pr[0], span])
		# The M8 posts (the board and Mara's door post), while present.
		for post: String in ["NPC_relay_board", "NPC_mara_door"]:
			var n := _npc(room, post)
			check(n != null, "%s missing" % post)
			if n == null or not n.is_present():
				continue
			var x := WorldMapIndex.local_pos(n, room).x
			var box := Vector2(x - 12, x + 12)
			for b: String in blockers:
				check(not _overlaps(box, blockers[b]), "%s: %s box %s overlaps %s" % [p.id, post, box, b])
			check(not _overlaps(box, WORKBENCH), "%s: %s box on Mara's workbench" % [p.id, post])
		check(is_equal_approx(WorldMapIndex.local_pos(_npc(room, "NPC_mara_door"), room).x, 930.0), "NPC_mara_door at 930")


# --- The radio board ----------------------------------------------------------------

func test_relay_board_rules() -> void:
	var board := _board()
	check(board.validate().is_empty(), "relay_board validates: %s" % str(board.validate()))
	check(board.npc_id == "relay_board" and not board.figure and board.verb == "Listen" and board.cue_new_lines,
		"relay_board is a bodiless Listen voice with the new-lines cue")
	check(board.map_label == "Radio chatter", "relay_board map label")
	for r in board.rules:
		var d := r.dialogue
		check(d.set_flags.is_empty() and d.give_scrap == 0 and d.give_circuit == "" and d.give_weapon == ""
			and d.open_menu == &"" and d.choices.is_empty(), "%s gives and sets nothing" % d.id)
		for l in d.lines:
			check(l.speaker != "", "%s: every line has a speaker" % d.id)
	for p in _presets():
		Game.new_game()
		StoryPresets.apply(p.id)
		var d := board.pick_dialogue()
		check(d != null and d.id == BOARD_BY_PRESET[p.id], "%s: board plays %s, expected %s" % [p.id, d.id if d else "nothing", BOARD_BY_PRESET[p.id]])
	# The Relay NPC index keeps a role for every NPC (the board's is its label).
	for n: Dictionary in WorldMapIndex.room_info(RELAY)["npcs"]:
		check(n["role"] != "", "%s has no map label" % n["id"])


func test_radio_board_cue() -> void:
	StoryPresets.apply("grid_rerouted")
	var room := await _enter(RELAY, &"start")
	var npc := _npc(room, "NPC_relay_board")
	check(npc != null, "the board is in the Relay")
	if npc == null:
		return
	check(npc.has_pending_beat(), "unheard chatter ticks")
	_box = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(_box)
	npc.interact(room.player)
	check(_box.is_open(), "Listen opens the board's lines")
	var n := 0
	while _box.is_open() and n < 12:
		_box.advance()
		n += 1
	get_tree().paused = false
	check(not _box.is_open(), "the board's lines close")
	check(Game.has_flag("heard_board_grid") and not npc.has_pending_beat(), "heard: the tick clears")
	StoryPresets.apply("krail_down")
	check(npc.has_pending_beat(), "board_krail is new: the tick is back")


# --- Map notes ----------------------------------------------------------------------

func test_map_notes() -> void:
	var bell := _note(LL + "BellTower.tscn")
	check(not bell.is_empty() and bell["label"] == "Orr: crates go up here every night", "Bell Tower note")
	var states := {"relay_met": false, "dead_air_done": true, "krail_down": false}
	for id: String in states:
		Game.new_game()
		StoryPresets.apply(id)
		check(WorldMapIndex.marker_active(bell) == states[id], "Bell Tower note at %s should be %s" % [id, states[id]])
	var rail := _note(LL + "RainlineChase.tscn")
	Game.new_game()
	check(not rail.is_empty() and not WorldMapIndex.marker_active(rail), "Rainline note hidden before Orr's line")
	Game.set_flag("orr_rainline_line")
	check(WorldMapIndex.marker_active(rail), "Rainline note after Orr's line")
	Game.set_flag("chase_rainline_done")
	check(not WorldMapIndex.marker_active(rail), "Rainline note resolved by the chase")
	var tower := _note(LL + "WardenTower.tscn")
	Game.new_game()
	StoryPresets.apply("act1_complete")
	check(not tower.is_empty() and not WorldMapIndex.marker_active(tower), "Warden Tower note waits for Nix's beat")
	Game.set_flag("arcbeat_nix_krail")
	check(WorldMapIndex.marker_active(tower), "Warden Tower note after arcbeat_nix_krail (never resolves)")
	check(WorldMapIndex.room_info(ALLEY)["markers"].size() == 1, "the Flooded Alley keeps its one marker")


# --- Barks --------------------------------------------------------------------------

func test_barks_nonlocking_and_instant() -> void:
	for b: Array in BARKS:
		var seq := load("res://data/sequences/%s.tres" % b[0]) as SequenceData
		check(seq != null, "%s loads" % b[0])
		if seq == null:
			continue
		check(seq.content_check().is_empty(), "%s validates: %s" % [b[0], seq.content_check()])
		check(not seq.lock_input and not seq.hide_hud and not seq.letterbox and not seq.locks_for(true) and not seq.locks_for(false),
			"%s is a non-locking bark" % b[0])
		check(seq.steps.size() == 1 and seq.steps[0] is SeqLine, "%s is one line" % b[0])
		check(seq.effective_seen_flag() == "seen_seq_%s" % b[0], "%s keeps the default seen flag" % b[0])
		Game.new_game()
		for f: String in b[4]:
			Game.set_flag(f)
		var room := await _enter(b[1], b[2])
		var trig := room.find_child(b[3], true, false) as SequenceTrigger
		check(trig != null and trig.sequence == seq, "%s: trigger %s plays it" % [b[0], b[3]])
		if trig == null:
			continue
		check(not Game.has_flag(seq.effective_seen_flag()), "%s unseen before the trigger" % b[0])
		var p := room.player
		p.invulnerable = true
		p.global_position = trig.global_position + Vector2(trig.size.x * 0.5, trig.size.y)
		var locked := false
		for i in 20:
			await physics_frames(1)
			locked = locked or p.cinematic_lock or p.input_override != null
			if Game.has_flag(seq.effective_seen_flag()):
				break
		check(Game.has_flag(seq.effective_seen_flag()), "%s: entering the trigger plays it (INSTANT headless)" % b[0])
		check(not locked and not p.cinematic_lock, "%s never locks Rook" % b[0])
