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
	"res://audio", "res://cinematics", "res://story"]
const ROOM_DIRS: PackedStringArray = ["res://world/rooms", "res://world/rooms/lowlight", "res://world/rooms/undercity"]
## District room folders only (no labs/backdrops in res://world/rooms): what
## SliceStats, the playtest report and the world tests iterate.
const WORLD_ROOM_DIRS: PackedStringArray = ["res://world/rooms/lowlight", "res://world/rooms/undercity"]
## Menu ids MenuHost knows besides shop_<id>.
const MENU_IDS: PackedStringArray = ["loadout", "pause", "journal", "settings", "slice_end", "moment", "survey", "map", "dev"]
## Flags set by code rather than data (kept here so the flag lint knows them).
## act1_complete: Game.load_game derives it for pre-M8 saves that passed the
## Act I end (the act1_close sequence also sets it in data).
const CODE_FLAGS: PackedStringArray = ["emergency_loop_spent", "hint_first_flow", "slice_end_seen", "core_hud_hidden",
	"act1_complete"]
## Flags only there for bookkeeping; never "unused".
## M8 story bookkeeping (seen sequences, memories viewed, endings seen, arc
## stages/beats, threads) is read by code (trackers, journal, dev tools).
const BOOKKEEPING_PREFIXES: PackedStringArray = ["hint_", "talks_", "met_", "seen_seq_", "mem_seen_", "mem_detail_",
	"ending_seen_", "arc_", "arcbeat_", "thread_"]
## Metrics a `count:<metric>:<n>` condition may name (Game.count_metric).
const COUNT_METRICS: PackedStringArray = ["fragments", "shards", "circuits", "secrets"]
## Bible §18: the four endings, exactly (D-126).
const ENDING_IDS: PackedStringArray = ["crown", "redline", "release", "sever"]
## Where future flags may be read: ending data (and their own declaration).
const FUTURE_READERS_DIR := "res://data/endings/"

var errors: PackedStringArray = []
var warnings: PackedStringArray = []
## room id -> [{id, kind}] for the collectible tracker.
var collectibles: Dictionary = {}
var produced: Dictionary = {}  # flag -> file name of the first producer
var consumed: Dictionary = {}  # flag -> file name of the first consumer
## flag -> Array[String] of the full res:// paths of every producer / consumer,
## in registration order (cross-area rules need the directory, not just the
## first file name).
var producers: Dictionary = {}
var consumers: Dictionary = {}
var stats: Dictionary = {"files": 0, "rooms": 0, "resources": 0}
## M8 story registry, filled by check_resource() and the room pass, read by
## validate_story() and the report: kind -> {res:// path -> resource}. Tests
## feed in-memory resources through check_resource with made-up paths.
var story: Dictionary = {"fragments": {}, "scenes": {}, "sequences": {}, "endings": {}, "arcs": {}, "acts": {},
	"future": {}, "lint": {}, "text": {}}
## Sequence id -> ["<room>: <referrer kind>", ...] (SequenceTrigger, BossArena
## intro, SliceEndTrigger, ActData close).
var sequence_refs: Dictionary = {}
## Fragment ids placed as Collectibles in rooms -> room id.
var placed_fragments: Dictionary = {}
## Room text shown in play: [path, what, text] (HintTrigger lines).
var room_text: Array = []
var _require_on_map: bool = true


func run() -> ContentValidator:
	scan_references()
	validate_resources()
	validate_rooms()
	validate_story()
	validate_flags()
	var art := ArtValidator.new().run()
	errors.append_array(art.errors)
	warnings.append_array(art.warnings)
	return self


## Test API: validate one room scene plus the flag graph it builds, without
## the full content pass. Tests read `errors` and `warnings` afterwards.
## require_on_map = false skips the world-map check (test fixtures are never
## on the map).
func check_room(path: String, require_on_map: bool = true) -> ContentValidator:
	var room := _instantiate_room(path, true)
	if room == null:
		return self
	RoomTemplate.expand_all(room)
	_require_on_map = require_on_map
	_check_world_room(room, path, {})
	_require_on_map = true
	room.free()
	validate_flags()
	return self


