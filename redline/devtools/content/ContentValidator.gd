class_name ContentValidator
extends RefCounted
## One pass over all game content (bible §34: broken-reference scanner,
## quest/dialogue validator, collectible tracker, room metadata checks).
## Run headless via devtools/content/ValidateContent.tscn, or from tests.
## Errors break the build; warnings are worth a look; `collectibles` is the
## tracker table.

const SCAN_DIRS: PackedStringArray = ["res://autoload", "res://bosses", "res://circuits", "res://combat",
	"res://data", "res://devtools", "res://dialogue", "res://enemies", "res://interactables", "res://player",
	"res://playtest", "res://progression", "res://quests", "res://ui", "res://vfx", "res://weapons", "res://world",
	"res://audio"]
const ROOM_DIRS: PackedStringArray = ["res://world/rooms", "res://world/rooms/lowlight"]
## Menu ids MenuHost knows besides shop_<id>.
const MENU_IDS: PackedStringArray = ["loadout", "pause", "journal", "settings", "slice_end", "moment", "survey", "map"]
## Flags set by code rather than data (kept here so the flag lint knows them).
const CODE_FLAGS: PackedStringArray = ["emergency_loop_spent", "hint_first_flow", "slice_end_seen"]
## Flags only there for bookkeeping; never "unused".
const BOOKKEEPING_PREFIXES: PackedStringArray = ["hint_", "talks_", "met_"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []
## room id -> [{id, kind}] for the collectible tracker.
var collectibles: Dictionary = {}
var produced: Dictionary = {}  # flag -> where
var consumed: Dictionary = {}  # flag -> where
var stats: Dictionary = {"files": 0, "rooms": 0, "resources": 0}


func run() -> ContentValidator:
	scan_references()
	validate_resources()
	validate_rooms()
	validate_flags()
	return self


func ok() -> bool:
	return errors.is_empty()


# --- Broken references ----------------------------------------------------------

func scan_references() -> void:
	for dir in SCAN_DIRS:
		for path in _files(dir, ["tscn", "tres", "gd"]):
			stats["files"] += 1
			for ref in references_in(FileAccess.get_file_as_string(path)):
				if not _exists(ref):
					errors.append("broken reference: %s -> %s" % [path, ref])
	var project := FileAccess.get_file_as_string("res://project.godot")
	for ref in references_in(project):
		if not _exists(ref):
			errors.append("broken reference: project.godot -> %s" % ref)


## Literal res:// paths in a file's text. Format strings ("%s", "{") are
## runtime patterns, not references, and are skipped.
static func references_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var rx := RegEx.create_from_string("\"(res://[^\"]+)\"")
	for m in rx.search_all(text):
		var ref := m.get_string(1)
		if ref.contains("%") or ref.contains("{") or ref.contains("*"):
			continue
		out.append(ref)
	return out


static func _exists(ref: String) -> bool:
	if ref.ends_with("/"):
		return DirAccess.dir_exists_absolute(ref)
	return ResourceLoader.exists(ref) or FileAccess.file_exists(ref) or DirAccess.dir_exists_absolute(ref)


# --- Data resources ---------------------------------------------------------------

func validate_resources() -> void:
	var catalog: ItemCatalog = load("res://data/catalog.tres")
	for path in _files("res://data", ["tres"]):
		var res := load(path)
		stats["resources"] += 1
		if res == null:
			errors.append("resource failed to load: %s" % path)
			continue
		if res.has_method("validate"):
			for e: String in res.validate():
				errors.append("%s: %s" % [path.get_file(), e])
		if res is DialogueData:
			_check_dialogue(res, path, catalog)
		elif res is NpcProfile:
			for rule in (res as NpcProfile).rules:
				_consume_list(rule.requires_flags, path)
				_consume_list(rule.forbids_flags, path)
				for c in rule.requires_conditions:
					_consume_condition(c, path)
				if rule.dialogue:
					_check_dialogue(rule.dialogue, path, catalog)
			produced["talks_%s" % (res as NpcProfile).npc_id] = "NPC.interact"
		elif res is QuestData:
			var q := res as QuestData
			_consume(q.start_flag, path)
			for s in q.stages:
				_consume_list(s.complete_flags, path)
				if s.map_room != "" and Game.world_map.room(s.map_room) == null:
					errors.append("%s: map note room '%s' is not on the world map" % [path.get_file(), s.map_room])
			_produce(q.complete_flag, path)
			for f in q.reward_flags:
				_produce(f, path)
			if q.reward_circuit != "" and catalog.circuit(q.reward_circuit) == null:
				errors.append("%s: reward circuit '%s' not in catalog" % [path.get_file(), q.reward_circuit])
		elif res is ShopData:
			for item in (res as ShopData).items:
				_consume(item.requires_flag, path)
				match item.kind:
					ShopItem.Kind.CIRCUIT:
						if catalog.circuit(item.item_id) == null:
							errors.append("%s: circuit '%s' not in catalog" % [path.get_file(), item.item_id])
					ShopItem.Kind.WEAPON:
						if catalog.weapon(item.item_id) == null:
							errors.append("%s: weapon '%s' not in catalog" % [path.get_file(), item.item_id])
					_:
						_produce(item.upgrade_flag, path)
	for d in Game.world_map.districts():
		produced["map_charted_%s" % d] = "Game.map_reveal"


func _check_dialogue(d: DialogueData, where: String, catalog: ItemCatalog) -> void:
	for f in d.set_flags:
		_produce(f, where)
	if d.give_circuit != "" and catalog.circuit(d.give_circuit) == null:
		errors.append("%s: dialogue %s gives unknown circuit %s" % [where.get_file(), d.id, d.give_circuit])
	if d.give_weapon != "" and catalog.weapon(d.give_weapon) == null:
		errors.append("%s: dialogue %s gives unknown weapon %s" % [where.get_file(), d.id, d.give_weapon])
	var menu := String(d.open_menu)
	if menu != "" and not MENU_IDS.has(menu) and not ResourceLoader.exists("res://data/shops/%s.tres" % menu):
		errors.append("%s: dialogue %s opens unknown menu '%s'" % [where.get_file(), d.id, menu])
	if d.lines.is_empty():
		errors.append("%s: dialogue %s has no lines" % [where.get_file(), d.id])


# --- Rooms ------------------------------------------------------------------------

func validate_rooms() -> void:
	var persistent := {}
	for dir in ROOM_DIRS:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".tscn"):
				continue
			var path := "%s/%s" % [dir, f]
			var room := (load(path) as PackedScene).instantiate() as Room
			if room == null:
				continue
			if room.world_room:
				stats["rooms"] += 1
				_check_world_room(room, path, persistent)
			room.free()


