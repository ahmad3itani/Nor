class_name PlaytestAnalyzer
extends RefCounted
## Turns a folder of PlaytestSession files into the numbers M4 asks for
## (bible §36): deaths, completion time, confusion, favourite mechanics,
## control complaints, performance, plus the §44 success scorecard and a
## per-variant comparison. Pure data in, Dictionary out; `render_markdown`
## and `render_heatmap` are the only presentation.

## Undercity timeline (M7, §42 onboarding pacing): minutes from session
## start to each beat. Keys match what autoload/Playtest.gd actually writes.
const TIMELINE_ITEMS: Array[Dictionary] = [
	{"key": "blade", "label": "Pulse Blade granted"},
	{"key": "dodge", "label": "First dodge"},
	{"key": "composition", "label": "MaintenanceShaft entered (proxy, early by about 2–3 min)"},
	{"key": "secret", "label": "First secret"},
	{"key": "npc", "label": "First NPC (Radio dialogue)"},
	{"key": "pursuit", "label": "FirstPursuit entered"},
	{"key": "first_flow", "label": "First Flow hint (hint_first_flow)"},
	{"key": "core_hud", "label": "Core HUD shown (core_hud_hidden → false)"},
	{"key": "anchor", "label": "First Anchor rest"},
	{"key": "anchor_lift", "label": "Rest at uc_lift"},
	{"key": "boss_start", "label": "Collector Drone fight started"},
	{"key": "boss_defeated", "label": "Collector Drone defeated"},
	{"key": "relay", "label": "Relay reached"},
]
## Rooms the Undercity district will hold. Used when a room is not on the
## world map yet, so continued runs are still classified before it lands.
const UNDERCITY_ROOM_IDS: PackedStringArray = ["Wake", "MedicalRuin", "MaintenanceShaft", "FirstPursuit", "BrokenLift", "EscapeTunnel", "CollectorBay"]
## Legacy sessions (before boss_start carried an id) name bosses by title.
const BOSS_TITLE_IDS: Dictionary = {"WARDEN KRAIL": "warden_krail", "COLLECTOR DRONE": "collector_drone"}
const BOSS_LABELS: Dictionary = {"warden_krail": ["Warden Krail", "him"], "collector_drone": ["Collector Drone", "it"]}
## Exact death-cause labels, checked before the generic "a/b" -> "a: b".
const CAUSE_LABELS: Dictionary = {"unknown/collector_eye_bolt": "Collector eye", "clamp": "Grid clamp", "scanner": "Scanner beam"}

var config: PlaytestConfig
## A campaign run is a "new" session whose first room is this one (tests
## point it elsewhere while the Undercity rooms do not exist).
var timeline_start_room: String = "Wake"
var sessions: Array[PlaytestSession] = []
## attack id -> weapon id, from the item catalog (for "favourite weapon").
var _attack_weapon: Dictionary = {}


func _init(p_config: PlaytestConfig) -> void:
	config = p_config
	var catalog: ItemCatalog = load("res://data/catalog.tres")
	for w in catalog.weapons:
		var attacks: Array = w.light_chain.duplicate()
		attacks.append_array([w.heavy, w.launcher, w.air_light, w.air_heavy, w.shot])
		for a in attacks:
			var cur := a as AttackData
			while cur:
				_attack_weapon[String(cur.id)] = String(w.id)
				cur = cur.follow_up


