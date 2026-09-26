extends Node
## Owns the live GameState (profile progress) and the rules that change it:
## flags, scrap, anchors, death/respawn, collectibles. Rooms and UI call in
## here instead of touching the state dictionary directly.

const CATALOG := preload("res://data/catalog.tres")
const WORLD_MAP := preload("res://data/world/world_map.tres")
const START_ROOM := "res://world/rooms/lowlight/Relay.tscn"
const START_ENTRY := &"start"
## How a New Game begins (campaign vs legacy slice start, D-063).
const ONBOARDING := preload("res://data/world/onboarding.tres")

## Session abilities (Movement/Combat Lab toggles and world unlocks share this).
var abilities: PlayerAbilities = PlayerAbilities.new()
var state: GameState = GameState.new()
var profile_id: int = 1
var catalog: ItemCatalog = CATALOG
var world_map: WorldMapData = WORLD_MAP
## Overridable so tests can run a campaign start without touching data.
var onboarding: OnboardingConfig = ONBOARDING
var quests: QuestTracker
## M8 character arcs (D-117): enters arc stages from flags, sibling of quests.
var arcs: ArcTracker
## D-147: while Challenges owns a sandbox state, saves write this (the
## untouched profile), never the sandbox.
var held_profile: GameState = null
## M9: set by Challenges around sandbox swaps so the leaving room never writes
## its player into the wrong GameState. Only Challenges sets or clears it.
var suppress_leave_capture: bool = false
## M9 session entry (T11 generous checkpoints fills the logic): the first
## room entry of this play session. Cleared on new_game and load_game.
var _session_entry_room: String = ""
var _session_entry_id: StringName = &""

## D-154: a flag set whenever its source flag holds (derived flag -> source).
## Retroactive for old saves (load_game) and live (set_flag).
const DERIVED_FLAGS := {"null_open": "act1_complete"}


func _ready() -> void:
	quests = QuestTracker.new()
	quests.name = "Quests"
	add_child(quests)
	arcs = ArcTracker.new()
	arcs.name = "Arcs"
	add_child(arcs)
	# count:secrets (arcs, journal) needs SliceStats.totals(), which
	# instantiates every district room once per session: pay that at boot
	# (the title), never on the first pickup or talk that reads it.
	_warm_slice_stats.call_deferred()


func _warm_slice_stats() -> void:
	SliceStats.totals()


func _process(delta: float) -> void:
	if not get_tree().paused:
		state.play_time_sec += delta


func set_ability(ability: StringName, unlocked: bool) -> void:
	if not ability in abilities:
		push_error("Unknown ability: %s" % ability)
		return
	abilities.set(ability, unlocked)
	state.abilities[String(ability)] = unlocked


# --- Profile lifecycle -----------------------------------------------------------

func new_game() -> void:
	state = GameState.new()
	abilities = PlayerAbilities.new()
	_session_entry_room = ""
	_session_entry_id = &""
	EventBus.game_state_reset.emit()


## New Game from the title (bible §42): the campaign start once the Undercity
## is live (unarmed, Core readout hidden), otherwise exactly new_game().
func start_campaign() -> void:
	new_game()
	# M9: only a title New Game counts for campaign IGT bests (both modes).
	state.igt_complete = true
	if not onboarding.enforce:
		return
	state.owned_weapons.assign(onboarding.start_owned_weapons)
	state.melee_weapon = onboarding.start_melee
	state.ranged_weapon = onboarding.start_ranged
	for f: String in onboarding.start_flags:
		set_flag(f, onboarding.start_flags[f])


func campaign_start_room() -> String:
	return onboarding.campaign_start_room if onboarding.enforce else START_ROOM


func campaign_start_entry() -> StringName:
	return onboarding.campaign_start_entry if onboarding.enforce else START_ENTRY


func load_game(p_profile: int = 1) -> bool:
	var data := SaveManager.load_profile(p_profile)
	if data.is_empty():
		return false
	profile_id = p_profile
	state = GameState.from_dict(data)
	# M8 load derivation (the only one): a pre-M8 save that already passed the
	# Act I end has slice_end_seen but no act1_complete. Derive it before
	# game_state_reset so the hub, arcs and music see the finished act. No
	# schema bump: flags need none (D-087/D-090).
	if state.flags.get("slice_end_seen", false) and not state.flags.get("act1_complete", false):
		state.flags["act1_complete"] = true
	# M9 derived flags (D-154): null_open follows act1_complete, also for
	# saves from before M9. Before game_state_reset, like the line above.
	for derived: String in DERIVED_FLAGS:
		if state.flags.get(DERIVED_FLAGS[derived], false) and not state.flags.get(derived, false):
			state.flags[derived] = true
	_session_entry_room = ""
	_session_entry_id = &""
	abilities = PlayerAbilities.new()
	for key: String in state.abilities:
		if key in abilities:
			abilities.set(key, bool(state.abilities[key]))
	EventBus.game_state_reset.emit()
	return true


