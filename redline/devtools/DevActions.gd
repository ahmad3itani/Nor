class_name DevActions
extends RefCounted
## Internal development tools (bible §34: teleport-to-room, unlock-all
## debug profile, quick boss restart, enemy spawning, save-state inspector,
## hitbox visualization, performance overlay). The DevConsole menu calls
## these; tests call them directly. Debug/editor builds only.

const VARIANT_DIR := "res://enemies/variants"
const SEQUENCE_DIR := "res://data/sequences"
const ACT1_CLOSE := "act1_close"

## Tests only: forces available() false so the gate itself can be tested in a
## debug build (the tests run in one, where available() is always true).
static var force_unavailable: bool = false


static func available() -> bool:
	if force_unavailable:
		return false
	return OS.is_debug_build() or OS.has_feature("editor")


## Every world room and its entries, for the teleport list.
static func teleport_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in Game.world_map.rooms:
		var info := WorldMapIndex.room_info(r.room_path)
		var ids: Array = (info["spawns"] as Dictionary).keys()
		ids.sort()
		for id: String in ids:
			out.append({"room": r.room_path, "entry": id, "label": "%s  ·  %s" % [info["name"], id]})
	return out


static func teleport(room_path: String, entry: String) -> void:
	SceneRouter.transition_to(room_path, StringName(entry))


## A profile that owns everything the game has, for testing late content:
## all weapons and Circuits, Dash, max shards, lots of Scrap, the map and
## transit, every room visited and fully explored, every Anchor on the line.
static func unlock_all() -> void:
	var st := Game.state
	# M9 (D-145): a fabricated profile never earns achievements.
	st.dev_tainted = true
	for w in Game.catalog.weapons:
		if not st.owned_weapons.has(String(w.id)):
			st.owned_weapons.append(String(w.id))
	for c in Game.catalog.circuits:
		if not st.owned_circuits.has(String(c.id)):
			st.owned_circuits.append(String(c.id))
	# A campaign profile may still be unarmed: fill empty slots with the kit.
	if st.melee_weapon == "":
		st.melee_weapon = GameState.DEFAULT_MELEE
	if st.ranged_weapon == "":
		st.ranged_weapon = GameState.DEFAULT_RANGED
	# set_flag(false), never erase: the HUD only reacts to flag_changed.
	Game.set_flag("core_hud_hidden", false)
	Game.set_ability(&"dash", true)
	# Every Core Shard in the game after M7 (five, capacity 9, D-082).
	st.core_shards = maxi(st.core_shards, 5)
	st.scrap_banked = maxi(st.scrap_banked, 9999)
	var flags: Array[String] = ["transit_pass", "map_lens", "injector_upgrades"]
	for d in Game.world_map.districts():
		flags.append("map_%s" % d)
	for f in flags:
		Game.set_flag(f, 1)
	for r in Game.world_map.rooms:
		if not st.visited_rooms.has(r.room_path):
			st.visited_rooms.append(r.room_path)
		var info := WorldMapIndex.room_info(r.room_path)
		var b: Rect2 = info["bounds"]
		var y := b.position.y + 32.0
		while y < b.end.y:
			var x := b.position.x + 32.0
			while x < b.end.x:
				MapProgress.reveal(st, Game.world_map, r.room_path, Vector2(x, y))
				x += 96.0
			y += 96.0
		for a: Dictionary in info["anchors"]:
			var key := "%s|%s" % [r.room_path, a["id"]]
			if not st.anchors_rested.has(key):
				st.anchors_rested.append(key)
	EventBus.scrap_changed.emit(st.total_scrap())
	EventBus.loadout_changed.emit()


## M9 endgame start: the act1_complete story preset plus unlock-all, so NG+,
## The Null and the challenge list can be reached without a playthrough.
## null_open follows from act1_complete through Game.DERIVED_FLAGS (D-154);
## this never sets it itself. The profile is dev-tainted (unlock_all): no
## achievements are earned on it (D-145).
static func apply_endgame_state() -> void:
	StoryPresets.apply("act1_complete")
	unlock_all()
	EventBus.hint_requested.emit("DEV: Act I complete + unlock-all (no achievements)", 2.0)


## Boss id -> [room path, entry at the arena door]. The Collector's room is
## written as a format string: CollectorBay lands with the Undercity rooms,
## and the content scanner only checks literal paths.
static func boss_restart_target(boss_id: String) -> Array:
	match boss_id:
		"warden_krail":
			return ["res://world/rooms/lowlight/WardenTower.tscn", &"from_bell"]
		"collector_drone":
			return ["res://world/rooms/%s/%s.tscn" % ["undercity", "CollectorBay"], &"from_lift"]
	return []


