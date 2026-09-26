class_name CrossRules
extends RefCounted
## Cross-area M9 rules (D6 §5.2, T14): the interactions no single area owns.
## Run last by ContentValidator.validate_m9 (RULE_MODULES), after every other
## module registered its producers, consumers and shown text.
##   X-1  id namespaces: achievement, stat, challenge and challenge-stage ids
##        unique within their kind; achievement and stat api names unique
##        ACROSS both (one storefront app would hold them all)
##   X-2  MenuHost.IDS == ContentValidator.MENU_IDS, and every id has its
##        screen (a Main.tscn/Menus node, or the M9 screen script)
##   X-3  every EventBus signal is recorded by Playtest or listed in
##        Playtest.UNRECORDED_SIGNALS with a reason (the M4 rule, mechanical)
##   X-4  no networking, storefront SDK, JavaScriptBridge or OS.shell_open in
##        ANY script under res:// (only tests/fixtures and .godot skipped);
##        comments and string literals are stripped first (§29, §37.7, the
##        local-only rule). build.py PY-NET is the Python side (T05).
##   X-5  raw folder scans (DirAccess.open / get_files_at /
##        get_directories_at) only in ALLOWED_RAW_SCANS: exported builds list
##        .remap names, so content scans go through DataDir (K-M8-22)
##   X-6  every top-level res:// folder with scripts, scenes or resources is
##        in ContentValidator.SCAN_DIRS or IGNORED_DIRS
##   X-7  M9 flag readers (achievement conditions and reveal_when, challenge
##        unlock_when/reveal_when) registered through content_flags(), so
##        the future-flag guard and the dangling-flag lint see them
##   X-8  never shame (§24): the settings catalog's forbidden_words over
##        every M9 string in the catalog (achievements, stats, challenges and
##        medals, Null ranks, NG+, settings, assists, the demo card)
##   X-9  the Act I knowledge lint over achievement title/description/hint,
##        challenge title/description and demo card lines (added through
##        ContentValidator.add_shown_text; the lint's exempt dirs apply)
##   X-10 every flag M9 code sets is in CODE_FLAGS or produced by data

## Top-level folders that hold no game content (D6 §5.2 X-6). locale/ holds
## PO files only (StringRules lints them).
const IGNORED_DIRS: PackedStringArray = ["res://tests", "res://tools", "res://.godot", "res://locale"]
## Scripts allowed a raw DirAccess scan, and why (X-5).
const ALLOWED_RAW_SCANS := {
	"res://progression/DataDir.gd": "the export-safe scanner itself",
	"res://progression/AtomicJson.gd": "user:// tree removal only",
	"res://quests/QuestTracker.gd": "handles .remap names itself",
	"res://playtest/PlaytestAnalyzer.gd": "user:// session folders only",
	"res://progression/EconomyAudit.gd": "tests and the validator only",
	"res://devtools/CaptureTour.gd": "dev tool (user:// captures)",
	"res://devtools/MovementProbe.gd": "dev tool",
	"res://devtools/dev_actions/NgPlusDevActions.gd": "dev tool (user:// save folder)",
}
## Folders whose scripts may scan raw (dev and validator tooling).
const ALLOWED_RAW_DIRS: PackedStringArray = ["res://devtools/content", "res://devtools/capture", "res://devtools/l10n",
	"res://tests"]
const RAW_SCAN_PATTERN := "DirAccess\\.(open|get_files_at|get_directories_at)\\b|\\bget_directories_at\\("
## Banned in code (comments and string literals stripped first, X-4).
const NET_PATTERNS: PackedStringArray = ["\\bSteam\\.", "\\bHTTPRequest\\b", "\\bHTTPClient\\b", "\\bStreamPeerTCP\\b",
	"\\bStreamPeerTLS\\b", "\\bPacketPeerUDP\\b", "\\bWebSocket", "\\bENet", "\\bMultiplayerPeer\\b",
	"\\bJavaScriptBridge\\b", "\\bOS\\.shell_open\\b", "\\bTCPServer\\b", "\\bUDPServer\\b", "\\bUPNP\\b"]