func save_game() -> Error:
	return SaveManager.save_profile(profile_id, (held_profile if held_profile != null else state).to_dict())


func has_save(p_profile: int = 1) -> bool:
	return not SaveManager.load_profile(p_profile).is_empty()


# --- Player <-> state bridge -----------------------------------------------------------

## Pushes profile progress into a freshly spawned player (world rooms only).
func apply_to_player(player: Player) -> void:
	player.abilities = abilities
	var combat := player.combat
	combat.set_loadout(catalog.weapon(state.melee_weapon), catalog.weapon(state.ranged_weapon))
	combat.health = combat.config.max_health if state.health < 0 else clampi(state.health, 1, combat.config.max_health)
	combat.injectors = combat.injector_capacity() if state.injectors < 0 else state.injectors
	var reactor := player.reactor
	reactor.charge = reactor.config.start_charge if state.reactor_charge < 0.0 else state.reactor_charge


## Pulls live values back before the room is freed.
func capture_from_player(player: Player) -> void:
	if player.combat.dead:
		return
	state.health = player.combat.health
	state.injectors = player.combat.injectors
	state.reactor_charge = player.reactor.charge


# --- Flags ------------------------------------------------------------------------

func set_flag(id: String, value: Variant = true) -> void:
	# Skip equal numbers (a JSON load turns 2 into 2.0; re-setting it must not
	# re-run every flag listener) and equal same-typed values. Never compare
	# across bool/number with == (4.3 raises on int == bool and aborts the
	# caller); a bool<->number change is a real change and emits.
	var old: Variant = state.flags.get(id)
	var num := func(v: Variant) -> bool: return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
	if (num.call(old) and num.call(value) and float(old) == float(value)) or (typeof(old) == typeof(value) and old == value):
		return
	state.flags[id] = value
	EventBus.flag_changed.emit(id, value)
	# D-154: a source flag turning on sets its derived flags.
	if not bool(value):
		return
	for derived: String in DERIVED_FLAGS:
		if DERIVED_FLAGS[derived] == id and not has_flag(derived):
			set_flag(derived)


func has_flag(id: String) -> bool:
	return bool(state.flags.get(id, false))


func flag_int(id: String) -> int:
	return int(state.flags.get(id, 0))


## Small condition language shared by map markers, world-state switches and
## the M8 story data: "flag:x", "ability:dash", "collected:id",
## "atleast:flag:n" (int flags such as talk counts), "count:<metric>:n"
## (fragments, shards, circuits, secrets; see count_metric), "" (always true);
## prefix "!" to negate. One grammar, no AND/OR (D-119): a rule that needs
## several conditions lists them. Keeps world consequences in data instead of
## one-off scripts.
func check_condition(expr: String) -> bool:
	if expr == "":
		return true
	if expr.begins_with("!"):
		return not check_condition(expr.substr(1))
	var kind := expr.get_slice(":", 0)
	var arg := expr.get_slice(":", 1)
	match kind:
		"flag":
			return has_flag(arg)
		"ability":
			return arg in abilities and bool(abilities.get(arg))
		"collected":
			return is_collected(arg)
		"atleast":
			return flag_int(arg) >= int(expr.get_slice(":", 2))
		"count":
			return count_metric(arg) >= int(expr.get_slice(":", 2))
	push_warning("Game.check_condition: unknown condition '%s'" % expr)
	return false


## Progress counts for "count:<metric>:n" conditions. An unknown metric warns
## and returns -1, so the condition is false (the validator also rejects it).
func count_metric(name: String) -> int:
	match name:
		"fragments":
			return state.memory_fragments.size()
		"shards":
			return state.core_shards
		"circuits":
			return state.owned_circuits.size()
		"secrets":
			return SliceStats.secrets_found()
	push_warning("Game.count_metric: unknown metric '%s'" % name)
	return -1


func all_flags(ids: PackedStringArray) -> bool:
	for id in ids:
		if not has_flag(id):
			return false
	return true


# --- Currency & collectibles --------------------------------------------------------

func add_scrap(amount: int) -> void:
	if amount <= 0:
		return
	state.scrap_unbanked += amount
	EventBus.scrap_changed.emit(state.total_scrap())


# --- Circuits (bible §11) ------------------------------------------------------------