func _check_world_room(room: Room, path: String, persistent: Dictionary) -> void:
	var id := path.get_file().get_basename()
	var tag := "room %s" % id
	if room.theme == null:
		errors.append("%s: no DistrictTheme" % tag)
	if room.district_name == "" or room.room_name == "":
		errors.append("%s: missing district/room name" % tag)
	if Game.world_map.room(id) == null:
		errors.append("%s: not on the world map (data/world/world_map.tres)" % tag)
	var spawns := {}
	var defaults := 0
	collectibles[id] = []
	for n in room.find_children("*", "", true, false):
		if n is SpawnMarker:
			var s := n as SpawnMarker
			if spawns.has(s.spawn_id):
				errors.append("%s: duplicate spawn id %s" % [tag, s.spawn_id])
			spawns[s.spawn_id] = true
			defaults += 1 if s.is_default else 0
		elif n is Anchor:
			pass  # checked after spawns are known
		elif n is Collectible or n is BreakableWall:
			var pid: String = n.persist_id
			if pid == "":
				errors.append("%s: %s without persist_id" % [tag, n.name])
			elif persistent.has(pid):
				errors.append("%s: persist_id '%s' also used in %s" % [tag, pid, persistent[pid]])
			persistent[pid] = id
			var kind: String = "wall" if n is BreakableWall else ["scrap", "fragment", "core_shard"][clampi(int((n as Collectible).kind), 0, 2)]
			(collectibles[id] as Array).append({"id": pid, "kind": kind})
		elif n is HintTrigger:
			var h := n as HintTrigger
			if h.action != &"" and not InputMap.has_action(h.action):
				errors.append("%s: hint '%s' names unknown input action %s" % [tag, h.hint_id, h.action])
			_produce("hint_" + h.hint_id, path)
		elif n is FlagSwitch:
			_produce((n as FlagSwitch).flag_id, path)
		elif n is SignalRepeater:
			_produce((n as SignalRepeater).flag_id, path)
		elif n is AbilityPickup:
			_produce((n as AbilityPickup).flag_id, path)
		elif n is BossArena:
			_produce((n as BossArena).defeated_flag(), path)
			_produce("%s_intro_seen" % (n as BossArena).boss_id, path)
		elif n is Gate:
			_consume((n as Gate).open_flag, path)
		elif n is RoomExit:
			var e := n as RoomExit
			_consume(e.requires_flag, path)
			if not ResourceLoader.exists(e.target_room):
				errors.append("%s: exit %s targets missing room %s" % [tag, e.name, e.target_room])
			elif not WorldMapIndex.room_info(e.target_room)["spawns"].has(String(e.target_entry)):
				errors.append("%s: exit %s targets missing entry %s in %s" % [tag, e.name, e.target_entry, e.target_room.get_file()])
		elif n is MapMarker:
			_consume_condition((n as MapMarker).resolved_when, path)
		elif n is WorldStateSwitch:
			_consume_condition((n as WorldStateSwitch).visible_when, path)
		elif n is Enemy:
			var en := n as Enemy
			if en.data == null:
				errors.append("%s: enemy %s has no data" % [tag, en.name])
	if defaults != 1:
		errors.append("%s: needs exactly one default spawn (has %d)" % [tag, defaults])
	for n in room.find_children("*", "Anchor", true, false):
		if not spawns.has((n as Anchor).anchor_id):
			errors.append("%s: Anchor %s has no spawn marker with the same id" % [tag, (n as Anchor).anchor_id])


