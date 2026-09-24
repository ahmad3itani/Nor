extends Node
## Owns the live GameState (profile progress) and the rules that change it:
## flags, scrap, anchors, death/respawn, collectibles. Rooms and UI call in
## here instead of touching the state dictionary directly.

const CATALOG := preload("res://data/catalog.tres")
const START_ROOM := "res://world/rooms/lowlight/Relay.tscn"
const START_ENTRY := &"start"

## Session abilities (Movement/Combat Lab toggles and world unlocks share this).
var abilities: PlayerAbilities = PlayerAbilities.new()
var state: GameState = GameState.new()
var profile_id: int = 1
var catalog: ItemCatalog = CATALOG
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
	combat.injectors = combat.config.injector_max if state.injectors < 0 else state.injectors
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


## Circuit stat multiplier (1.0 when no equipped Circuit touches the stat).
func circuit_mult(stat: StringName) -> float:
	return 1.0


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
