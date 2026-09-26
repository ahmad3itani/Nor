class_name AchievementRules
extends RefCounted
## Achievement content rules (M9 D1 §5, T07), run by ContentValidator's rule
## seam over every data/achievements/*.tres. The per-file rules PL-1..PL-4
## live in AchievementData.validate()/content_check() (T02); this module
## does the cross-file checks:
##   PL-5   ids, sort values and api() names are unique; api() is
##          storefront-safe (^[A-Z0-9_]{1,128}$)
##   PL-6   stat_id is in data/platform/stats.tres; a COUNTER target is at most
##          PlatformConfig.grind_cap (no grind, D-146); a RANK target is a
##          StyleConfig.rank_names index. Warning (R07.6): a style-rank target
##          with no recorded reachability evidence (STYLE_EVIDENCE)
##   PL-7   completion == true: exactly one count:<metric>:N and N equals the
##          live total (SliceStats.totals(), the Circuit catalog). Any count:
##          above its total is an error (unearnable) even without completion
##   PL-8   atleast:memories_remembered:N <= the MemoryLibrary scene count
##   PL-9   earnable now (D-140): no condition or reveal_when reads a future
##          flag (data/story/future_flags.tres) while `act` <= the highest
##          built act
##   PL-10  no settings coupling (D-144): no AchievementData field and no
##          condition argument names a Settings property (an assist player
##          earns every achievement)
##   PL-15  reveal_when (R07.3, the spoiler guard) is a valid condition and
##          every flag it reads is produced (content or code). The plan calls
##          this "PL-11", but PlatformRules already owns PL-11 (boss stats).
## Report (PL-13): a table of id, category, hidden, conditions, stat and
## whether the achievement is earnable (no PL error of its own).

const DIR := "res://data/achievements"
const CONFIG_PATH := "res://data/platform/platform_config.tres"
const STYLE_PATH := "res://data/style/default_style.tres"
const CATALOG_PATH := "res://data/catalog.tres"
const API_RE := "^[A-Z0-9_]{1,128}$"
const RANK_STAT := &"best_style_rank"
## Style ranks a scripted run is known to reach in Act I content (R07.6):
## rank index -> the test that proves it. Every best_style_rank target not
## listed here is a PL-6 warning, never an error (style never gates, §10).
## Empty until a BossBot/combo fixture reaches the rank in an Act I room or
## pit_style (which feeds the lifetime rank through the R02.3 whitelist).
const STYLE_EVIDENCE := {}
## Category names for the report (AchievementData.Category order).
const CATEGORY_NAMES: PackedStringArray = ["Story", "Exploration", "People", "Mastery"]

## [id, category, hidden, conditions, stat, earnable] of the last run.
static var last_table: Array = []


static func run(v: ContentValidator) -> void:
	var list: Array[AchievementData] = []
	for path in DataDir.list(DIR):
		var a := load(path) as AchievementData
		if a != null:
			list.append(a)
	var r := check_list(list, v)
	v.errors.append_array(r["errors"])
	v.warnings.append_array(r["warnings"])


static func report(_v: ContentValidator) -> String:
	if last_table.is_empty():
		return ""
	var md := PackedStringArray(["## Achievements", "",
		"| id | category | hidden | conditions | stat | earnable |", "|---|---|---|---|---|---|"])
	for row: Array in last_table:
		md.append("| %s | %s | %s | %s | %s | %s |" % row)
	return "\n".join(md)