func load_dir(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return 0
	for f in DirAccess.get_files_at(path):
		if f.begins_with("session_") and f.ends_with(".json"):
			var s := PlaytestSession.load_file("%s/%s" % [path, f])
			if s:
				sessions.append(s)
	return sessions.size()


# --- Metrics --------------------------------------------------------------------

func analyze() -> Dictionary:
	var r := {
		"sessions": sessions.size(),
		"completed": 0,
		"completion_times": [],
		"session_minutes": [],
		"deaths_total": 0,
		"deaths_by_room": {},
		"deaths_by_cause": {},
		"damage_by_cause": {},
		"pits_by_room": {},
		"boss_attempts": [],
		"boss_clears": 0,
		"boss_attempts_by_id": {},
		"boss_clears_by_id": {},
		"lowlight_times": [],
		"timeline": {"campaign": [], "continued": [], "excluded": {}},
		"shutter_margins": {},
		"chase_catches": {},
		"chase_runs": {},
		"tracker_locks": {},
		"scanner_trips": {},
		"clamp_drops": {},
		"breakers": {},
		"room_seconds": {},
		"room_reentries": {},
		"idle_spans": {},
		"moments": [],
		"moment_tags": {},
		"hints": 0,
		"pauses": 0,
		"map_opens_by_room": {},
		"fast_travels": 0,
		"secrets_found": [],
		"dead_air_done": 0,
		"weapon_hits": {},
		"shots": {},
		"circuits_final": {},
		"purchases": {},
		"input_pad_share": [],
		"perf": {"histogram": [], "rooms": {}, "spikes": [], "hardware": []},
		"survey": {},
		"variants": {},
	}
	var hist: Array = []
	hist.resize(PlaytestSession.BUCKETS.size() + 1)
	hist.fill(0)
	for s in sessions:
		_analyze_session(s, r, hist)
	(r["perf"] as Dictionary)["histogram"] = hist
	r["scorecard"] = scorecard()
	return r


func _analyze_session(s: PlaytestSession, r: Dictionary, hist: Array) -> void:
	var meta: Dictionary = s.data["meta"]
	var variant := String(meta.get("variant", ""))
	var v: Dictionary = (r["variants"] as Dictionary).get(variant, {"sessions": 0, "completed": 0, "deaths": 0, "minutes": [], "movement": []})
	v["sessions"] = int(v["sessions"]) + 1
	r["session_minutes"].append(float(s.data.get("duration", 0.0)) / 60.0)
	var visited := {}
	var boss_starts := {}
	var deaths := 0
	for e: Dictionary in s.data["events"]:
		var room := String(e.get("room", ""))
		match String(e["type"]):
			"death":
				deaths += 1
				_inc(r["deaths_by_room"], room)
				_inc(r["deaths_by_cause"], _short_cause(String(e.get("cause", "unknown"))))
			"damage":
				_inc(r["damage_by_cause"], _short_cause(String(e.get("cause", "unknown"))), float(e.get("amount", 1)))
				if String(e.get("cause", "")) == "pit":
					_inc(r["pits_by_room"], room)
			"room_enter":
				if visited.has(room):
					_inc(r["room_reentries"], room)
				visited[room] = true
			"room_exit":
				_push(r["room_seconds"], room, float(e.get("seconds", 0.0)))
			"boss_start":
				_inc(boss_starts, boss_key(e))
			"boss_defeated":
				var bid := String(e.get("boss", ""))
				_inc(r["boss_clears_by_id"], bid)
				if bid == "warden_krail":
					r["boss_clears"] = int(r["boss_clears"]) + 1
			"shutter":
				_push(r["shutter_margins"], String(e.get("id", "")), float(e.get("margin", 0.0)))
			"chase_caught":
				_inc(r["chase_catches"], "%s CP%d" % [e.get("id", ""), int(e.get("cp", 0))])
			"chase_done":
				_push(r["chase_runs"], String(e.get("id", "")), int(e.get("catches", 0)))
			"tracker_lock":
				_inc(r["tracker_locks"], "%s / %s" % [room, e.get("id", "")])
			"scanner":
				_inc(r["scanner_trips"], "%s %s / %s (mode %d)" % [
					"calibration" if bool(e.get("calibration", false)) else "live", room, e.get("id", ""), int(e.get("mode", 0))])
			"clamp":
				_inc(r["clamp_drops"], "%s%s" % [e.get("id", ""), " (staggered boss)" if bool(e.get("staggered", false)) else ""])
			"breaker":
				_inc(r["breakers"], "%s / %s" % [room, e.get("circuit", "")])
			"slice_complete":
				r["completed"] = int(r["completed"]) + 1
				v["completed"] = int(v["completed"]) + 1
				r["completion_times"].append(float(e.get("play_time", 0.0)) / 60.0)
				(v["minutes"] as Array).append(float(e.get("play_time", 0.0)) / 60.0)
				r["secrets_found"].append(int(e.get("secrets", 0)))
				if bool(e.get("dead_air", false)):
					r["dead_air_done"] = int(r["dead_air_done"]) + 1
			"moment":
				r["moments"].append({"tag": e.get("tag", ""), "note": e.get("note", ""), "room": room, "x": e["x"], "y": e["y"]})
				_inc(r["moment_tags"], String(e.get("tag", "")))
			"hint":
				r["hints"] = int(r["hints"]) + 1
			"pause":
				r["pauses"] = int(r["pauses"]) + 1
			"map_open":
				_inc(r["map_opens_by_room"], room)
			"fast_travel":
				r["fast_travels"] = int(r["fast_travels"]) + 1
			"purchase":
				_inc(r["purchases"], String(e.get("item", "")))
	r["deaths_total"] = int(r["deaths_total"]) + deaths
	v["deaths"] = int(v["deaths"]) + deaths
	for bid: String in boss_starts:
		_push(r["boss_attempts_by_id"], bid, int(boss_starts[bid]))
		if bid == "warden_krail":
			r["boss_attempts"].append(int(boss_starts[bid]))
	_lowlight_time(s, r)
	_timeline(s, r)
	var loadouts := s.events_of("loadout")
	if not loadouts.is_empty():
		for c in (loadouts[-1] as Dictionary).get("circuits", []):
			_inc(r["circuits_final"], String(c))
	var counters: Dictionary = s.data["counters"]
	for key: String in counters:
		if key.begins_with("hits:"):
			_inc(r["weapon_hits"], String(_attack_weapon.get(key.trim_prefix("hits:"), "other")), float(counters[key]))
		elif key.begins_with("shots:"):
			_inc(r["shots"], key.trim_prefix("shots:"), float(counters[key]))
	var pad := float(counters.get("input_pad_s", 0.0))
	var kb := float(counters.get("input_keyboard_s", 0.0))
	if pad + kb > 0.0:
		r["input_pad_share"].append(pad / (pad + kb))
	for room: String in s.data["samples"]:
		var spans := idle_spans(s.data["samples"][room])
		for span in spans:
			_push(r["idle_spans"], room, span)
	var perf: Dictionary = s.data["perf"]
	for i in hist.size():
		hist[i] = int(hist[i]) + int((perf["histogram"] as Array)[i])
	var rooms_out: Dictionary = r["perf"]["rooms"]
	for room: String in perf["rooms"]:
		var src: Dictionary = perf["rooms"][room]
		var dst: Dictionary = rooms_out.get(room, {"frames": 0, "total_ms": 0.0, "max_ms": 0.0, "spikes": 0})
		dst["frames"] = int(dst["frames"]) + int(src["frames"])
		dst["total_ms"] = float(dst["total_ms"]) + float(src["total_ms"])
		dst["max_ms"] = maxf(float(dst["max_ms"]), float(src["max_ms"]))
		dst["spikes"] = int(dst["spikes"]) + int(src["spikes"])
		rooms_out[room] = dst
	r["perf"]["hardware"].append("%s / %s / %s Hz" % [meta.get("gpu", "?"), meta.get("os", "?"), meta.get("refresh_hz", "?")])
	var survey: Dictionary = s.data["survey"]
	for q in config.survey:
		if survey.has(q.id):
			_push(r["survey"], q.id, survey[q.id])
			if q.id == "movement_satisfying":
				(v["movement"] as Array).append(int(survey[q.id]))
	r["variants"][variant] = v


## Boss id of a boss_start event; pre-M7 sessions only carry the title.
static func boss_key(e: Dictionary) -> String:
	var id := String(e.get("id", ""))
	if id != "":
		return id
	var title := String(e.get("boss", ""))
	return String(BOSS_TITLE_IDS.get(title, title.to_lower()))


## Lowlight on its own: Relay arrival (cumulative play time) to slice end,
## for every kind of session, so the slice target reads the same after the
## Undercity was put in front of it.
func _lowlight_time(s: PlaytestSession, r: Dictionary) -> void:
	var relay: Dictionary = {}
	for e: Dictionary in s.data["events"]:
		if relay.is_empty() and e["type"] == "room_enter" and String(e.get("room", "")) == "Relay" and e.has("pt"):
			relay = e
		elif e["type"] == "slice_complete" and not relay.is_empty():
			r["lowlight_times"].append((float(e.get("play_time", 0.0)) - float(relay["pt"])) / 60.0)
			return


## Which timeline table a session belongs to ("campaign", "continued") or why
## it is left out.
func timeline_kind(s: PlaytestSession) -> String:
	var kind := String((s.data["meta"] as Dictionary).get("kind", ""))
	var first := ""
	for e: Dictionary in s.data["events"]:
		if e["type"] == "room_enter":
			first = String(e.get("room", ""))
			break
	if kind == "new":
		return "campaign" if first == timeline_start_room else "new, first room %s" % (first if first != "" else "none")
	if kind == "continue":
		return "continued" if _is_undercity(first) else "continue, first room %s" % (first if first != "" else "none")
	return kind if kind != "" else "unknown kind"


static func _is_undercity(room_id: String) -> bool:
	var m := Game.world_map.room(room_id)
	if m != null:
		return m.district == "undercity"
	return UNDERCITY_ROOM_IDS.has(room_id)


func _timeline(s: PlaytestSession, r: Dictionary) -> void:
	var tl: Dictionary = r["timeline"]
	var which := timeline_kind(s)
	if which != "campaign" and which != "continued":
		_inc(tl["excluded"], which)
		return
	# Campaign minutes use the session clock; continued runs use cumulative
	# play time so a beat after Save & Quit reports its true campaign minute.
	var use_pt := which == "continued"
	var row := {}
	for e: Dictionary in s.data["events"]:
		var key := _timeline_key(e)
		if key == "" or row.has(key):
			continue
		row[key] = float(e.get("pt", 0.0) if use_pt else e.get("t", 0.0)) / 60.0
		# The first rest is also the uc_lift rest when it is that anchor.
		if key == "anchor_lift" and not row.has("anchor"):
			row["anchor"] = row[key]
	(tl[which] as Array).append(row)


static func _timeline_key(e: Dictionary) -> String:
	match String(e["type"]):
		"weapon_granted":
			return "blade" if String(e.get("id", "")) == "pulse_blade" else ""
		"dodge_first":
			return "dodge"
		"room_enter":
			match String(e.get("room", "")):
				"MaintenanceShaft":
					return "composition"
				"FirstPursuit":
					return "pursuit"
				"Relay":
					return "relay"
		"secret":
			return "secret"
		"dialogue":
			return "npc" if String(e.get("npc", "")) == "Radio" else ""
		"flag":
			if String(e.get("id", "")) == "hint_first_flow":
				return "first_flow"
			if String(e.get("id", "")) == "core_hud_hidden" and not bool(e.get("value", true)):
				return "core_hud"
		"anchor_rest":
			return "anchor_lift" if String(e.get("anchor", "")) == "uc_lift" else "anchor"
		"boss_start":
			return "boss_start" if String(e.get("boss", "")) == "COLLECTOR DRONE" else ""
		"boss_defeated":
			return "boss_defeated" if String(e.get("boss", "")) == "collector_drone" else ""
	return ""


## Median minutes per timeline item over rows ("—" when nobody reached it).
static func timeline_medians(rows: Array) -> Dictionary:
	var out := {}
	for item: Dictionary in TIMELINE_ITEMS:
		var vals: Array = []
		for row: Dictionary in rows:
			if row.has(item["key"]):
				vals.append(row[item["key"]])
		out[item["key"]] = _median(vals) if not vals.is_empty() else null
	return out


## Spans (seconds) where the player stayed within idle_radius for at least
## idle_seconds: the clearest "unsure what to do" signal the samples give.
func idle_spans(samples: Array) -> Array:
	var spans: Array = []
	if samples.is_empty():
		return spans
	var start: Array = samples[0]
	var last: Array = samples[0]
	for smp: Array in samples:
		var moved := Vector2(float(smp[1]) - float(start[1]), float(smp[2]) - float(start[2])).length() > config.idle_radius
		var gap := float(smp[0]) - float(last[0]) > config.sample_interval * 4.0  # paused / room left
		if moved or gap:
			var d := float(last[0]) - float(start[0])
			if d >= config.idle_seconds:
				spans.append(d)
			start = smp
		last = smp
	var tail := float(last[0]) - float(start[0])
	if tail >= config.idle_seconds:
		spans.append(tail)
	return spans


## Bible §44 scorecard: for each criterion, the share of answering testers
## who passed it; a criterion is met at >= pass_ratio, the slice passes when
## at least criteria_needed are met.
func scorecard() -> Dictionary:
	var rows: Array = []
	var met := 0
	for q in config.survey:
		if q.criterion == "":
			continue
		var answered := 0
		var passed := 0
		for s in sessions:
			var survey: Dictionary = s.data["survey"]
			if survey.has(q.id):
				answered += 1
				if q.passes(survey[q.id]):
					passed += 1
		var ratio := float(passed) / answered if answered > 0 else 0.0
		var ok := answered > 0 and ratio >= config.pass_ratio
		if ok:
			met += 1
		rows.append({"id": q.id, "criterion": q.criterion, "answered": answered, "passed": passed, "ratio": ratio, "met": ok})
	return {"rows": rows, "met": met, "needed": config.criteria_needed, "pass": met >= config.criteria_needed}


# --- Presentation ------------------------------------------------------------

func render_markdown(r: Dictionary, title: String = "REDLINE playtest report") -> String:
	var md: PackedStringArray = []
	md.append("# %s" % title)
	md.append("")
	md.append("Sessions: **%d** · completed the slice: **%d** · generated %s" % [r["sessions"], r["completed"], Time.get_datetime_string_from_system(true)])
	if int(r["sessions"]) < 5:
		md.append("")
		md.append("> Fewer than 5 sessions: treat every number here as anecdote, not evidence.")
	var sc: Dictionary = r["scorecard"]
	md.append("")
	var any_answers := (sc["rows"] as Array).any(func(row: Dictionary) -> bool: return int(row["answered"]) > 0)
	var verdict := "NO SURVEY DATA" if not any_answers else ("PASS" if sc["pass"] else "NOT YET")
	md.append("## Bible §44 scorecard: %s (%d of %d criteria met, %d needed)" % [verdict, sc["met"], (sc["rows"] as Array).size(), sc["needed"]])
	md.append("")
	md.append("| Criterion | Answered | Passed | Share | Met |")
	md.append("|---|---|---|---|---|")
	for row: Dictionary in sc["rows"]:
		var mark := "—" if int(row["answered"]) == 0 else ("✅" if row["met"] else "❌")
		md.append("| %s | %d | %d | %d%% | %s |" % [row["criterion"], row["answered"], row["passed"], roundi(float(row["ratio"]) * 100.0), mark])
	md.append("")
	md.append("## Completion time and deaths")
	md.append("- Completion time, whole run (min): %s" % _stats(r["completion_times"]))
	md.append("- Lowlight time, Relay arrival → slice_complete (min): %s" % _stats(r["lowlight_times"]))
	md.append("- Session length (min): %s" % _stats(r["session_minutes"]))
	md.append("- Deaths: %d total, %.1f per session" % [r["deaths_total"], float(r["deaths_total"]) / maxi(1, int(r["sessions"]))])
	var boss_ids: Array = ["warden_krail", "collector_drone"]
	for bid: String in r["boss_attempts_by_id"]:
		if not boss_ids.has(bid):
			boss_ids.append(bid)
	for bid: String in boss_ids:
		var label: Array = BOSS_LABELS.get(bid, [bid, "it"])
		md.append("- %s: attempts per tester who reached %s: %s · clears: %d" % [label[0], label[1],
			_stats((r["boss_attempts_by_id"] as Dictionary).get(bid, [])), int((r["boss_clears_by_id"] as Dictionary).get(bid, 0))])
	md.append("- Secrets found at the end: %s · Dead Air completed: %d" % [_stats(r["secrets_found"]), r["dead_air_done"]])
	md.append("")
	md.append(_table("Deaths by room", r["deaths_by_room"]))
	md.append(_table("Deaths by cause (enemy/attack, hazard, pit, burnout)", r["deaths_by_cause"]))
	md.append(_table("Damage taken by cause", r["damage_by_cause"]))
	md.append(_table("Pit falls by room", r["pits_by_room"]))
	md.append(_timeline_markdown(r["timeline"]))
	md.append(_set_piece_markdown(r))
	md.append("## Confusion signals")
	md.append("")
	md.append("| Room | Median time (s) | Visits | Re-entries | Idle spans ≥ %ds |" % roundi(config.idle_seconds))
	md.append("|---|---|---|---|---|")
	var rooms: Array = (r["room_seconds"] as Dictionary).keys()
	rooms.sort()
	for room: String in rooms:
		var secs: Array = r["room_seconds"][room]
		md.append("| %s | %d | %d | %d | %d |" % [room, roundi(_median(secs)), secs.size(), int(r["room_reentries"].get(room, 0)), (r["idle_spans"].get(room, []) as Array).size()])
	md.append("")
	md.append("- Hints shown: %d · pauses: %d · fast travels: %d" % [r["hints"], r["pauses"], r["fast_travels"]])
	md.append("")
	md.append(_table("Map opened, by room (lots of opens in one room = players unsure where to go)", r["map_opens_by_room"]))
	md.append(_survey_line(r, "got_lost", "Got lost (yes answers)"))
	md.append("")
	md.append(_table("Reported moments by tag", r["moment_tags"]))
	var notes: PackedStringArray = []
	for m: Dictionary in r["moments"]:
		notes.append("- **%s** in %s at (%d, %d)%s" % [m["tag"], m["room"], m["x"], m["y"], (": \"%s\"" % m["note"]) if String(m["note"]) != "" else ""])
	if not notes.is_empty():
		md.append("### Moment notes")
		md.append("\n".join(notes))
		md.append("")
	md.append("## Favourite mechanics")
	md.append(_choice_table(r, "favorite", "Favourite thing to do (survey)"))
	md.append(_choice_table(r, "memorable_enemy", "Most memorable enemy (survey)"))
	md.append(_table("Hits landed by weapon", r["weapon_hits"]))
	md.append(_table("Shots fired by weapon", r["shots"]))
	md.append(_table("Circuits equipped at the end", r["circuits_final"]))
	md.append(_table("Purchases", r["purchases"]))
	md.append("## Controls")
	md.append(_survey_line(r, "controls_ok", "\"The controls did what I meant\" (1–5)"))
	md.append("- 'Controls felt off' moments: %d" % int(r["moment_tags"].get("Controls felt off", 0)))
	md.append("- Controller share of play time: %s" % _stats(r["input_pad_share"], true))
	md.append("")
	md.append("## Performance (real frame times on testers' machines)")
	var hist: Array = r["perf"]["histogram"]
	var total := 0
	for n in hist:
		total += int(n)
	var labels: PackedStringArray = []
	var prev := 0.0
	for i in hist.size():
		var hi: String = ("%.1f" % PlaytestSession.BUCKETS[i]) if i < PlaytestSession.BUCKETS.size() else "∞"
		labels.append("%s–%s ms: %.1f%%" % [("%.1f" % prev), hi, 100.0 * int(hist[i]) / maxi(1, total)])
		if i < PlaytestSession.BUCKETS.size():
			prev = PlaytestSession.BUCKETS[i]
	md.append("- Frames: %d · %s" % [total, " · ".join(labels)])
	md.append("")
	md.append("| Room | Avg ms | Max ms | Spikes > %.1f ms |" % config.spike_ms)
	md.append("|---|---|---|---|")
	var prooms: Array = (r["perf"]["rooms"] as Dictionary).keys()
	prooms.sort()
	for room: String in prooms:
		var p: Dictionary = r["perf"]["rooms"][room]
		md.append("| %s | %.2f | %.1f | %d |" % [room if room != "" else "(menus/transition)", float(p["total_ms"]) / maxi(1, int(p["frames"])), p["max_ms"], p["spikes"]])
	md.append("")
	var hw := {}
	for h: String in r["perf"]["hardware"]:
		hw[h] = int(hw.get(h, 0)) + 1
	var hw_list: PackedStringArray = []
	for h: String in hw:
		hw_list.append("%s ×%d" % [h, hw[h]])
	md.append("Hardware (GPU / OS / refresh): %s" % ", ".join(hw_list))
	md.append("")
	md.append("## Variants (open design questions)")
	md.append("")
	md.append("| Variant | Sessions | Completed | Deaths/session | Completion min | Movement score |")
	md.append("|---|---|---|---|---|---|")
	for id: String in r["variants"]:
		var v: Dictionary = r["variants"][id]
		md.append("| %s | %d | %d | %.1f | %s | %s |" % [id if id != "" else "(none)", v["sessions"], v["completed"], float(v["deaths"]) / maxi(1, int(v["sessions"])), _stats(v["minutes"]), _stats(v["movement"])])
	md.append("")
	md.append("> Variant differences with a handful of testers are directional only. Read them alongside the moment notes and the heatmaps.")
	return "\n".join(md) + "\n"


func _timeline_markdown(tl: Dictionary) -> String:
	var md: PackedStringArray = ["## Undercity timeline", ""]
	var campaign: Array = tl["campaign"]
	md.append("Campaign runs (New Game from %s, minutes of session time): **%d**. Medians:" % [timeline_start_room, campaign.size()])
	md.append("")
	md.append("| Beat | Median min | Reached |")
	md.append("|---|---|---|")
	var med := timeline_medians(campaign)
	for item: Dictionary in TIMELINE_ITEMS:
		var reached := campaign.filter(func(row: Dictionary) -> bool: return row.has(item["key"])).size()
		md.append("| %s | %s | %d |" % [item["label"], _minutes(med[item["key"]]), reached])
	md.append("")
	for title: String in ["Campaign", "Continued"]:
		var rows: Array = tl[title.to_lower()]
		if rows.is_empty():
			continue
		md.append("%s runs, per session%s:" % [title, " (minutes of cumulative play time)" if title == "Continued" else ""])
		md.append("")
		var head: PackedStringArray = ["Session"]
		var sep: PackedStringArray = ["---"]
		for item: Dictionary in TIMELINE_ITEMS:
			head.append(item["key"])
			sep.append("---")
		md.append("| %s |" % " | ".join(head))
		md.append("| %s |" % " | ".join(sep))
		for i in rows.size():
			var cells: PackedStringArray = [str(i + 1)]
			for item: Dictionary in TIMELINE_ITEMS:
				cells.append(_minutes((rows[i] as Dictionary).get(item["key"])))
			md.append("| %s |" % " | ".join(cells))
		md.append("")
	var excluded: Dictionary = tl["excluded"]
	var n := 0
	var why: PackedStringArray = []
	for k: String in excluded:
		n += int(excluded[k])
		why.append("%s ×%d" % [k, int(excluded[k])])
	md.append("Excluded from the timeline: %d%s" % [n, (" (" + ", ".join(why) + ")") if n > 0 else ""])
	md.append("")
	return "\n".join(md)


func _set_piece_markdown(r: Dictionary) -> String:
	var md: PackedStringArray = ["## District set pieces", ""]
	md.append("| Shutter | Passes | Median margin (s) | Closest (s) |")
	md.append("|---|---|---|---|")
	var ids: Array = (r["shutter_margins"] as Dictionary).keys()
	ids.sort()
	for id: String in ids:
		var m: Array = r["shutter_margins"][id]
		var lo := m.duplicate()
		lo.sort()
		md.append("| %s | %d | %.2f | %.2f |" % [id, m.size(), _median(m), float(lo[0])])
	if ids.is_empty():
		md.append("| _none recorded_ | | | |")
	md.append("")
	var runs: PackedStringArray = []
	for id: String in r["chase_runs"]:
		runs.append("%s: %s" % [id, _stats(r["chase_runs"][id])])
	md.append("- Chase catches per completed run: %s" % (", ".join(runs) if not runs.is_empty() else "n/a"))
	md.append("")
	md.append(_table("Chase catches by checkpoint", r["chase_catches"]))
	md.append(_table("Collector eye locks by room / eye", r["tracker_locks"]))
	# Errata #15: live and calibration trips are separate rows ("live ..." /
	# "calibration ..."), so a calibration beam that trips often reads as
	# teaching, not as failure.
	md.append(_table("Scanner trips by kind / room / beam", r["scanner_trips"]))
	md.append(_table("Grid clamp drops", r["clamp_drops"]))
	md.append(_table("Breakers struck by room / circuit", r["breakers"]))
	return "\n".join(md)


static func _minutes(v: Variant) -> String:
	return "—" if v == null else "%.1f" % float(v)


## Top-down map of one room: geometry in grey, position samples as a warm
## density, deaths as red crosses, pit falls orange, reported moments yellow.
func render_heatmap(room_file: String, scale: float = 0.5) -> Image:
	var room_id := room_file.get_file().get_basename()
	var scene := load(room_file) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Room
	RoomTemplate.expand_all(inst)
	var b := inst.bounds
	var size := Vector2i(ceili(b.size.x * scale), ceili(b.size.y * scale))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.05, 0.09))
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(roundi((p.x - b.position.x) * scale), roundi((p.y - b.position.y) * scale))
	for n in inst.find_children("*", "GrayboxBlock", true, false):
		var blk := n as GrayboxBlock
		var pos := _local_pos(blk, inst)
		var tl: Vector2i = to_px.call(pos)
		var r := Rect2i(tl, Vector2i(maxi(1, roundi(blk.size.x * scale)), maxi(1, roundi(blk.size.y * scale))))
		img.fill_rect(r.intersection(Rect2i(Vector2i.ZERO, size)), Color(0.36, 0.36, 0.42) if not blk.one_way else Color(0.3, 0.45, 0.5))
	inst.free()
	var density := {}
	for s in sessions:
		for smp: Array in (s.data["samples"] as Dictionary).get(room_id, []):
			var px: Vector2i = to_px.call(Vector2(float(smp[1]), float(smp[2]) - 12.0))
			density[px] = int(density.get(px, 0)) + 1
	for px: Vector2i in density:
		var k := clampf(float(density[px]) / 6.0, 0.2, 1.0)
		_dot(img, px, 2, Color(1.0, 0.5 + 0.45 * k, 0.15, 0.55 + 0.45 * k))
	for s in sessions:
		for e: Dictionary in s.data["events"]:
			if String(e.get("room", "")) != room_id:
				continue
			var px: Vector2i = to_px.call(Vector2(float(e["x"]), float(e["y"]) - 12.0))
			match String(e["type"]):
				"death":
					_cross(img, px, Color(1, 0.15, 0.2))
				"damage":
					if String(e.get("cause", "")) == "pit":
						_dot(img, px, 2, Color(1, 0.55, 0.1))
				"moment":
					_dot(img, px, 3, Color(1, 0.9, 0.2))
	return img


