class_name RecordStore
extends RefCounted
## Local leaderboards and personal bests (M9 D2 §5, D-149): one
## profile-independent file, Platform.store_dir + "/records.json", written
## atomically (AtomicJson: tmp -> .bak -> rename, .bak recovery on read).
##
## Layout: {format, boards: {challenge_id: {revision, entries[top N], best{p},
## attempts{p}, clears{p}, stage_best{p}{stage}, archived[]}}, campaign:
## {best_igt{p}, best_splits{p}, best_tags{p}}, ever_unlocked{id: unix},
## meta{reset_used, announced_groups}}. Profile keys are strings (JSON).
##
## All local profiles share one board per challenge and each entry shows its
## profile slot; bests and ghosts are per profile. Assisted runs stay on the
## same board and earn the same medals, with neutral tags only (D-149).
## Challenge progress never lives in the profile save (a new slot starts with
## an empty best column). Nothing is written unless Platform.active()
## (headless runs only with allow_headless); in-memory otherwise.
## It loads lazily and reloads when Platform.store_dir changed (debug demos,
## tests; R04.21).

const FORMAT := 1
const FILE := "records.json"

## Tests: a fixed "now" (unix seconds) for dates and tie-breaks; -1 = clock.
var now_override: float = -1.0

var _data: Dictionary = {}
## Platform.store_dir at load time ("" = not loaded yet).
var _loaded_dir: String = ""
var _seq: int = 0


func path() -> String:
	return Platform.store_dir + "/" + FILE


func ghost_path(challenge_id: String, profile: int) -> String:
	return "%s/ghosts/%s_p%d.ghost" % [Platform.store_dir, challenge_id, profile]


## Drops the in-memory copy; the next access reads the file again.
func reload() -> void:
	_loaded_dir = ""
	_data = {}


func _ensure() -> void:
	if _loaded_dir == Platform.store_dir and not _data.is_empty():
		return
	_loaded_dir = Platform.store_dir
	_data = AtomicJson.read(path()) if FileAccess.file_exists(path()) or FileAccess.file_exists(path() + ".bak") else {}
	if int(_data.get("format", FORMAT)) != FORMAT:
		push_warning("RecordStore: unknown records format %s, starting empty" % _data.get("format"))
		_data = {}
	for k: String in ["boards", "campaign", "ever_unlocked", "meta"]:
		if not _data.get(k) is Dictionary:
			_data[k] = {}
	_data["format"] = FORMAT
	for b: Dictionary in _data["boards"].values():
		for e: Dictionary in b.get("entries", []):
			_seq = maxi(_seq, int(e.get("seq", 0)))


func _save() -> Error:
	if not Platform.active():
		return OK
	return AtomicJson.write(path(), _data)


func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


static func _pk(profile: int) -> String:
	return str(profile)


## The board of `ch`, archiving an older revision's record first (D2 §5.4).
func _board(ch: ChallengeData) -> Dictionary:
	_ensure()
	var boards: Dictionary = _data["boards"]
	var b: Dictionary = boards.get(ch.id, {})
	if not b.is_empty() and int(b.get("revision", 1)) != ch.revision:
		var archived: Array = b.get("archived", [])
		var old := b.duplicate(true)
		old.erase("archived")
		archived.append(old)
		b = {"archived": archived}
	if b.is_empty() or not b.has("revision"):
		for k: String in ["best", "attempts", "clears", "stage_best"]:
			b[k] = b.get(k, {})
		b["entries"] = b.get("entries", [])
		b["archived"] = b.get("archived", [])
		b["revision"] = ch.revision
	boards[ch.id] = b
	return b


func _peek(id: String) -> Dictionary:
	_ensure()
	return _data["boards"].get(id, {})


