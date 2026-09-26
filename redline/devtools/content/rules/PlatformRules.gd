extends RefCounted
## Platform-services validator rules (M9 D1 §5), run by ContentValidator's
## rule-module seam. Achievement-file rules (PL-1..PL-10, PL-13) are T07's
## AchievementRules; this module owns the stat catalog and the no-network ban.
##
## PL-11  every boss_nohit_* / boss_time_* stat names a BossArena.boss_id found
##        in a district room (the room pass registers "<boss_id>_intro_seen").
## PL-12  StatDef ids unique; api names unique and storefront-safe
##        (^[A-Z0-9_]{1,128}$); DERIVED stats are ones StatsTracker computes.
## PL-14  no network classes or storefront SDK calls under res://platform or in
##        autoload/Platform.gd (D-141). Comments are stripped first, so the
##        adapter-slot notes may name storefront APIs (R02.2).

const STATS_PATH := "res://data/platform/stats.tres"
const API_RE := "^[A-Z0-9_]{1,128}$"
const NET_DIRS: PackedStringArray = ["res://platform"]
const NET_FILES: PackedStringArray = ["res://autoload/Platform.gd"]
## Banned in code (never in comments).
const NET_PATTERNS: PackedStringArray = ["Steam\\.", "HTTPRequest", "HTTPClient", "StreamPeerTCP", "PacketPeerUDP",
	"WebSocketPeer", "\\bWebSocket", "ENetMultiplayerPeer", "\\bENet", "Engine\\.get_singleton\\(\\s*\"Steam\"\\s*\\)"]


static func run(v: ContentValidator) -> void:
	var cat := load(STATS_PATH) as StatCatalog
	if cat == null:
		v.errors.append("[PL-12] %s is missing or not a StatCatalog" % STATS_PATH)
	else:
		for e in stat_errors(cat):
			v.errors.append("[PL-12] " + e)
		# PL-11 reads the room pass; a validator that ran none (a partial run
		# from a test) has no boss ids to compare against.
		if int(v.stats.get("rooms", 0)) > 0:
			for e in boss_stat_errors(cat, world_boss_ids(v)):
				v.errors.append("[PL-11] " + e)
	for e in network_violations():
		v.errors.append("[PL-14] " + e)


## PL-12 on one catalog.
static func stat_errors(cat: StatCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string(API_RE)
	var ids := {}
	var apis := {}
	for s in cat.stats:
		if s == null:
			continue
		if ids.has(s.id):
			out.append("stat id '%s' is not unique" % s.id)
		ids[s.id] = true
		var api := s.api()
		if re.search(api) == null:
			out.append("stat %s: api name '%s' is not storefront-safe (%s)" % [s.id, api, API_RE])
		if apis.has(api):
			out.append("stat %s: api name '%s' is not unique" % [s.id, api])
		apis[api] = true
		if s.kind == StatDef.Kind.DERIVED and not StatsTracker.DERIVED_IDS.has(s.id):
			out.append("stat %s is DERIVED but StatsTracker does not compute it" % s.id)
	return out


## Boss ids of the arenas in the district rooms (not labs or challenge rooms).
static func world_boss_ids(v: ContentValidator) -> PackedStringArray:
	var out := PackedStringArray()
	for flag: String in v.producers:
		if not flag.ends_with("_intro_seen"):
			continue
		for path: String in v.producers[flag]:
			if ContentValidator.WORLD_ROOM_DIRS.has(path.get_base_dir()) and path.ends_with(".tscn"):
				var id := flag.trim_suffix("_intro_seen")
				if not out.has(id):
					out.append(id)
	return out


## PL-11 on one catalog against a list of boss ids.
static func boss_stat_errors(cat: StatCatalog, boss_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for s in cat.stats:
		if s == null:
			continue
		var id := String(s.id)
		for prefix in ["boss_nohit_", "boss_time_"]:
			if id.begins_with(prefix) and not boss_ids.has(id.trim_prefix(prefix)):
				out.append("stat %s: no district room has a BossArena with boss_id '%s'" % [id, id.trim_prefix(prefix)])
	return out


## PL-14 over every platform script.
static func network_violations() -> PackedStringArray:
	var out := PackedStringArray()
	var files := PackedStringArray(NET_FILES)
	for d in NET_DIRS:
		files.append_array(DataDir.list_files(d, "gd"))
	for path in files:
		for hit in scan_source(FileAccess.get_file_as_string(path)):
			out.append("%s: %s" % [path, hit])
	return out


## "line N: <pattern>" for every banned symbol in code (comments stripped).
static func scan_source(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var res: Array[RegEx] = []
	for p in NET_PATTERNS:
		res.append(RegEx.create_from_string(p))
	var lines := text.split("\n")
	for i in lines.size():
		var code := strip_comment(lines[i])
		for j in res.size():
			if res[j].search(code) != null:
				out.append("line %d: %s" % [i + 1, NET_PATTERNS[j]])
				break
	return out


## The line without its comment: everything from the first `#` outside a
## string literal ("..." or '...', with backslash escapes) is dropped, which
## also removes `##` doc comments.
static func strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line
