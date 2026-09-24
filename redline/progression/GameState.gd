class_name GameState
extends RefCounted
## Everything a save profile remembers (bible §29): progress, currencies,
## loadout, flags, collectibles and where to respawn. Rooms and player
## components read/write this; SaveManager serializes it via to_dict().

const DEFAULT_MELEE := "pulse_blade"
const DEFAULT_RANGED := "service_pistol"

## Health pips carried between rooms. -1 = full.
var health: int = -1
## Healing injectors currently held. -1 = full.
var injectors: int = -1
## Core charge carried between rooms. -1 = config start value.
var reactor_charge: float = -1.0

## Scrap is "banked" when resting at an Anchor. Unbanked scrap drops on death
## as a recoverable cache (bible §7) unless currency loss is disabled.
var scrap_banked: int = 0
var scrap_unbanked: int = 0
## {"room": path, "x": float, "y": float, "amount": int} or empty.
var dropped_scrap: Dictionary = {}

var core_shards: int = 0
var memory_fragments: Array[String] = []
## Persistent one-shot things already taken/broken/triggered, by unique id.
var collected: Dictionary = {}
## Story/quest/world flags (bible §19). Values are bool or int.
var flags: Dictionary = {}

var abilities: Dictionary = {}
var owned_weapons: Array[String] = [DEFAULT_MELEE, DEFAULT_RANGED]
var melee_weapon: String = DEFAULT_MELEE
var ranged_weapon: String = DEFAULT_RANGED
var owned_circuits: Array[String] = []
var equipped_circuits: Array[String] = []

var last_anchor_room: String = ""
var last_anchor_id: String = ""
var visited_rooms: Array[String] = []
var play_time_sec: float = 0.0
var deaths: int = 0


func total_scrap() -> int:
	return scrap_banked + scrap_unbanked


## Spend from banked first, then unbanked. Returns false if unaffordable.
func spend_scrap(amount: int) -> bool:
	if total_scrap() < amount:
		return false
	var from_banked := mini(amount, scrap_banked)
	scrap_banked -= from_banked
	scrap_unbanked -= amount - from_banked
	return true


func to_dict() -> Dictionary:
	return {
		"health": health,
		"injectors": injectors,
		"reactor_charge": reactor_charge,
		"scrap_banked": scrap_banked,
		"scrap_unbanked": scrap_unbanked,
		"dropped_scrap": dropped_scrap.duplicate(),
		"core_shards": core_shards,
		"memory_fragments": memory_fragments.duplicate(),
		"collected": collected.duplicate(),
		"flags": flags.duplicate(),
		"abilities": abilities.duplicate(),
		"owned_weapons": owned_weapons.duplicate(),
		"melee_weapon": melee_weapon,
		"ranged_weapon": ranged_weapon,
		"owned_circuits": owned_circuits.duplicate(),
		"equipped_circuits": equipped_circuits.duplicate(),
		"last_anchor_room": last_anchor_room,
		"last_anchor_id": last_anchor_id,
		"visited_rooms": visited_rooms.duplicate(),
		"play_time_sec": play_time_sec,
		"deaths": deaths,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.health = int(d.get("health", -1))
	s.injectors = int(d.get("injectors", -1))
	s.reactor_charge = float(d.get("reactor_charge", -1.0))
	s.scrap_banked = int(d.get("scrap_banked", 0))
	s.scrap_unbanked = int(d.get("scrap_unbanked", 0))
	s.dropped_scrap = d.get("dropped_scrap", {})
	s.core_shards = int(d.get("core_shards", 0))
	s.memory_fragments.assign(d.get("memory_fragments", []))
	s.collected = d.get("collected", {})
	s.flags = d.get("flags", {})
	s.abilities = d.get("abilities", {})
	s.owned_weapons.assign(d.get("owned_weapons", [DEFAULT_MELEE, DEFAULT_RANGED]))
	s.melee_weapon = str(d.get("melee_weapon", DEFAULT_MELEE))
	s.ranged_weapon = str(d.get("ranged_weapon", DEFAULT_RANGED))
	s.owned_circuits.assign(d.get("owned_circuits", []))
	s.equipped_circuits.assign(d.get("equipped_circuits", []))
	s.last_anchor_room = str(d.get("last_anchor_room", ""))
	s.last_anchor_id = str(d.get("last_anchor_id", ""))
	s.visited_rooms.assign(d.get("visited_rooms", []))
	s.play_time_sec = float(d.get("play_time_sec", 0.0))
	s.deaths = int(d.get("deaths", 0))
	return s
