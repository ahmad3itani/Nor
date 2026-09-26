class_name AssistAdvisor
extends Node
## Adaptive-assist suggestion (bible §23, §24, D4 §10): after repeated deaths
## in one fight or one room, the game *offers* options on a card
## (AssistSuggestMenu). It never changes a setting by itself; only the
## player's answer on the card does. Main.gd instances it at boot (optional
## M9 systems); gameplay never calls it, it only listens to EventBus.
##
## Two death logs, neither cleared by a room change (R11.4), because neither
## boss room has an Anchor: a Collector death respawns at BrokenLift and a
## Krail death at the BellTower, and the player walks back.
## - Boss log "boss:<id>": deaths while a BossArena fight was running. Cleared
##   only by boss_defeated(id), window expiry or an answer to the card.
## - Room log "room:<path>": every other death in that room within the
##   window, wherever the player respawned. Cleared only by window expiry, a
##   rest at an Anchor in that room or an answer.
## The card is checked on player_respawned and opens once the respawn's fade
## is over and no menu is open.
##
## Suppressed (never shown) when the player turned suggestions off, a
## challenge run or a dev theatre owns the session, the room is not a world
## room, the dev "advisor quiet" toggle is on, within the cooldown after a
## "Not now", past the per-session cap, or when every setting the matching
## rule would offer is already in an assisted state.

## Player text lives on the card (AssistSuggestMenu) and in AssistRule data.
const LOC_FIELDS := {}

## Explicit assisted-value sets (R11.12): [key, offered value, values that
## already count as assisted]. No "stronger than" arithmetic: a key whose
## current value is in the set is never offered. Keys not listed count as
## assisted only at the offered value itself.
const ASSISTED := [
	["burnout_hurts", false, [false]],
	["reactor_mode", 1, [1]],
	["damage_assist", 1, [1, 2, 3]],
	["damage_assist", 2, [2, 3]],
	["damage_assist", 3, [3]],
	["aim_assist", 1, [1, 2]],
	["aim_assist", 2, [2]],
	["generous_checkpoints", true, [true]],
	["jump_hold_mode", 1, [1]],
]
## Values a player chose on purpose that no suggestion may touch: a Redline
## Challenge Core (reactor_mode 2) is never offered a Core-mode change; the
## burnout rule then offers only burnout_hurts = false.
const NEVER_FROM := [["reactor_mode", [2]]]

## Dev console "Toggle advisor quiet" (only honoured in dev builds).
static var dev_quiet: bool = false

## Test seam: added to Time.get_ticks_msec() (window and cooldown are real time).
var time_offset_ms: int = 0
## Test seam: replaces Settings.access_config when set.
var config_override: AccessibilityConfig = null
## context -> Array of {t: int ms, cause: String}.
var _logs: Dictionary = {}
## context -> title for the card (boss title or room name).
var _titles: Dictionary = {}
## Boss id and title while a BossArena fight runs ("" when none).
var _boss_id: String = ""
var _boss_title: String = ""
## The context of the last death, checked on the next player_respawned.
var _death_context: String = ""
## A context waiting for the fade and menus to clear before the card opens.
var _pending: String = ""
var _shown_this_session: int = 0
## Real ms after which "Not now" no longer holds the card back (-1 = none).
var _cooldown_until: int = -1


func _ready() -> void:
	add_to_group(&"assist_advisor")
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.room_loaded.connect(_on_room_loaded)
	EventBus.anchor_rested.connect(_on_anchor_rested)
	EventBus.assist_suggestion_answered.connect(_on_answered)


func config() -> AccessibilityConfig:
	return config_override if config_override != null else Settings.config()


func now_ms() -> int:
	return Time.get_ticks_msec() + time_offset_ms


# --- Death logs -------------------------------------------------------------

func _on_boss_started(boss: Node2D, title: String) -> void:
	var id := BossArena.id_of(boss)
	_boss_id = id if id != "" else title.to_lower().replace(" ", "_")
	_boss_title = title