## Needs the string literal ("Steam"), so it runs on the comment-free line.
const NET_SINGLETON := "Engine\\.get_singleton\\(\\s*\"Steam\"\\s*\\)"
## X-4 skips these (fixtures may hold banned text on purpose).
const NET_SKIP_DIRS: PackedStringArray = ["res://tests/fixtures", "res://.godot"]
## Main.tscn/Menus node per non-M9 menu id (X-2).
const MENU_NODES := {"loadout": "LoadoutMenu", "pause": "PauseMenu", "journal": "JournalMenu",
	"settings": "SettingsMenu", "slice_end": "SliceEndMenu", "moment": "MomentMenu", "survey": "SurveyMenu",
	"map": "MapMenu", "dev": "DevConsole"}
const MAIN_SCENE := "res://Main.tscn"
const EVENTBUS_PATH := "res://autoload/EventBus.gd"
const PLAYTEST_PATH := "res://autoload/Playtest.gd"
const POT_PATH := "res://locale/redline.pot"
## Catalog references that count as M9 shown text (X-8).
const M9_TEXT_PREFIXES: PackedStringArray = ["data/achievements/", "data/challenges/", "data/platform/", "data/release/",
	"data/ngplus/", "data/remix/", "data/settings/", "data/accessibility/", "data/input/", "platform/", "challenges/",
	"release/", "accessibility/", "input/", "ui/settings/", "ui/menus/AchievementsMenu.gd", "ui/menus/ChallengesMenu.gd",
	"ui/menus/ChallengeResultMenu.gd", "ui/menus/NgPlusMenu.gd", "ui/menus/AssistSuggestMenu.gd",
	"ui/menus/DemoEndMenu.gd", "ui/menus/SettingsMenu.gd", "ui/hud/RunTimerHud.gd", "ui/hud/AchievementToast.gd",
	"autoload/Challenges.gd", "autoload/Platform.gd"]
## Flags M9 code writes into Game.state (X-10). NG+ reads its three names
## from NgPlusConfig (whose content_flags() produces them).
const M9_CODE_FLAGS: PackedStringArray = ["demo_build", "demo_end_seen", "null_open"]


static func run(v: ContentValidator) -> void:
	for e in id_errors():
		v.errors.append("[X-1] " + e)
	for e in menu_errors(MenuHost.IDS, ContentValidator.MENU_IDS, FileAccess.get_file_as_string(MAIN_SCENE)):
		v.errors.append("[X-2] " + e)
	for e in unrecorded_signals(FileAccess.get_file_as_string(EVENTBUS_PATH), FileAccess.get_file_as_string(PLAYTEST_PATH),
			Playtest.UNRECORDED_SIGNALS):
		v.errors.append("[X-3] " + e)
	for e in network_violations():
		v.errors.append("[X-4] " + e)
	for e in raw_scan_violations():
		v.errors.append("[X-5] " + e)
	for e in unscanned_dirs(top_level_dirs()):
		v.errors.append("[X-6] " + e)
	# X-7, X-9 and X-10 read the flag graph and the room pass; a partial
	# validator (a test probing the rule seam) has neither.
	if int(v.stats.get("rooms", 0)) > 0:
		for e in unregistered_readers(v):
			v.errors.append("[X-7] " + e)
		for e in unproduced_code_flags(v):
			v.errors.append("[X-10] " + e)
		v.warnings.append_array(knowledge_warnings(v, add_m9_shown_text(v)))
	var cat := load(SettingsCatalog.PATH) as SettingsCatalog
	if cat:
		for e in shaming_text(m9_catalog_text(PoFile.load_file(POT_PATH)), cat):
			v.errors.append("[X-8] " + e)


# --- X-1 ------------------------------------------------------------------------------