func core_capacity() -> int:
	return catalog.base_core_capacity + state.core_shards


func capacity_used() -> int:
	var used := 0
	for id in state.equipped_circuits:
		var c := catalog.circuit(id) as CircuitData
		if c:
			used += c.cost
	return used


func can_equip(id: String) -> bool:
	var c := catalog.circuit(id) as CircuitData
	return c != null and state.owned_circuits.has(id) and not state.equipped_circuits.has(id) \
		and capacity_used() + c.cost <= core_capacity()


func toggle_circuit(id: String) -> bool:
	if state.equipped_circuits.has(id):
		state.equipped_circuits.erase(id)
	elif can_equip(id):
		state.equipped_circuits.append(id)
	else:
		return false
	EventBus.loadout_changed.emit()
	return true


## Product of equipped Circuits' multipliers for a stat (1.0 if none).
func circuit_mult(stat: StringName) -> float:
	var m := 1.0
	for id in state.equipped_circuits:
		var c := catalog.circuit(id) as CircuitData
		if c:
			m *= float(c.multipliers.get(stat, 1.0))
	return m


## Sum of equipped Circuits' values for a stat (0.0 if none).
func circuit_value(stat: StringName) -> float:
	var v := 0.0
	for id in state.equipped_circuits:
		var c := catalog.circuit(id) as CircuitData
		if c:
			v += float(c.values.get(stat, 0.0))
	return v


## Extra injector charges bought in shops. Each shop keeps its own upgrade
## flag (Mara's Spare Injector, Iko's Bootleg Injector) so ShopMenu.is_owned
## can mark each item owned independently; the bonuses stack.
func injector_bonus() -> int:
	return flag_int("injector_upgrades") + flag_int("injector_upgrades_bootleg")


func equip_weapon(id: String) -> void:
	var w := catalog.weapon(id)
	if w == null or not state.owned_weapons.has(id):
		return
	if w.kind == WeaponData.Kind.MELEE:
		state.melee_weapon = id
	else:
		state.ranged_weapon = id
	EventBus.loadout_changed.emit()


func scrap_multiplier() -> float:
	return circuit_mult(&"scrap_gain")


func grant_circuit(id: String) -> void:
	if id == "" or state.owned_circuits.has(id):
		return
	state.owned_circuits.append(id)
	var c := catalog.circuit(id)
	EventBus.hint_requested.emit("CIRCUIT ACQUIRED  —  %s" % (c.display_name if c else id), 3.0)
	EventBus.circuit_granted.emit(id)


## The only source of the "WEAPON ACQUIRED" banner. A weapon found while its
## slot is empty (the unarmed campaign start) is equipped on the spot, so the
## live player can use it immediately; a full slot is left as the player set it.
func grant_weapon(id: String) -> void:
	if id == "" or state.owned_weapons.has(id):
		return
	state.owned_weapons.append(id)
	var w := catalog.weapon(id)
	if w:
		var melee := w.kind == WeaponData.Kind.MELEE
		if melee and state.melee_weapon == "":
			state.melee_weapon = id
			EventBus.loadout_changed.emit()
		elif not melee and state.ranged_weapon == "":
			state.ranged_weapon = id
			EventBus.loadout_changed.emit()
	EventBus.hint_requested.emit("WEAPON ACQUIRED  —  %s" % (w.display_name if w else id), 3.0)
	EventBus.weapon_granted.emit(id)


## Applies a finished conversation's effects (flags, gifts, follow-up menu).
## `choice` is the index of the DialogueChoice picked in the box (-1 = none,
## so every pre-M8 caller is unchanged); its flags apply with the rest.
func apply_dialogue(d: DialogueData, choice: int = -1) -> void:
	for f in d.set_flags:
		set_flag(f)
	if choice >= 0 and choice < d.choices.size():
		for f in d.choices[choice].set_flags:
			set_flag(f)
	add_scrap(d.give_scrap)
	grant_circuit(d.give_circuit)
	grant_weapon(d.give_weapon)
	if d.open_menu != &"":
		EventBus.menu_requested.emit(d.open_menu)


func is_collected(id: String) -> bool:
	return state.collected.has(id)


func mark_collected(id: String) -> void:
	state.collected[id] = true


# --- Anchors, death and respawn -------------------------------------------------------