func _on_boss_defeated(boss_id: String) -> void:
	_logs.erase("boss:%s" % boss_id)
	if _boss_id == boss_id:
		_boss_id = ""


## A new room (a door, a respawn transition) ends any running fight. The logs
## stay: the walk back from the Anchor is part of learning the fight.
func _on_room_loaded(_room: Node) -> void:
	_boss_id = ""


func _on_anchor_rested(_anchor: Node) -> void:
	_logs.erase("room:%s" % SceneRouter.current_room_path)


func _on_player_died() -> void:
	var room := SceneRouter.current_room as Room
	# A challenge run owns its deaths (fast resets are the point there).
	if room == null or not room.world_room or Challenges.active():
		return
	var cause := "unknown"
	if is_instance_valid(room.player):
		cause = room.player.combat.last_damage_source
	var ctx: String
	if _boss_id != "":
		ctx = "boss:%s" % _boss_id
		_titles[ctx] = _boss_title
	else:
		ctx = "room:%s" % SceneRouter.current_room_path
		_titles[ctx] = room.room_name
	record_death(ctx, cause)
	_death_context = ctx


## Logs one death (tests and the dev trigger call it directly).
func record_death(ctx: String, cause: String) -> void:
	var entries: Array = _logs.get(ctx, [])
	entries.append({"t": now_ms(), "cause": cause})
	_logs[ctx] = entries
	_prune(ctx)


func deaths(ctx: String) -> int:
	_prune(ctx)
	return (_logs.get(ctx, []) as Array).size()


func _prune(ctx: String) -> void:
	if not _logs.has(ctx):
		return
	var cfg := config()
	var window := int((cfg.window_seconds if cfg else 900.0) * 1000.0)
	var keep: Array = []
	for e: Dictionary in _logs[ctx]:
		if now_ms() - int(e["t"]) <= window:
			keep.append(e)
	if keep.is_empty():
		_logs.erase(ctx)
	else:
		_logs[ctx] = keep


func threshold(ctx: String) -> int:
	var cfg := config()
	if cfg == null:
		return 999
	return cfg.boss_deaths if ctx.begins_with("boss:") else cfg.room_deaths


## The cause that stopped the player most often in a context (by its first
## segment, "needle/needle_stab" -> "needle"); the latest one of that group.
func main_cause(ctx: String) -> String:
	var counts := {}
	var latest := {}
	for e: Dictionary in _logs.get(ctx, []):
		var c: String = e["cause"]
		var group := c.get_slice("/", 0)
		counts[group] = int(counts.get(group, 0)) + 1
		latest[group] = c
	var best := ""
	var best_n := 0
	for e: Dictionary in _logs.get(ctx, []):
		var group := String(e["cause"]).get_slice("/", 0)
		if int(counts[group]) >= best_n:
			best_n = int(counts[group])
			best = group
	return latest.get(best, "")


# --- The suggestion -----------------------------------------------------------

func _on_player_respawned(_p: Node2D, _spawn: StringName) -> void:
	if _death_context == "":
		return
	var ctx := _death_context
	_death_context = ""
	if deaths(ctx) >= threshold(ctx):
		_pending = ctx


func _process(_delta: float) -> void:
	if _pending == "" or SceneRouter.transitioning or MenuScreen.open_count > 0 or get_tree().paused:
		return
	var ctx := _pending
	_pending = ""
	show_suggestion(ctx)


## Why no card may open now ("" = it may). Rule filtering is separate.
func suppressed_reason(ignore_limits := false) -> String:
	if not Settings.assist_suggestions:
		return "off"
	if Challenges.active():
		return "challenge"
	if CinematicMode.theatre:
		return "theatre"
	var room := SceneRouter.current_room as Room
	if room == null or not room.world_room:
		return "not_world_room"
	if dev_quiet and DevActions.available():
		return "dev_quiet"
	if ignore_limits:
		return ""
	var cfg := config()
	if _cooldown_until >= 0 and now_ms() < _cooldown_until:
		return "cooldown"
	if cfg != null and _shown_this_session >= cfg.max_per_session:
		return "session_cap"
	return ""


