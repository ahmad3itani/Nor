extends Node
## Owns the live GameState (profile progress) and the rules that change it:
## flags, scrap, anchors, death/respawn, collectibles. Rooms and UI call in
## here instead of touching the state dictionary directly.

const CATALOG := preload("res://data/catalog.tres")
const WORLD_MAP := preload("res://data/world/world_map.tres")
const START_ROOM := "res://world/rooms/lowlight/Relay.tscn"
const START_ENTRY := &"start"

## Session abilities (Movement/Combat Lab toggles and world unlocks share this).
var abilities: PlayerAbilities = PlayerAbilities.new()
var state: GameState = GameState.new()
var profile_id: int = 1
var catalog: ItemCatalog = CATALOG
var world_map: WorldMapData = WORLD_MAP
var quests: QuestTracker


func _ready() -> void:
	quests = QuestTracker.new()
	quests.name = "Quests"
	add_child(quests)


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
	EventBus.game_state_reset.emit()


func load_game(p_profile: int = 1) -> bool:
	var data := SaveManager.load_profile(p_profile)
	if data.is_empty():
		return false
	profile_id = p_profile
	state = GameState.from_dict(data)
	abilities = PlayerAbilities.new()
	for key: String in state.abilities:
		if key in abilities:
			abilities.set(key, bool(state.abilities[key]))
	EventBus.game_state_reset.emit()
	return true


func save_game() -> Error:
	return SaveManager.save_profile(profile_id, state.to_dict())


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
	if state.flags.get(id) == value:
		return
	state.flags[id] = value
	EventBus.flag_changed.emit(id, value)


func has_flag(id: String) -> bool:
	return bool(state.flags.get(id, false))


func flag_int(id: String) -> int:
	return int(state.flags.get(id, 0))


## Small condition language shared by map markers and world-state switches:
## "flag:x", "ability:dash", "collected:id", "atleast:flag:n" (int flags such
## as talk counts), "" (always true); prefix "!" to negate. Keeps world consequences in data instead of one-off scripts.
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
	push_warning("Game.check_condition: unknown condition '%s'" % expr)
	return false


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


func injector_bonus() -> int:
	return flag_int("injector_upgrades")


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


func grant_weapon(id: String) -> void:
	if id == "" or state.owned_weapons.has(id):
		return
	state.owned_weapons.append(id)
	var w := catalog.weapon(id)
	EventBus.hint_requested.emit("WEAPON ACQUIRED  —  %s" % (w.display_name if w else id), 3.0)
	EventBus.weapon_granted.emit(id)


## Applies a finished conversation's effects (flags, gifts, follow-up menu).
func apply_dialogue(d: DialogueData) -> void:
	for f in d.set_flags:
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


func respawn_room() -> String:
	return state.last_anchor_room if state.last_anchor_room != "" else START_ROOM


func respawn_entry() -> StringName:
	return StringName(state.last_anchor_id) if state.last_anchor_id != "" else START_ENTRY


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
	if not has_flag(flag) and MapProgress.district_ratio(state, world_map, room.district) >= world_map.charted_threshold:
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