# --- Helpers --------------------------------------------------------------------

static func _local_pos(n: Node2D, root: Node) -> Vector2:
	var p := n.position
	var cur := n.get_parent()
	while cur and cur != root:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p


static func _dot(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := c + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixelv(p, img.get_pixelv(p).blend(col))


static func _cross(img: Image, c: Vector2i, col: Color) -> void:
	for i in range(-3, 4):
		for p: Vector2i in [c + Vector2i(i, i), c + Vector2i(i, -i)]:
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixelv(p, col)


## "needle/needle_stab" -> "needle: needle_stab" for tables. Set-piece causes
## get readable names (the Collector eye has no Enemy, so it reads unknown/).
static func _short_cause(cause: String) -> String:
	if CAUSE_LABELS.has(cause):
		return CAUSE_LABELS[cause]
	if cause.begins_with("chase/"):
		return "Chase: " + cause.trim_prefix("chase/")
	return cause.replace("/", ": ")


static func _inc(d: Dictionary, key: String, amount: float = 1.0) -> void:
	d[key] = float(d.get(key, 0.0)) + amount


static func _push(d: Dictionary, key: String, value: Variant) -> void:
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append(value)


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var m := v.size() / 2
	return float(v[m]) if v.size() % 2 == 1 else (float(v[m - 1]) + float(v[m])) * 0.5


static func _stats(values: Array, percent := false) -> String:
	if values.is_empty():
		return "n/a"
	var v := values.duplicate()
	v.sort()
	var f := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if percent else ("%.1f" % x)
	return "median %s (min %s, max %s, n=%d)" % [f.call(_median(v)), f.call(float(v[0])), f.call(float(v[-1])), v.size()]


func _survey_line(r: Dictionary, id: String, label: String) -> String:
	var answers: Array = (r["survey"] as Dictionary).get(id, [])
	if answers.is_empty():
		return "- %s: no answers" % label
	var nums := answers.map(func(a: Variant) -> float: return 1.0 if a is bool and a else (0.0 if a is bool else float(a)))
	return "- %s: %s" % [label, _stats(nums)]


func _choice_table(r: Dictionary, id: String, title: String) -> String:
	var q: SurveyQuestion = null
	for x in config.survey:
		if x.id == id:
			q = x
	var counts := {}
	for a in (r["survey"] as Dictionary).get(id, []):
		var i := int(a)
		if q and i >= 0 and i < q.choices.size():
			_inc(counts, q.choices[i])
	return _table(title, counts)


static func _table(title: String, d: Dictionary) -> String:
	var out: PackedStringArray = ["### %s" % title, ""]
	if d.is_empty():
		out.append("_none recorded_")
		out.append("")
		return "\n".join(out)
	var keys: Array = d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(d[a]) > float(d[b]))
	out.append("| | Count |")
	out.append("|---|---|")
	for k in keys:
		out.append("| %s | %s |" % [k if String(k) != "" else "(none)", str(snappedf(float(d[k]), 0.1))])
	out.append("")
	return "\n".join(out)