## Test API: lint one data resource as validate_resources() would (validate(),
## the typed branches, the resource content protocol). Tests pass an in-memory
## resource with a made-up path, then call validate_flags() and read `errors`
## and `warnings`; nothing is written under res://data.
func check_resource(res: Resource, path: String) -> void:
	if res.has_method("validate"):
		for e: String in res.validate():
			errors.append("%s: %s" % [path.get_file(), e])
	if res is DialogueData:
		_check_dialogue(res, path, _catalog())
	elif res is NpcProfile:
		for rule in (res as NpcProfile).rules:
			_consume_list(rule.requires_flags, path)
			_consume_list(rule.forbids_flags, path)
			for c in rule.requires_conditions:
				_consume_condition(c, path)
			if rule.dialogue:
				_check_dialogue(rule.dialogue, path, _catalog())
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
		if q.reward_circuit != "" and _catalog().circuit(q.reward_circuit) == null:
			errors.append("%s: reward circuit '%s' not in catalog" % [path.get_file(), q.reward_circuit])
	elif res is ShopData:
		for item in (res as ShopData).items:
			_consume(item.requires_flag, path)
			match item.kind:
				ShopItem.Kind.CIRCUIT:
					if _catalog().circuit(item.item_id) == null:
						errors.append("%s: circuit '%s' not in catalog" % [path.get_file(), item.item_id])
				ShopItem.Kind.WEAPON:
					if _catalog().weapon(item.item_id) == null:
						errors.append("%s: weapon '%s' not in catalog" % [path.get_file(), item.item_id])
				_:
					_produce(item.upgrade_flag, path)
	_register_story(res, path)
	# Resource content protocol (M8): a separate `if` after the typed
	# branches, so any resource (sequences, arcs, endings, memory scenes,
	# hub music) lints itself without a new branch here.
	if res.has_method("content_flags"):
		_register_flags(res.content_flags(), path)
	if res.has_method("content_check"):
		for e: String in res.content_check():
			if e.begins_with("WARN: "):
				warnings.append("%s: %s" % [path.get_file(), e.trim_prefix("WARN: ")])
			else:
				errors.append("%s: %s" % [path.get_file(), e])


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
	for path in _files("res://data", ["tres"]):
		var res := load(path)
		stats["resources"] += 1
		if res == null:
			errors.append("resource failed to load: %s" % path)
			continue
		check_resource(res, path)
	for d in Game.world_map.districts():
		produced["map_charted_%s" % d] = "Game.map_reveal"


var _catalog_cache: ItemCatalog = null


func _catalog() -> ItemCatalog:
	if _catalog_cache == null:
		_catalog_cache = load("res://data/catalog.tres")
	return _catalog_cache


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
			var room := _instantiate_room(path, false)
			if room == null:
				continue
			RoomTemplate.expand_all(room)
			if room.world_room:
				stats["rooms"] += 1
				_check_world_room(room, path, persistent)
			room.free()


## Loads and instantiates a room scene. A missing scene or a non-Room root
## returns null (the stray node is freed, never orphaned); report = true
## records why as an error.
func _instantiate_room(path: String, report: bool) -> Room:
	var id := path.get_file().get_basename()
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		if report:
			errors.append("room %s: cannot load scene %s" % [id, path])
		return null
	var node := packed.instantiate()
	if node is Room:
		return node as Room
	if report:
		errors.append("room %s: not a Room scene" % id)
	if node != null:
		node.free()
	return null


func _check_world_room(room: Room, path: String, persistent: Dictionary) -> void:
	var id := path.get_file().get_basename()
	var tag := "room %s" % id
	if room.theme == null:
		errors.append("%s: no DistrictTheme" % tag)
	if room.district_name == "" or room.room_name == "":
		errors.append("%s: missing district/room name" % tag)
	if _require_on_map and Game.world_map.room(id) == null:
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
		_note_story_node(n, id, path)
		# Content protocol (M7): any node may lint itself and declare the flags
		# it sets/reads. A separate `if`, not part of the chain above, so a
		# subclass of a handled type (PowerShutter is a Gate) still reports.
		_check_protocol(n, room, tag, path)
	if defaults != 1:
		errors.append("%s: needs exactly one default spawn (has %d)" % [tag, defaults])
	for n in room.find_children("*", "Anchor", true, false):
		if not spawns.has((n as Anchor).anchor_id):
			errors.append("%s: Anchor %s has no spawn marker with the same id" % [tag, (n as Anchor).anchor_id])


## The node content protocol. Binding signatures:
##   func content_errors(room: Node) -> PackedStringArray
##     "WARN: ..." entries become warnings, the rest errors.
##   func content_flags() -> Dictionary
##     {produces: [...], consumes: [...], conditions: [...]}; must not depend
##     on _ready (rooms are validated without entering the tree).
## Messages are tagged "room <id>: <node>: <message>".
##
## The resource content protocol (M8, see check_resource). Binding signatures:
##   func content_flags() -> Dictionary      same shape as the node protocol
##   func content_check() -> PackedStringArray
##     no room argument, so it never collides with a node's content_errors;
##     "WARN: ..." entries become warnings, the rest errors.
## Messages are tagged "<file name>: <message>".
func _check_protocol(n: Node, room: Room, tag: String, path: String) -> void:
	if n.has_method("content_errors"):
		for e: String in n.content_errors(room):
			if e.begins_with("WARN: "):
				warnings.append("%s: %s: %s" % [tag, n.name, e.trim_prefix("WARN: ")])
			else:
				errors.append("%s: %s: %s" % [tag, n.name, e])
	if n.has_method("content_flags"):
		_register_flags(n.content_flags(), path)