## Records one finished or failed attempt. Failed runs (no value) count an
## attempt only. Returns the SubmitResult dictionary the result card reads:
## {challenge, profile, outcome, value, medal, new_best, prev_best, rank,
##  attempt, tags, date}.
func submit(ch: ChallengeData, profile: int, value: int, outcome: int, splits: PackedInt32Array = PackedInt32Array(),
		tags: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var b := _board(ch)
	var pk := _pk(profile)
	var attempts: Dictionary = b["attempts"]
	attempts[pk] = int(attempts.get(pk, 0)) + 1
	var t := _now()
	var date := Time.get_datetime_string_from_unix_time(int(t))
	var medal := ch.medal_for(value) if value >= 0 else -1
	if extra.has("medal"):
		medal = int(extra["medal"])
	var prev: Dictionary = b["best"].get(pk, {})
	var prev_best := int(prev.get("value", -1))
	var res := {"challenge": ch.id, "profile": profile, "outcome": outcome, "value": value, "medal": medal,
		"new_best": false, "prev_best": prev_best, "rank": 0, "attempt": int(attempts[pk]),
		"tags": tags.duplicate(true), "date": date}
	for k: String in extra:
		if not res.has(k) or k == "medal":
			res[k] = extra[k]
	if value < 0:
		_save()
		return res
	var clears: Dictionary = b["clears"]
	clears[pk] = int(clears.get(pk, 0)) + 1
	_seq += 1
	var entry := {"profile": profile, "value": value, "medal": medal, "outcome": outcome, "date": date, "t": t,
		"seq": _seq, "assists": Array(tags.get("assists", [])), "timing": Array(tags.get("timing", [])),
		"build": BuildInfo.version(), "attempt": int(attempts[pk])}
	var entries: Array = b["entries"]
	var at := entries.size()
	for i in entries.size():
		if _before(ch, entry, entries[i]):
			at = i
			break
	entries.insert(at, entry)
	var size := ChallengeConfig.shared().pb_board_size
	while entries.size() > size:
		entries.pop_back()
	res["rank"] = at + 1 if at < size else 0
	if ch.is_better(value, prev_best):
		res["new_best"] = true
		b["best"][pk] = {"value": value, "medal": medal, "splits": Array(splits), "date": date,
			"stages": extra.get("stages", []), "ghost": ghost_path(ch.id, profile).get_file()}
	_save()
	return res


## Board order: better value first; equal values by the earlier date, then
## by submission order.
func _before(ch: ChallengeData, a: Dictionary, b: Dictionary) -> bool:
	var va := int(a["value"])
	var vb := int(b["value"])
	if va != vb:
		return ch.is_better(va, vb)
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 0.0))
	if ta != tb:
		return ta < tb
	return int(a.get("seq", 0)) < int(b.get("seq", 0))


## A stage cleared inside a staged run: keeps the per-stage best (by score).
## Returns true on a new stage best.
func submit_stage(ch: ChallengeData, profile: int, stage_id: String, result: Dictionary) -> bool:
	var b := _board(ch)
	var pk := _pk(profile)
	var per: Dictionary = b["stage_best"].get(pk, {})
	var prev: Dictionary = per.get(stage_id, {})
	var better := prev.is_empty() or int(result.get("score", -1)) > int(prev.get("score", -1)) \
		or (int(result.get("score", -1)) == int(prev.get("score", -1)) and int(result.get("frames", 0)) < int(prev.get("frames", 0)))
	if better:
		per[stage_id] = result.duplicate(true)
		b["stage_best"][pk] = per
		_save()
	return better


## Top entries, best first (copies).
func board(id: String) -> Array:
	return (_peek(id).get("entries", []) as Array).duplicate(true)


## {value, medal, splits, date, stages, ghost} or {}.
func best(id: String, profile: int) -> Dictionary:
	var d: Dictionary = _peek(id).get("best", {}).get(_pk(profile), {})
	return d.duplicate(true)


func best_stage(id: String, profile: int, stage_id: String) -> Dictionary:
	var d: Dictionary = _peek(id).get("stage_best", {}).get(_pk(profile), {}).get(stage_id, {})
	return d.duplicate(true)