## Every cross-file rule over `list` (tests pass fixtures). The PL-15 flag
## check reads v.produced, so it only runs on a validator that did the room
## pass (a partial run has no producers to compare against). Returns
## {errors, warnings}; every line is prefixed with its rule id.
static func check_list(list: Array[AchievementData], v: ContentValidator = null) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var bad := {}
	var add := func(rule: String, a: AchievementData, msg: String) -> void:
		errors.append("[%s] %s: %s" % [rule, a.id, msg])
		bad[a.id] = true
	var cat := StatCatalog.shipped()
	var cfg := load(CONFIG_PATH) as PlatformConfig
	var grind_cap := cfg.grind_cap if cfg else 25.0
	var ranks := _rank_count()
	var totals := metric_totals()
	var scenes := MemoryLibrary.all_scenes().size()
	var future := FutureFlagSet.shared().flags()
	var top_act := highest_act()
	var setting_names := settings_properties()
	var api_re := RegEx.create_from_string(API_RE)
	var check_flags := v != null and int(v.stats.get("rooms", 0)) > 0
	var ids := {}
	var sorts := {}
	var apis := {}
	for a in list:
		# PL-5
		if ids.has(a.id):
			add.call("PL-5", a, "id is not unique")
		ids[a.id] = true
		if sorts.has(a.sort):
			add.call("PL-5", a, "sort %d is also used by %s" % [a.sort, sorts[a.sort]])
		else:
			sorts[a.sort] = a.id
		var api := a.api()
		if api_re.search(api) == null:
			add.call("PL-5", a, "api name '%s' is not storefront-safe (%s)" % [api, API_RE])
		if apis.has(api):
			add.call("PL-5", a, "api name '%s' is not unique" % api)
		apis[api] = true
		# PL-6
		if a.stat_id != &"":
			var def := cat.stat(a.stat_id) if cat else null
			if def == null:
				add.call("PL-6", a, "stat '%s' is not in %s" % [a.stat_id, StatCatalog.PATH])
			else:
				if def.kind == StatDef.Kind.COUNTER and a.stat_target > grind_cap:
					add.call("PL-6", a, "COUNTER target %s is over the grind cap %s (D-146)" % [a.stat_target, grind_cap])
				if def.format == StatDef.Format.RANK and int(a.stat_target) >= ranks:
					add.call("PL-6", a, "rank target %d is not a StyleConfig rank (0..%d)" % [int(a.stat_target), ranks - 1])
				if a.stat_scope == AchievementData.Scope.LIFETIME and not def.lifetime:
					add.call("PL-6", a, "stat '%s' is not kept for the lifetime" % a.stat_id)
				if a.stat_scope == AchievementData.Scope.PROFILE and not def.profile:
					add.call("PL-6", a, "stat '%s' is not kept per profile" % a.stat_id)
				if a.stat_id == RANK_STAT and not STYLE_EVIDENCE.has(int(a.stat_target)):
					warnings.append("[PL-6] %s: no scripted run is known to reach style rank %d in Act I (R07.6)" % [a.id, int(a.stat_target)])
		var conds: Array = Array(a.conditions)
		var counts := conds.filter(func(c: String) -> bool: return c.trim_prefix("!").begins_with("count:"))
		# PL-7
		for c: String in counts:
			var metric := c.get_slice(":", 1)
			var n := int(c.get_slice(":", 2))
			if totals.has(metric) and n > int(totals[metric]):
				add.call("PL-7", a, "'%s' is above the %d that exist (unearnable)" % [c, totals[metric]])
		if a.completion:
			if counts.size() != 1:
				add.call("PL-7", a, "a completion achievement needs exactly one count: condition")
			else:
				var c: String = counts[0]
				var metric := c.get_slice(":", 1)
				if totals.has(metric) and int(c.get_slice(":", 2)) != int(totals[metric]):
					add.call("PL-7", a, "'%s' must equal the live total %d (D-146)" % [c, totals[metric]])
		# PL-8
		for c: String in conds:
			if c.begins_with("atleast:%s:" % MemoryLibrary.REMEMBERED_FLAG) and int(c.get_slice(":", 2)) > scenes:
				add.call("PL-8", a, "'%s' is above the %d memory scenes" % [c, scenes])
		# PL-9
		var reads := conds.duplicate()
		if a.reveal_when != "":
			reads.append(a.reveal_when)
		if a.act <= top_act:
			for c: String in reads:
				var f := flag_of(c)
				if f != "" and future.has(f):
					add.call("PL-9", a, "'%s' reads a future flag while Act %d is built (unearnable)" % [c, top_act])
		# PL-10
		for c: String in reads:
			var arg := c.trim_prefix("!").get_slice(":", 1)
			if setting_names.has(arg):
				add.call("PL-10", a, "'%s' names the setting '%s' (D-144)" % [c, arg])
		# PL-15
		if a.reveal_when != "":
			if not ContentValidator.is_valid_condition(a.reveal_when):
				add.call("PL-15", a, "reveal_when '%s' is not a valid condition" % a.reveal_when)
			elif check_flags:
				var f := flag_of(a.reveal_when)
				if f != "" and not v.produced.has(f) and not ContentValidator.CODE_FLAGS.has(f):
					add.call("PL-15", a, "reveal_when reads '%s', which nothing sets" % f)
	# PL-10: the data script itself carries no setting (a field shared with
	# Settings would be a way to read it).
	for p in AchievementData.new().get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and setting_names.has(String(p["name"])):
			errors.append("[PL-10] AchievementData.%s shares a name with a Settings property (D-144)" % p["name"])
	last_table.clear()
	for a in list:
		var stat := "" if a.stat_id == &"" else "%s >= %s%s" % [a.stat_id, a.stat_target,
			" (profile)" if a.stat_scope == AchievementData.Scope.PROFILE else ""]
		last_table.append([a.id, CATEGORY_NAMES[clampi(a.category, 0, CATEGORY_NAMES.size() - 1)],
			"yes" if a.hidden else "no", ", ".join(a.conditions), stat, "no" if bad.has(a.id) else "yes"])
	return {"errors": errors, "warnings": warnings}


## The flag a condition reads ("flag:x", "atleast:x:n", with or without "!"),
## or "".
static func flag_of(expr: String) -> String:
	var e := expr.trim_prefix("!")
	if e.begins_with("flag:") or e.begins_with("atleast:"):
		return e.get_slice(":", 1)
	return ""


## metric -> how many exist: the count: grammar's totals (Game.count_metric).
static func metric_totals() -> Dictionary:
	var t := SliceStats.totals()
	var out := {"secrets": (t["secret_ids"] as Array).size(), "fragments": int(t["fragments"]),
		"shards": int(t["core_shards"])}
	var cat := load(CATALOG_PATH) as ItemCatalog
	if cat != null:
		out["circuits"] = cat.circuits.size()
	return out


## The highest act with data (ActLibrary scans data/story/act<N>.tres).
static func highest_act() -> int:
	var n := 0
	while ActLibrary.act(n + 1) != null:
		n += 1
	return maxi(n, 1)


## Every script variable of the Settings autoload.
static func settings_properties() -> Dictionary:
	var out := {}
	var script := load("res://autoload/Settings.gd") as Script
	if script == null:
		return out
	for p in script.get_script_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[String(p["name"])] = true
	return out


static func _rank_count() -> int:
	var style := load(STYLE_PATH) as StyleConfig
	return style.rank_names.size() if style else 8