## Re-arm a boss (clear the win) and drop Rook at the arena door with full
## health: iterate on the fight without replaying the way there.
static func quick_boss_restart(boss_id: String = "warden_krail") -> void:
	var target := boss_restart_target(boss_id)
	if target.is_empty() or not ResourceLoader.exists(target[0]):
		push_warning("quick_boss_restart: no arena room for %s" % boss_id)
		return
	Game.state.flags.erase("%s_defeated" % boss_id)
	# Heal the live player too: leaving the room captures its state.
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.combat.rest()
	Game.state.health = -1
	Game.state.injectors = -1
	Game.state.reactor_charge = -1.0
	SceneRouter.transition_to(target[0], target[1])


## Export-safe scan (K-M8-22): exported builds list .tscn.remap files.
static func enemy_scenes() -> PackedStringArray:
	return DataDir.list_scenes(VARIANT_DIR)


## Spawns an enemy 90 px in front of Rook in the current room.
static func spawn_enemy(scene_path: String) -> Enemy:
	var room := SceneRouter.current_room as Room
	if room == null or not is_instance_valid(room.player):
		return null
	var e := (load(scene_path) as PackedScene).instantiate() as Enemy
	e.position = room.player.position + Vector2(90.0 * room.player.facing, -2.0)
	room.add_child(e)
	return e


## Save-state inspector text: what the profile holds right now.
static func state_summary() -> String:
	var st := Game.state
	var flags: Array = st.flags.keys()
	flags.sort()
	var flag_text := PackedStringArray()
	for f: String in flags:
		flag_text.append("%s=%s" % [f, st.flags[f]])
	var lines := PackedStringArray([
		"Scrap %d banked + %d carried · shards %d · deaths %d · time %s" % [st.scrap_banked, st.scrap_unbanked, st.core_shards, st.deaths, SliceStats.format_time(st.play_time_sec)],
		"Respawn: %s / %s" % [st.last_anchor_room.get_file(), st.last_anchor_id],
		"Weapons: %s (melee %s, ranged %s)" % [", ".join(st.owned_weapons), st.melee_weapon, st.ranged_weapon],
		"Circuits: %s   equipped: %s" % [", ".join(st.owned_circuits), ", ".join(st.equipped_circuits)],
		"Collected (%d): %s" % [st.collected.size(), ", ".join(PackedStringArray(st.collected.keys()))],
		"Rooms visited %d · Anchors on the line %d · pins %d" % [st.visited_rooms.size(), st.anchors_rested.size(), st.map_pins.size()],
		story_line(),
	])
	lines.append_array(sequence_lines())
	lines.append("Flags (%d): %s" % [flags.size(), ", ".join(flag_text)])
	return "\n".join(lines)


## "Story: act 1 · arcs mara 2/3 vell 1/3 … · memories 2 · endings seen none".
static func story_line() -> String:
	var arcs := PackedStringArray()
	if Game.arcs:
		for a in Game.arcs.arcs:
			arcs.append("%s %d/%d" % [a.npc_id, a.current_index(), a.stages.size()])
	var seen := PackedStringArray()
	for e in EndingResolver.all():
		if Game.has_flag(e.seen_flag()):
			seen.append(e.id)
	return "Story: act %d · arcs %s · memories %d · endings seen %s" % [
		ActLibrary.current_act(), " ".join(arcs) if not arcs.is_empty() else "-",
		MemoryLibrary.remembered_count(), ", ".join(seen) if not seen.is_empty() else "none"]


## "SEQ playing <id> step i/n first|repeat" (or "SEQ idle"), then the
## sequences this profile has seen.
static func sequence_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var p := Cinematics.current
	if Cinematics.is_playing():
		out.append("SEQ playing %s step %d/%d %s%s" % [p.seq.id, maxi(p.index, 0) + 1, p.seq.steps.size(),
			"first" if p.first_view else "repeat", "" if p.locking else " (unlocked)"])
	else:
		out.append("SEQ idle")
	var seen := PackedStringArray()
	for seq in sequences(true):
		if Game.has_flag(seq.effective_seen_flag()):
			seen.append(seq.id)
	out.append("SEQ seen: %s" % (", ".join(seen) if not seen.is_empty() else "none"))
	return out


static func state_json() -> String:
	var d := Game.state.to_dict()
	d["schema_version"] = SaveManager.CURRENT_SCHEMA_VERSION
	return JSON.stringify(d, "  ")