func attempts(id: String, profile: int) -> int:
	return int(_peek(id).get("attempts", {}).get(_pk(profile), 0))


func clears(id: String, profile: int) -> int:
	return int(_peek(id).get("clears", {}).get(_pk(profile), 0))


## Records from earlier revisions of this challenge (kept, not shown).
func archived_count(id: String) -> int:
	var n := 0
	for a: Dictionary in _peek(id).get("archived", []):
		n += (a.get("entries", []) as Array).size()
	return n


# --- Campaign IGT ------------------------------------------------------------

func campaign_best(profile: int) -> int:
	_ensure()
	return int(_data["campaign"].get("best_igt", {}).get(_pk(profile), -1))


func campaign_best_splits(profile: int) -> Dictionary:
	_ensure()
	var out := {}
	var d: Dictionary = _data["campaign"].get("best_splits", {}).get(_pk(profile), {})
	for k: String in d:
		out[k] = int(d[k])
	return out


func campaign_best_tags(profile: int) -> PackedStringArray:
	_ensure()
	return PackedStringArray(_data["campaign"].get("best_tags", {}).get(_pk(profile), []))


## Posts a finished campaign (the act1_end split). Returns true on a new best.
func submit_campaign(profile: int, igt: int, splits: Dictionary, tags: PackedStringArray = PackedStringArray()) -> bool:
	_ensure()
	var c: Dictionary = _data["campaign"]
	for k: String in ["best_igt", "best_splits", "best_tags"]:
		if not c.get(k) is Dictionary:
			c[k] = {}
	var pk := _pk(profile)
	var prev := int(c["best_igt"].get(pk, -1))
	if prev >= 0 and igt >= prev:
		return false
	c["best_igt"][pk] = igt
	c["best_splits"][pk] = splits.duplicate()
	c["best_tags"][pk] = Array(tags)
	_save()
	return true


# --- Sticky unlocks, notices, first-use hints -------------------------------

## True once the challenge was ever unlocked on this machine (R04.6): NG+
## resets *_defeated flags but never re-locks a challenge.
func ever_unlocked(id: String) -> bool:
	_ensure()
	return _data["ever_unlocked"].has(id)


## Records the unlock; true the first time.
func record_unlock(id: String) -> bool:
	if ever_unlocked(id):
		return false
	_data["ever_unlocked"][id] = int(_now())
	_save()
	return true


func group_announced(group: int) -> bool:
	_ensure()
	return (_data["meta"].get("announced_groups", []) as Array).has(group)


func mark_group_announced(group: int) -> void:
	if group_announced(group):
		return
	var a: Array = _data["meta"].get("announced_groups", [])
	a.append(group)
	_data["meta"]["announced_groups"] = a
	_save()


## R04.7: the player has used fast reset at least once.
func reset_used() -> bool:
	_ensure()
	return bool(_data["meta"].get("reset_used", false))


func mark_reset_used() -> void:
	if reset_used():
		return
	_data["meta"]["reset_used"] = true
	_save()


## Dev only: forget one challenge's record (or every record and ghost file).
func clear(id: String = "") -> void:
	_ensure()
	if id == "":
		_data["boards"] = {}
		_data["campaign"] = {}
	else:
		(_data["boards"] as Dictionary).erase(id)
	_save()


# --- Ghost files ---------------------------------------------------------------

## The personal-best ghost (written only on a new best; never a Resource).
func save_pb_ghost(id: String, profile: int, g: GhostData) -> Error:
	if not Platform.active() or g == null:
		return ERR_UNAVAILABLE
	return GhostCodec.save(ghost_path(id, profile), g)


## The profile's PB ghost for this revision, or null.
func pb_ghost(id: String, profile: int, revision: int) -> GhostData:
	var p := ghost_path(id, profile)
	if not FileAccess.file_exists(p):
		return null
	var g := GhostCodec.load_file(p)
	if g == null or g.challenge != id or g.revision != revision:
		return null
	return g