## The card's data for a context, or {} when nothing would be offered:
## {context, title, cause, deaths, text, keys, values}.
func suggestion_for(ctx: String) -> Dictionary:
	var cfg := config()
	if cfg == null:
		return {}
	var cause := main_cause(ctx)
	var picked := pick_rule(cfg, ctx.begins_with("boss:"), cause)
	if picked.is_empty():
		return {}
	var rule: AssistRule = cfg.rules[int(picked["rule"])]
	return {"context": ctx, "title": str(_titles.get(ctx, "")), "cause": cause, "deaths": deaths(ctx),
		"text": rule.text, "keys": picked["keys"], "values": picked["values"]}


## Opens the card for a context if nothing suppresses it. Returns whether it
## was offered. `ignore_limits` (dev trigger) skips the cooldown and the cap.
func show_suggestion(ctx: String, ignore_limits := false) -> bool:
	if suppressed_reason(ignore_limits) != "":
		return false
	var card := suggestion_for(ctx)
	if card.is_empty():
		return false
	_shown_this_session += 1
	EventBus.assist_suggested.emit(ctx, str(card["cause"]), int(card["deaths"]))
	MenuHost.context = card
	EventBus.menu_requested.emit(&"assist_suggest")
	# MenuHost copies (and clears) the context when it opens the card; with
	# no host listening nothing may leak into the next open.
	MenuHost.context = {}
	return true


## Every answer on the card forgets that context's deaths (R11.4); only an
## armed "Not now" starts the cooldown (R11.11).
func _on_answered(ctx: String, answer: StringName, _key: String) -> void:
	_logs.erase(ctx)
	if answer == &"later":
		var cfg := config()
		_cooldown_until = now_ms() + int((cfg.cooldown_seconds if cfg else 1200.0) * 1000.0)


## Dev console "Trigger assist suggestion (current room)": fills the room log
## to its threshold and offers the card now (cooldown and cap ignored).
func dev_trigger_here() -> bool:
	var room := SceneRouter.current_room as Room
	if room == null:
		return false
	var ctx := "room:%s" % SceneRouter.current_room_path
	_titles[ctx] = room.room_name
	while deaths(ctx) < threshold(ctx):
		record_death(ctx, "dev")
	return show_suggestion(ctx, true)


# --- Rules (pure; tests call them without a tree) --------------------------------

## First rule whose scope and cause match and that still has something to
## offer: {rule: index, keys: PackedStringArray, values: Array}, or {}.
static func pick_rule(cfg: AccessibilityConfig, is_boss: bool, cause: String) -> Dictionary:
	for i in cfg.rules.size():
		var r := cfg.rules[i]
		if r == null or (r.boss_only and not is_boss):
			continue
		if r.cause_prefix != "" and not cause.begins_with(r.cause_prefix):
			continue
		var keys := PackedStringArray()
		var values: Array = []
		for k in r.suggest.size():
			if k >= r.values.size():
				break
			if should_offer(r.suggest[k], r.values[k]):
				keys.append(r.suggest[k])
				values.append(r.values[k])
		if not keys.is_empty():
			return {"rule": i, "keys": keys, "values": values}
	return {}


## Whether a key may be offered at `value` given the player's current setting.
static func should_offer(key: String, value: Variant) -> bool:
	if not key in Settings:
		return false
	var current: Variant = Settings.get(key)
	for row: Array in NEVER_FROM:
		if row[0] == key and _in_set(current, row[1]):
			return false
	return not _in_set(current, assisted_values(key, value))


static func assisted_values(key: String, value: Variant) -> Array:
	for row: Array in ASSISTED:
		if row[0] == key and same_value(row[1], value):
			return row[2]
	return [value]


static func _in_set(v: Variant, values: Array) -> bool:
	for x: Variant in values:
		if same_value(v, x):
			return true
	return false


## Equality that never compares bool with a number (4.3 raises on int ==
## bool); ints and floats compare by value (a .cfg may load 1 as 1.0).
static func same_value(a: Variant, b: Variant) -> bool:
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if na and nb:
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b