# --- M8 story tools (T09): Sequence / Memory / Ending theatres, arcs, presets ---
# Every action that changes the profile or the scene is gated by available().
# The theatres run with CinematicMode.theatre on (trigger autoplay and
# sequence telemetry off) and never mark the profile (D-128).

## Every sequence in data/sequences, sorted by id. The test fixtures
## (data/sequences/test_*) only with include_tests.
static func sequences(include_tests: bool = false) -> Array[SequenceData]:
	var out: Array[SequenceData] = []
	for path in DataDir.list(SEQUENCE_DIR):
		var seq := load(path) as SequenceData
		if seq == null or seq.id == "":
			continue
		if include_tests or not seq.id.begins_with("test_"):
			out.append(seq)
	out.sort_custom(func(a: SequenceData, b: SequenceData) -> bool: return a.id < b.id)
	return out


static func sequence_ids(include_tests: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	for seq in sequences(include_tests):
		out.append(seq.id)
	return out


static func sequence(id: String) -> SequenceData:
	for seq in sequences(true):
		if seq.id == id:
			return seq
	return null


## The ending whose sequence is `sequence_id`, or null (a theatre row for an
## ending sequence plays the whole ending, sandboxed).
static func ending_for_sequence(sequence_id: String) -> EndingData:
	for e in EndingResolver.all():
		if e.sequence and e.sequence.id == sequence_id:
			return e
	return null


## Plays `id` where Rook is now (no teleport, no sandbox): tests and the
## tour. first_view forces the view through SequenceContext.first_view.
static func play_sequence(id: String, first_view: bool = true) -> SequenceResult:
	var seq := sequence(id)
	if not available() or seq == null:
		return null
	var ctx := _context_for(seq, SceneRouter.current_room as Room)
	ctx.first_view = 1 if first_view else 0
	return await Cinematics.play(seq, ctx)


## Dev preview: teleport to the sequence's room / preview_entry and play it
## there. view: 1 = first view, 0 = repeat, -1 = the seen flag decides.
## The view is forced through SequenceContext.first_view, never by editing
## the seen flag. CinematicMode.theatre goes on BEFORE the teleport, so the
## room's own SequenceTrigger stays quiet (T07 guard), and the play runs in a
## FlagSandbox: a preview never marks the profile (its seen flag, and what
## the scene sets, e.g. act1_complete, are all put back).
## A static coroutine: fire-and-forget callers are safe (K-M8-23).
static func preview_sequence(id: String, view: int = 1) -> SequenceResult:
	if not available():
		return null
	var restore := FlagSandbox.begin()
	var res := await _preview(id, view)
	restore.call()
	return res


## preview_sequence without its own sandbox (replay_act1_close owns one).
static func _preview(id: String, view: int) -> SequenceResult:
	var seq := sequence(id)
	if seq == null:
		push_warning("preview_sequence: no sequence '%s'" % id)
		return null
	var theatre_was := CinematicMode.theatre
	CinematicMode.theatre = true
	if seq.room != "" and ResourceLoader.exists(seq.room) and SceneRouter.world_root != null:
		SceneRouter.goto_room(seq.room, seq.preview_entry)
		# The room's deferred setup (camera, autoplay triggers, quiet under
		# theatre) runs before the first step.
		var tree := Engine.get_main_loop() as SceneTree
		for i in 2:
			await tree.process_frame
	var ctx := _context_for(seq, SceneRouter.current_room as Room)
	ctx.first_view = view if view >= 0 else (1 if Cinematics.first_view(seq) else 0)
	var res: SequenceResult = await Cinematics.play(seq, ctx)
	CinematicMode.theatre = theatre_was
	return res


## Room-independent sequences draw on the overlay only; a boss intro binds
## its arena (so @boss / @arena resolve); anything else binds the room.
static func _context_for(seq: SequenceData, room: Room) -> SequenceContext:
	if seq.room == "":
		return SequenceContext.for_overlay(room)
	if room:
		for n in room.find_children("*", "BossArena", true, false):
			var arena := n as BossArena
			if arena.intro_sequence and arena.intro_sequence.id == seq.id:
				return SequenceContext.for_arena(arena, true)
	return SequenceContext.for_room(room)


## Memory theatre: one vignette through the normal request signal (the
## MemoryScenePlayer answers; source &"dev" is neither a rest nor a journal
## replay).
static func play_memory(id: String) -> void:
	if available():
		EventBus.memory_playback_requested.emit(PackedStringArray([id]), &"dev")


static func grant_all_fragments() -> void:
	if available():
		Game.state.dev_tainted = true
		MemoryLibrary.dev_grant_all_fragments()


static func reset_memories() -> void:
	if available():
		MemoryLibrary.dev_reset()


static func arc_summary() -> String:
	return Game.arcs.summary() if Game.arcs else ""


static func force_arc_stage(npc: String, stage: String) -> void:
	if available() and Game.arcs:
		Game.state.dev_tainted = true
		Game.arcs.force_stage(npc, stage)


static func reset_arcs() -> void:
	if available() and Game.arcs:
		Game.arcs.dev_reset()


static func apply_story_preset(id: String) -> void:
	if available():
		Game.state.dev_tainted = true
		StoryPresets.apply(id)


## Ending ids in priority order.
static func ending_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in EndingResolver.all():
		out.append(e.id)
	return out


## Ending theatre: sandboxed, theatre on. Fire and forget: EndingDirector
## retains itself in _running until play() returns (K-M8-23).
static func play_ending(id: String) -> void:
	var e := EndingResolver.by_id(id)
	if not available() or e == null:
		return
	EndingDirector.new().play(e, true)


## One explain() entry as the theatre shows it:
## "✗ Story flag:act5_finale_reached (Act V)".
static func explain_line(c: Dictionary) -> String:
	var act := ""
	if c["future"]:
		act = "  (Act %s)" % ["I", "II", "III", "IV", "V", "VI"][clampi(int(c["act"]) - 1, 0, 5)]
	return "%s %s %s%s" % ["✓" if c["ok"] else "✗", c["group"], c["expr"], act]


static func ending_explain(id: String) -> String:
	var e := EndingResolver.by_id(id)
	if e == null:
		return ""
	var lines := PackedStringArray()
	for c in EndingResolver.explain(e):
		lines.append(explain_line(c))
	return "\n".join(lines)


## explain() of every ending, then "resolves now: <id|none>".
static func ending_report() -> String:
	var lines := PackedStringArray()
	for e in EndingResolver.all():
		lines.append("%s%s  (priority %d)" % [e.title, "  [hidden]" if e.hidden else "", e.priority])
		for c in EndingResolver.explain(e):
			lines.append("  " + explain_line(c))
	var r := EndingResolver.resolve()
	lines.append("resolves now: %s" % (r.id if r else "none"))
	return "\n".join(lines)


## Tests and the story tour: every condition of `id` made true inside a
## FlagSandbox (flag:x -> true, !flag:x -> false, atleast:x:n -> n). Returns
## the sandbox's restore. Refuses anything that is not a flag (collected:,
## ability:, count:) with a warning; endings use none of them.
static func satisfy_ending(id: String) -> Callable:
	var e := EndingResolver.by_id(id)
	if not available() or e == null:
		return func() -> void: pass
	var restore := FlagSandbox.begin()
	for c in e.all_conditions():
		if c.begins_with("!flag:"):
			Game.set_flag(c.get_slice(":", 1), false)
		elif c.begins_with("flag:"):
			Game.set_flag(c.get_slice(":", 1), true)
		elif c.begins_with("atleast:"):
			var f := c.get_slice(":", 1)
			Game.set_flag(f, maxi(Game.flag_int(f), c.get_slice(":", 2).to_int()))
		else:
			push_warning("satisfy_ending(%s): refuses '%s' (not a flag)" % [id, c])
	return restore


## "Replay Act I close + card": the close in the Relay, then the Act I card,
## inside one FlagSandbox with theatre on. Both are put back once the card
## closes (at once when no SliceEndMenu is in the tree: tests).
## A static coroutine on purpose: no RefCounted instance that could be freed
## mid-await (K-M8-23), so fire-and-forget callers are safe.
static func replay_act1_close() -> void:
	if not available():
		return
	var restore := FlagSandbox.begin()
	var theatre_was := CinematicMode.theatre
	CinematicMode.theatre = true
	# The card is about a finished Act I: play the close in that state.
	Game.set_flag("warden_krail_defeated")
	var res := await _preview(ACT1_CLOSE, 1)
	CinematicMode.theatre = true
	if res != null and not res.refused and not res.aborted():
		Game.set_flag("slice_end_seen")
		var tree := Engine.get_main_loop() as SceneTree
		var card := tree.root.find_child("SliceEndMenu", true, false) as MenuScreen
		EventBus.menu_requested.emit(&"slice_end")
		if is_instance_valid(card) and card.is_open():
			await card.closed
	CinematicMode.theatre = theatre_was
	restore.call()


## Clears <boss>_intro_seen, then quick_boss_restart: the arena plays the
## full first-view intro again when Rook walks in.
static func replay_boss_intro(boss_id: String) -> void:
	if not available():
		return
	Game.set_flag("%s_intro_seen" % boss_id, false)
	quick_boss_restart(boss_id)