## Records a content_flags() dictionary {produces, consumes, conditions}.
func _register_flags(d: Dictionary, path: String) -> void:
	for f in d.get("produces", []):
		_produce(String(f), path)
	for f in d.get("consumes", []):
		_consume(String(f), path)
	for c in d.get("conditions", []):
		_consume_condition(String(c), path)


# --- Story (M8, cross-area) --------------------------------------------------

## Files check_resource saw, by kind, for the cross-area story rules.
func _register_story(res: Resource, path: String) -> void:
	var kind := ""
	if res is MemoryFragmentData:
		kind = "fragments"
	elif res is MemorySceneData:
		kind = "scenes"
	elif res is SequenceData:
		kind = "sequences"
	elif res is EndingData:
		kind = "endings"
	elif res is NpcArc:
		kind = "arcs"
	elif res is ActData:
		kind = "acts"
	elif res is FutureFlagSet:
		kind = "future"
	elif res is KnowledgeLint:
		kind = "lint"
	elif res is NpcProfile or res is DialogueData or res is QuestData or res is MemoryConfig:
		kind = "text"
	if kind != "":
		(story[kind] as Dictionary)[path] = res


## Room nodes the story rules need: who plays which sequence, which
## fragments are placed, and hint text shown in play.
func _note_story_node(n: Node, room_id: String, path: String) -> void:
	var seq: SequenceData = null
	var what := ""
	if n is SequenceTrigger:
		seq = (n as SequenceTrigger).sequence
		what = "SequenceTrigger"
	elif n is BossArena:
		seq = (n as BossArena).intro_sequence
		what = "BossArena intro"
	elif n is SliceEndTrigger:
		seq = (n as SliceEndTrigger).sequence
		what = "SliceEndTrigger"
	elif n is Collectible and (n as Collectible).kind == Collectible.Kind.MEMORY_FRAGMENT and (n as Collectible).fragment:
		placed_fragments[(n as Collectible).fragment.id] = room_id
	elif n is HintTrigger and (n as HintTrigger).text != "":
		room_text.append([path, "hint %s" % (n as HintTrigger).hint_id, (n as HintTrigger).text])
	if seq != null and seq.id != "":
		_push_ref(seq.id, "%s: %s" % [room_id, what])


func _push_ref(seq_id: String, where: String) -> void:
	if not sequence_refs.has(seq_id):
		sequence_refs[seq_id] = []
	if not (sequence_refs[seq_id] as Array).has(where):
		(sequence_refs[seq_id] as Array).append(where)


func _future_set() -> FutureFlagSet:
	for path: String in story["future"]:
		return story["future"][path] as FutureFlagSet
	return FutureFlagSet.shared()


## Cross-area story rules (M8 T10): future flags, orphan sequences, memory
## cross-checks, the ending set, arc threads. Runs after resources and rooms
## registered their flags, before validate_flags().
func validate_story() -> void:
	_check_future_flags()
	_check_sequence_refs()
	_check_memories()
	_check_endings()
	_check_arc_threads()


## A5 §9.2: a future flag is produced only by its declaration and read only
## by ending data. `producers` (not `produced`, which keeps the first file) is
## what catches a second producer.
func _check_future_flags() -> void:
	var future := _future_set()
	var flags := future.flags()
	for f in flags:
		for where: String in producers.get(f, []):
			if where != FutureFlagSet.PATH:
				errors.append("future flag '%s' (Act %d) is set by %s: remove it from future_flags.tres when that act lands" % [f, future.act_of(f), where])
		for where: String in consumers.get(f, []):
			if where != FutureFlagSet.PATH and not where.begins_with(FUTURE_READERS_DIR):
				errors.append("future flag '%s' (Act %d) is read by %s: only data/endings may read it until that act lands" % [f, future.act_of(f), where])
	if not flags.is_empty():
		warnings.append("%d future flags declared (Acts II-V/M9): %s" % [flags.size(), ", ".join(flags)])


## Every sequence a player can meet is played by something: a room trigger,
## a boss arena, the slice end or an act close. theatre_only ones (endings,
## test fixtures) are exempt.
func _check_sequence_refs() -> void:
	for path: String in story["acts"]:
		var a := story["acts"][path] as ActData
		if a.close_sequence and a.close_sequence.id != "":
			_push_ref(a.close_sequence.id, "act %d close" % a.act)
	for path: String in story["sequences"]:
		var seq := story["sequences"][path] as SequenceData
		if not seq.theatre_only and not sequence_refs.has(seq.id):
			warnings.append("%s: sequence %s is played by nothing (no SequenceTrigger, BossArena intro, SliceEndTrigger or act close)" % [path.get_file(), seq.id])