static func id_errors() -> PackedStringArray:
	var cat := StatCatalog.shipped()
	var stats: Array = cat.stats if cat else []
	return id_errors_for(AchievementLibrary.all(), stats, ChallengeLibrary._load_all())


static func id_errors_for(achievements: Array, stats: Array, challenges: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var apis := {}
	var seen := {}
	for a: AchievementData in achievements:
		_unique(out, seen, "achievement", a.id)
		_unique_api(out, apis, a.api(), "achievement " + a.id)
	for s: StatDef in stats:
		if s != null:
			_unique(out, seen, "stat", String(s.id))
			_unique_api(out, apis, s.api(), "stat %s" % s.id)
	for ch: ChallengeData in challenges:
		_unique(out, seen, "challenge", ch.id)
		var stages := {}
		for st in ch.stages:
			if st != null:
				_unique(out, stages, "stage of %s" % ch.id, st.id)
	return out


static func _unique(out: PackedStringArray, seen: Dictionary, kind: String, id: String) -> void:
	var k := "%s:%s" % [kind, id]
	if seen.has(k):
		out.append("%s id '%s' is not unique" % [kind, id])
	seen[k] = true


static func _unique_api(out: PackedStringArray, apis: Dictionary, api: String, who: String) -> void:
	if apis.has(api):
		out.append("api name '%s' is used by %s and %s (one storefront app holds both kinds)" % [api, apis[api], who])
	else:
		apis[api] = who


# --- X-2 ------------------------------------------------------------------------------

static func menu_errors(host_ids: PackedStringArray, validator_ids: PackedStringArray, main_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in host_ids:
		if not validator_ids.has(id):
			out.append("menu id '%s' is in MenuHost.IDS but not ContentValidator.MENU_IDS" % id)
	for id in validator_ids:
		if not host_ids.has(id):
			out.append("menu id '%s' is in ContentValidator.MENU_IDS but not MenuHost.IDS" % id)
	for id in host_ids:
		if MenuHost.M9_SCREENS.has(StringName(id)):
			var path := "res://ui/menus/%s.gd" % MenuHost.M9_SCREENS[StringName(id)]
			if not ResourceLoader.exists(path):
				out.append("menu id '%s': screen script %s is missing" % [id, path])
		elif not MENU_NODES.has(id):
			out.append("menu id '%s' has no screen (not an M9 screen, no Main.tscn node known)" % id)
		elif not main_text.contains("[node name=\"%s\"" % MENU_NODES[id]) or \
				not main_text.contains("[node name=\"%s\" type=\"CanvasLayer\" parent=\"Menus\"" % MENU_NODES[id]):
			out.append("menu id '%s': Main.tscn has no Menus/%s" % [id, MENU_NODES[id]])
	return out


# --- X-3 ------------------------------------------------------------------------------

## Signals declared in `eventbus_text` that `playtest_text` never connects and
## `unrecorded` does not list (with a non-empty reason).
static func unrecorded_signals(eventbus_text: String, playtest_text: String, unrecorded: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("(?m)^signal\\s+(\\w+)")
	for m in re.search_all(eventbus_text):
		var s := m.get_string(1)
		if playtest_text.contains("EventBus.%s.connect" % s):
			continue
		if not unrecorded.has(s):
			out.append("EventBus.%s is neither recorded by Playtest nor listed in Playtest.UNRECORDED_SIGNALS" % s)
		elif String(unrecorded[s]).strip_edges() == "":
			out.append("Playtest.UNRECORDED_SIGNALS[%s] needs a one-line reason" % s)
	return out


# --- X-4 ------------------------------------------------------------------------------

static func network_violations() -> PackedStringArray:
	var out := PackedStringArray()
	for path in project_scripts(NET_SKIP_DIRS):
		for hit in scan_network(FileAccess.get_file_as_string(path)):
			out.append("%s: %s" % [path, hit])
	return out


## "line N: <pattern>" for every banned symbol in code.
static func scan_network(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var res: Array[RegEx] = []
	for p in NET_PATTERNS:
		res.append(RegEx.create_from_string(p))
	var singleton := RegEx.create_from_string(NET_SINGLETON)
	var lines := text.split("\n")
	for i in lines.size():
		var code := strip_comment(lines[i])
		if singleton.search(code) != null:
			out.append("line %d: %s" % [i + 1, NET_SINGLETON])
			continue
		var bare := strip_strings(code)
		for j in res.size():
			if res[j].search(bare) != null:
				out.append("line %d: %s" % [i + 1, NET_PATTERNS[j]])
				break
	return out


## The line without its comment: everything from the first `#` outside a
## string literal is dropped (the same rule as PlatformRules PL-14).
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


## The line with every "..." / '...' literal emptied (a validator's own
## pattern list, or a test's fixture text, is not a network call).
static func strip_strings(line: String) -> String:
	var out := ""
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
				out += c
		else:
			out += c
			if c == "\"" or c == "'":
				quote = c
		i += 1
	return out


# --- X-5 ------------------------------------------------------------------------------

static func raw_scan_violations() -> PackedStringArray:
	var out := PackedStringArray()
	for path in project_scripts(NET_SKIP_DIRS):
		for hit in scan_raw(path, FileAccess.get_file_as_string(path)):
			out.append(hit)
	return out


static func scan_raw(path: String, text: String) -> PackedStringArray:
	var out := PackedStringArray()
	if ALLOWED_RAW_SCANS.has(path):
		return out
	if _has_prefix(path, ALLOWED_RAW_DIRS, "/"):
		return out
	var re := RegEx.create_from_string(RAW_SCAN_PATTERN)
	var lines := text.split("\n")
	for i in lines.size():
		if re.search(strip_strings(strip_comment(lines[i]))) != null:
			out.append("%s line %d: raw folder scan outside ALLOWED_RAW_SCANS (use DataDir.list / list_scenes)" % [path, i + 1])
	return out


# --- X-6 ------------------------------------------------------------------------------

## Top-level res:// folders that hold .gd, .tscn or .tres files.
static func top_level_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at("res://"):
		if d.begins_with("."):
			continue
		var path := "res://" + d
		if FileAccess.file_exists(path + "/.gdignore"):
			continue
		if not ContentValidator._files(path, ["gd", "tscn", "tres"]).is_empty():
			out.append(path)
	return out


static func unscanned_dirs(dirs: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for d in dirs:
		if not ContentValidator.SCAN_DIRS.has(d) and not IGNORED_DIRS.has(d):
			out.append("%s holds content but is in neither ContentValidator.SCAN_DIRS nor CrossRules.IGNORED_DIRS" % d)
	return out


# --- X-7 ------------------------------------------------------------------------------

## Every flag an achievement or a challenge reads is a registered consumer.
static func unregistered_readers(v: ContentValidator) -> PackedStringArray:
	var out := PackedStringArray()
	for a in AchievementLibrary.all():
		var exprs := Array(a.conditions)
		if a.reveal_when != "":
			exprs.append(a.reveal_when)
		for f in condition_flags(exprs):
			if not v.consumers.has(f):
				out.append("achievement %s reads flag '%s' but no content_flags() registered it" % [a.id, f])
	for ch in ChallengeLibrary._load_all():
		for f in condition_flags([ch.unlock_when, ch.reveal_when]):
			if not v.consumers.has(f):
				out.append("challenge %s reads flag '%s' but no content_flags() registered it" % [ch.id, f])
	return out


## The flag names in Game.check_condition expressions ("flag:x", "!flag:x",
## "int:x>=n"); other kinds read no flag.
static func condition_flags(exprs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for e: String in exprs:
		var s := e.strip_edges().trim_prefix("!")
		if s.begins_with("flag:"):
			out.append(s.trim_prefix("flag:"))
	return out


# --- X-8 ------------------------------------------------------------------------------

## [where, text] for every catalog entry referenced from an M9 area.
static func m9_catalog_text(po: PoFile) -> Array:
	var out: Array = []
	for e: Dictionary in po.entries:
		for r: String in e.get("refs", PackedStringArray()):
			var ref := r.get_slice(":", 0) if not r.contains("::") else r.get_slice("::", 0)
			if _has_prefix(ref, M9_TEXT_PREFIXES):
				out.append([ref, String(e["msgid"])])
				break
	return out


static func shaming_text(texts: Array, cat: SettingsCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Array in texts:
		for w in cat.forbidden_in(String(t[1])):
			out.append("%s: '%s' in \"%s\" (§24: M9 text never shames the player)" % [t[0], w, String(t[1]).left(60)])
	return out


# --- X-9 ------------------------------------------------------------------------------

## Registers the M9 lines the knowledge lint reads and returns them.
static func add_m9_shown_text(v: ContentValidator) -> Array:
	var items: Array = []
	for a in AchievementLibrary.all():
		var p := a.resource_path if a.resource_path != "" else "res://data/achievements/%s.tres" % a.id
		items.append([p, "achievement %s title" % a.id, a.title])
		items.append([p, "achievement %s description" % a.id, a.description])
		if a.hint_when_hidden != "":
			items.append([p, "achievement %s hint" % a.id, a.hint_when_hidden])
	for ch in ChallengeLibrary._load_all():
		var p := ch.resource_path if ch.resource_path != "" else "res://data/challenges/%s.tres" % ch.id
		# A challenge set in an exempt room folder (the Deep Rig) is exempt too.
		if ch.start_room != "" and _lint_exempt(v, ch.start_room):
			continue
		items.append([p, "challenge %s title" % ch.id, ch.title])
		items.append([p, "challenge %s description" % ch.id, ch.description])
	var demo := BuildInfo.config()
	if demo:
		for line: Array in demo.text_lines():
			items.append([BuildInfo.DEMO_CONFIG_PATH, "demo %s" % line[0], String(line[1])])
	for it: Array in items:
		v.add_shown_text(it[0], it[1], it[2])
	return items


static func _lint_exempt(v: ContentValidator, path: String) -> bool:
	var lint := v._knowledge_lint()
	return lint != null and lint.is_exempt(path)


## ContentValidator._check_knowledge ran before the rule modules, so the
## lines added here are linted here, in the same warning format.
static func knowledge_warnings(v: ContentValidator, items: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var lint := v._knowledge_lint()
	if lint == null:
		return out
	for item: Array in items:
		if lint.is_exempt(String(item[0])):
			continue
		for term in lint.hits(String(item[2])):
			var w := "knowledge lint (Act %s): %s: %s: '%s' in \"%s\"" % [ActData.roman(lint.act), String(item[0]).get_file(),
				item[1], term, String(item[2]).replace("\n", " ").left(70)]
			if not out.has(w) and not v.warnings.has(w):
				out.append(w)
	return out


# --- X-10 -----------------------------------------------------------------------------

static func unproduced_code_flags(v: ContentValidator) -> PackedStringArray:
	var out := PackedStringArray()
	var flags := PackedStringArray(M9_CODE_FLAGS)
	var ng := NewGamePlus.config()
	flags.append_array([ng.cycle_flag, ng.remix_flag, ng.keep_dash_flag])
	for f in flags:
		if not ContentValidator.CODE_FLAGS.has(f) and not v.producers.has(f):
			out.append("flag '%s' is set by M9 code but is neither in CODE_FLAGS nor produced by data" % f)
	return out


# --- Shared ---------------------------------------------------------------------------

static func _has_prefix(path: String, prefixes: PackedStringArray, suffix: String = "") -> bool:
	for p in prefixes:
		if path.begins_with(p + suffix):
			return true
	return false


## Every .gd under res:// except the skipped folders.
static func project_scripts(skip: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for path in ContentValidator._files("res://", ["gd"]):
		var p := path.replace("res:///", "res://")
		if _has_prefix(p, skip, "/"):
			continue
		out.append(p)
	return out