# --- Flags (quest/dialogue validator) ------------------------------------------

func validate_flags() -> void:
	for f in CODE_FLAGS:
		produced[f] = "code"
	for f: String in consumed:
		if not produced.has(f):
			errors.append("flag '%s' is required by %s but nothing sets it" % [f, consumed[f]])
	for f: String in produced:
		if consumed.has(f) or CODE_FLAGS.has(f):
			continue
		if Array(BOOKKEEPING_PREFIXES).any(func(p: String) -> bool: return f.begins_with(p)) or f.ends_with("_intro_seen"):
			continue
		warnings.append("flag '%s' is set by %s but nothing in data reads it (code may)" % [f, produced[f]])


func _produce(flag: String, where: String) -> void:
	if flag != "" and not produced.has(flag):
		produced[flag] = where.get_file()


func _consume(flag: String, where: String) -> void:
	if flag != "" and not consumed.has(flag):
		consumed[flag] = where.get_file()


func _consume_list(flags: PackedStringArray, where: String) -> void:
	for f in flags:
		_consume(f, where)


## Conditions use flags via "flag:x" and "atleast:x:n" (see Game.check_condition).
func _consume_condition(expr: String, where: String) -> void:
	var e := expr.trim_prefix("!")
	if e.begins_with("flag:") or e.begins_with("atleast:"):
		_consume(e.get_slice(":", 1), where)
	elif e != "" and not (e.begins_with("ability:") or e.begins_with("collected:")):
		errors.append("%s: unknown condition '%s'" % [where.get_file(), expr])


# --- Report ---------------------------------------------------------------------

func report() -> String:
	var lines: PackedStringArray = ["# Content validation", ""]
	lines.append("Scanned %d files, %d data resources, %d world rooms." % [stats["files"], stats["resources"], stats["rooms"]])
	lines.append("")
	lines.append("## Errors (%d)" % errors.size())
	for e in errors:
		lines.append("- " + e)
	lines.append("")
	lines.append("## Warnings (%d)" % warnings.size())
	for w in warnings:
		lines.append("- " + w)
	lines.append("")
	lines.append("## Collectible tracker")
	lines.append("")
	lines.append("| Room | Fragments | Core Shards | Walls | Scrap stashes | Ids |")
	lines.append("|---|---|---|---|---|---|")
	var ids: Array = collectibles.keys()
	ids.sort()
	for room: String in ids:
		var items: Array = collectibles[room]
		var count := func(k: String) -> int: return items.filter(func(i: Dictionary) -> bool: return i["kind"] == k).size()
		lines.append("| %s | %d | %d | %d | %d | %s |" % [room, count.call("fragment"), count.call("core_shard"), count.call("wall"), count.call("scrap"),
			", ".join(PackedStringArray(items.map(func(i: Dictionary) -> String: return i["id"])))])
	return "\n".join(lines) + "\n"


static func _files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if exts.has(f.get_extension()):
			out.append("%s/%s" % [dir, f])
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_files("%s/%s" % [dir, sub], exts))
	return out