func _check_memories() -> void:
	var scenes: Dictionary = story["scenes"]
	var by_fragment := {}  # fragment id -> scene count
	var scene_ids := {}
	var slots := {}  # "act:slot" -> scene id
	for path: String in scenes:
		var sc := scenes[path] as MemorySceneData
		scene_ids[sc.id] = true
		if sc.source == MemorySceneData.Source.FRAGMENT and sc.fragment:
			by_fragment[sc.fragment.id] = int(by_fragment.get(sc.fragment.id, 0)) + 1
		var key := "%d:%d" % [sc.act, sc.timeline_slot]
		if slots.has(key):
			errors.append("memory %s: timeline_slot %d is already used by %s in act %d" % [sc.id, sc.timeline_slot, slots[key], sc.act])
		else:
			slots[key] = sc.id
	for path: String in story["fragments"]:
		var fr := story["fragments"][path] as MemoryFragmentData
		var n := int(by_fragment.get(fr.id, 0))
		if n != 1:
			errors.append("%s: fragment %s has %d memory scenes (needs exactly one in data/memories)" % [path.get_file(), fr.id, n])
	var ids: Array = placed_fragments.keys()
	ids.sort()
	for fid: String in ids:
		if not by_fragment.has(fid):
			errors.append("room %s: placed fragment %s has no memory scene" % [placed_fragments[fid], fid])
	for where: String in producers.get("memories_remembered", []):
		if not scenes.has(where):
			errors.append("memories_remembered is set by %s: only memory scenes (MemoryLibrary) may count it" % where)
	for f: String in consumers:
		if f.begins_with("mem_seen_") and not scene_ids.has(f.trim_prefix("mem_seen_")):
			errors.append("flag '%s' is read by %s but there is no memory scene '%s'" % [f, consumers[f][0], f.trim_prefix("mem_seen_")])


func _check_endings() -> void:
	var ids := PackedStringArray()
	for path: String in story["endings"]:
		ids.append((story["endings"][path] as EndingData).id)
	ids.sort()
	if ids != ENDING_IDS:
		errors.append("endings must be exactly %s (bible §18), found %s" % [", ".join(ENDING_IDS), ", ".join(ids)])


## Arc threads are the hooks later acts read: each must actually be set.
## (One owning profile per arc is NpcArc.content_check.)
func _check_arc_threads() -> void:
	for path: String in story["arcs"]:
		var a := story["arcs"][path] as NpcArc
		for t in a.threads:
			if not producers.has(t):
				errors.append("%s: arc %s thread %s is never set" % [path.get_file(), a.npc_id, t])


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
	if flag == "":
		return
	if not produced.has(flag):
		produced[flag] = where.get_file()
	if not producers.has(flag):
		var paths: Array[String] = []
		producers[flag] = paths
	producers[flag].append(where)


func _consume(flag: String, where: String) -> void:
	if flag == "":
		return
	if not consumed.has(flag):
		consumed[flag] = where.get_file()
	if not consumers.has(flag):
		var paths: Array[String] = []
		consumers[flag] = paths
	consumers[flag].append(where)


func _consume_list(flags: PackedStringArray, where: String) -> void:
	for f in flags:
		_consume(f, where)


## Conditions use flags via "flag:x" and "atleast:x:n" (see Game.check_condition);
## "count:<metric>:<n>" reads a progress count and consumes no flag.
func _consume_condition(expr: String, where: String) -> void:
	var e := expr.trim_prefix("!")
	if e.begins_with("flag:") or e.begins_with("atleast:"):
		_consume(e.get_slice(":", 1), where)
	elif e.begins_with("count:"):
		if not COUNT_METRICS.has(e.get_slice(":", 1)):
			errors.append("%s: unknown count metric in condition '%s'" % [where.get_file(), expr])
	elif e != "" and not (e.begins_with("ability:") or e.begins_with("collected:")):
		errors.append("%s: unknown condition '%s'" % [where.get_file(), expr])


## The same grammar as _consume_condition, for resources' content_check()
## (one grammar, no AND/OR: D-119). "" is valid (always true).
static func is_valid_condition(expr: String) -> bool:
	var e := expr.trim_prefix("!")
	if e == "":
		return true
	if e.begins_with("count:"):
		return COUNT_METRICS.has(e.get_slice(":", 1)) and e.get_slice_count(":") == 3 and e.get_slice(":", 2).is_valid_int()
	for kind in ["flag:", "atleast:", "ability:", "collected:"]:
		if e.begins_with(kind):
			return e.get_slice(":", 1) != ""
	return false


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