## Resting: bank scrap, set the respawn point, save. Health/injector/core refill
## is applied to the live player by the Anchor itself.
func rest_at_anchor(room_path: String, anchor_id: String) -> void:
	var key := "%s|%s" % [room_path, anchor_id]
	if not state.anchors_rested.has(key):
		state.anchors_rested.append(key)
	state.scrap_banked += state.scrap_unbanked
	state.scrap_unbanked = 0
	state.last_anchor_room = room_path
	state.last_anchor_id = anchor_id
	state.health = -1
	state.injectors = -1
	state.reactor_charge = -1.0
	set_flag("emergency_loop_spent", false)
	EventBus.scrap_changed.emit(state.total_scrap())
	save_game()


## Called when Rook dies in a world room. Drops unbanked scrap as a cache.
func on_player_death(room_path: String, at: Vector2) -> void:
	state.deaths += 1
	if Settings.currency_loss and state.scrap_unbanked > 0:
		state.dropped_scrap = {"room": room_path, "x": at.x, "y": at.y, "amount": state.scrap_unbanked}
		state.scrap_unbanked = 0
	state.health = -1
	state.injectors = -1
	state.reactor_charge = -1.0
	EventBus.scrap_changed.emit(state.total_scrap())


func recover_dropped_scrap() -> int:
	var amount := int(state.dropped_scrap.get("amount", 0))
	state.dropped_scrap = {}
	add_scrap(amount)
	return amount


## Pre-Anchor respawn (D-063): until the first rest, the last room entry (or
## mid-room EntryCheckpoint) is the respawn point, so an early death never
## sends a new player back to the title start. Ignored once an Anchor is set.
func note_room_entry(path: String, entry: StringName) -> void:
	if state.last_anchor_room != "":
		return
	state.last_entry_room = path
	state.last_entry_id = String(entry)


## Anchor first, then the pre-Anchor entry, then the slice start.
func respawn_room() -> String:
	return respawn_room_for(state)


func respawn_entry() -> StringName:
	return respawn_entry_for(state)


## The same rule for any state (the title peeks at a save without loading it).
func respawn_room_for(s: GameState) -> String:
	if s.last_anchor_room != "":
		return s.last_anchor_room
	return s.last_entry_room if s.last_entry_room != "" else START_ROOM


func respawn_entry_for(s: GameState) -> StringName:
	if s.last_anchor_room != "":
		return StringName(s.last_anchor_id) if s.last_anchor_id != "" else START_ENTRY
	return StringName(s.last_entry_id) if s.last_entry_room != "" else START_ENTRY


# --- Map and transit (bible §20, M5) ----------------------------------------------------

## Called by the current room as Rook moves: clears fog around him and sets
## "map_charted_<district>" once enough of a district has been explored.
func map_reveal(room_path: String, local_pos: Vector2) -> void:
	if MapProgress.reveal(state, world_map, room_path, local_pos) == 0:
		return
	var room := world_map.room(room_path.get_file().get_basename())
	if room == null:
		return
	var flag := "map_charted_%s" % room.district
	if not has_flag(flag) and MapProgress.district_ratio(state, world_map, room.district) >= world_map.threshold_for(room.district):
		set_flag(flag)


## Toggles a player pin near (room, pos): removes one within `radius`,
## otherwise adds one if under the limit. Returns true if a pin now exists.
func toggle_pin(room_id: String, pos: Vector2, radius: float = 48.0) -> bool:
	for i in state.map_pins.size():
		var p: Dictionary = state.map_pins[i]
		if p["room"] == room_id and Vector2(float(p["x"]), float(p["y"])).distance_to(pos) <= radius:
			state.map_pins.remove_at(i)
			EventBus.map_pins_changed.emit()
			return false
	if state.map_pins.size() >= world_map.max_pins:
		return false
	state.map_pins.append({"room": room_id, "x": pos.x, "y": pos.y})
	EventBus.map_pins_changed.emit()
	return true


## Transit (bible §13 Nix, §7 Anchors "later fast travel"): once the pass is
## owned, any Anchor rested at is a destination from any other Anchor.
func transit_unlocked() -> bool:
	return has_flag("transit_pass")


func transit_destinations(exclude_room: String = "", exclude_id: String = "") -> Array[String]:
	var out: Array[String] = []
	for key in state.anchors_rested:
		if key != "%s|%s" % [exclude_room, exclude_id]:
			out.append(key)
	return out


## Travel to a rested Anchor: it becomes the respawn point (you rested there
## on arrival), then the room loads at that Anchor's spawn.
func travel_to(key: String) -> void:
	var room := key.get_slice("|", 0)
	var anchor := key.get_slice("|", 1)
	var from := "%s|%s" % [state.last_anchor_room, state.last_anchor_id]
	rest_at_anchor(room, anchor)
	EventBus.fast_traveled.emit(from, key)
	SceneRouter.transition_to(room, StringName(anchor))

