class_name NewGamePlus
extends RefCounted
## New Game+ (M9 D3 §2, bible §30, D-153): after the Act I close the same
## profile starts again with a carry-over (weapons, Circuits, banked Scrap,
## shop upgrades, Core Shards that stay found) and, optionally, remixed rooms
## and the Dash from the start. The cycle lives in the int flag ng_cycle
## (0/absent = first run). The cleared save is archived first
## (SaveManager.archive_profile, "cycle<N>"); the game never loads the
## archive back (D-153 as amended, R09.5: only the dev page restores it).
##
## carry() is pure (tests call it directly); begin() does the autoload work.

const CONFIG_PATH := "res://data/ngplus/ng_plus.tres"
## Where a known dialogue's flags come from (R09.12): only conversations.
const DIALOGUE_DIRS: PackedStringArray = ["res://data/npcs/", "res://data/arcs/"]

static var _config: NgPlusConfig = null
## persist_id -> {"kind": Collectible.Kind, "secret": bool} over every
## district room (built once; the carry and the secret count read it).
static var _collectibles: Dictionary = {}
## Room scene path -> {persist_id: true} of its secret Scrap stashes.
static var _secret_by_room: Dictionary = {}
## Flags a conversation sets (DialogueData.set_flags under DIALOGUE_DIRS).
static var _dialogue_flags: PackedStringArray = []
static var _dialogue_flags_built: bool = false


static func config() -> NgPlusConfig:
	if _config == null:
		_config = load(CONFIG_PATH) as NgPlusConfig
		if _config == null:
			_config = NgPlusConfig.new()
	return _config


## Whether this save data may start NG+: the build allows it and the profile
## closed Act I (act1_complete, or slice_end_seen from before M8, which
## Game.load_game turns into act1_complete).
static func can_begin(data: Dictionary) -> bool:
	if not BuildInfo.enabled(&"ngplus") or data.is_empty():
		return false
	var flags: Dictionary = data.get("flags", {})
	return bool(flags.get("act1_complete", false)) or bool(flags.get("slice_end_seen", false))


static func cycle() -> int:
	return Game.flag_int(config().cycle_flag)


## The cycle of raw save data (JSON numbers are floats, hence int()).
static func cycle_of(data: Dictionary) -> int:
	return int((data.get("flags", {}) as Dictionary).get(config().cycle_flag, 0))


## "" for the first run, "NG+" for cycle 1, "NG+2" onwards, "NG+9+" past the
## cap (a brand label, the same in every locale).
static func cycle_label(n: int) -> String:
	if n <= 0:
		return ""
	if n == 1:
		return "NG+"
	var cap := config().max_cycle_label
	return "NG+%d+" % cap if n > cap else "NG+%d" % n


## Whether the live profile chose the remix / the early Dash.
static func remix_on() -> bool:
	return Game.has_flag(config().remix_flag)


static func keep_dash_on() -> bool:
	return Game.has_flag(config().keep_dash_flag)


# --- Carry ------------------------------------------------------------------------

## Pure: the NG+ GameState built from the cleared one (D3 §2.3 steps 1-6;
## the Null progress step is cut, its records are global). No autoload
## writes. options: {remix: bool, keep_dash: bool}.
static func carry(old: GameState, cfg: NgPlusConfig, options: Dictionary, onboarding: OnboardingConfig) -> GameState:
	var s := GameState.new()
	# Weapons: the kit carries even when the campaign starts unarmed. The
	# blade rack and the pistol drop then only set their flags (WeaponPickup),
	# which CollectorBay's exit needs.
	if cfg.carry_weapons:
		s.owned_weapons.assign(old.owned_weapons)
		s.melee_weapon = old.melee_weapon
		s.ranged_weapon = old.ranged_weapon
	elif onboarding != null and onboarding.enforce:
		s.owned_weapons.assign(onboarding.start_owned_weapons)
		s.melee_weapon = onboarding.start_melee
		s.ranged_weapon = onboarding.start_ranged
	if cfg.carry_circuits:
		s.owned_circuits.assign(old.owned_circuits)
		s.equipped_circuits.assign(old.equipped_circuits)
	if cfg.carry_core_shards:
		s.core_shards = old.core_shards
	if cfg.carry_scrap_banked:
		s.scrap_banked = old.scrap_banked
	# Unbanked Scrap is lost, like a death; the dropped cache is gone.
	s.scrap_unbanked = 0
	s.dropped_scrap = {}
	# R09.2: shard spots stay found (a husk marks them) and plain Scrap
	# bundles stay taken; secret stashes and breakable walls refill.
	var index := collectible_index()
	for id: String in old.collected:
		var info: Dictionary = index.get(id, {})
		if info.is_empty():
			continue
		var k := int(info["kind"])
		if (k == Collectible.Kind.CORE_SHARD and cfg.carry_core_shards) \
				or (k == Collectible.Kind.SCRAP_BUNDLE and not bool(info["secret"])):
			s.collected[id] = true
	# Flags: the whitelist, the shop upgrade counters, then the cycle/options.
	var upgrades := _upgrade_flags() if cfg.carry_shop_upgrades else PackedStringArray()
	for f: String in old.flags:
		if cfg.carries_flag(f) or (upgrades.has(f) and not NgPlusConfig.denied(f)):
			s.flags[f] = old.flags[f]
	s.flags[cfg.cycle_flag] = int(old.flags.get(cfg.cycle_flag, 0)) + 1
	s.flags[cfg.remix_flag] = bool(options.get("remix", true))
	s.flags[cfg.keep_dash_flag] = bool(options.get("keep_dash", true))
	if onboarding != null and onboarding.enforce:
		for f: String in onboarding.start_flags:
			if not cfg.skip_start_flags.has(f):
				s.flags[f] = onboarding.start_flags[f]
	# Abilities: only the optional ones, only with the option. The Dash
	# reward flag (unlocked_dash) never carries, so the DashModule still waits
	# in the Warden Tower and the Relay door still asks for it.
	if bool(options.get("keep_dash", true)):
		for a in cfg.optional_abilities:
			s.abilities[a] = true
	# The archive: one row per finished cycle, and every scene or
	# conversation already seen (the short skip hold, instant known text).
	var arch: Dictionary = old.ng_archive.duplicate(true)
	var cycles: Array = (arch.get("cycles", []) as Array).duplicate(true)
	cycles.append({"cycle": int(old.flags.get(cfg.cycle_flag, 0)), "play_time_sec": old.play_time_sec,
		"deaths": old.deaths, "fragments": old.memory_fragments.size(), "secrets": secrets_found_in(old)})
	var seen: Array = []
	for f in arch.get("seen_flags", []):
		if not seen.has(String(f)):
			seen.append(String(f))
	var dialogue := dialogue_flags()
	for f: String in old.flags:
		if not bool(old.flags[f]):
			continue
		if (f.begins_with("seen_seq_") or f.begins_with("mem_seen_") or dialogue.has(f)) and not seen.has(f):
			seen.append(f)
	seen.sort()
	s.ng_archive = {"cycles": cycles, "seen_flags": seen}
	# R09.1: dev taint is sticky (D-145); NG+ never launders it.
	s.dev_tainted = old.dev_tainted
	return s


## Secrets the profile found (the same ids SliceStats counts).
static func secrets_found_in(s: GameState) -> int:
	var n := 0
	for id in SliceStats.totals()["secret_ids"]:
		if s.collected.has(id):
			n += 1
	return n


static func _upgrade_flags() -> PackedStringArray:
	var out := PackedStringArray()
	for path in DataDir.list("res://data/shops"):
		var shop := load(path) as ShopData
		if shop == null:
			continue
		for item in shop.items:
			if item != null and item.upgrade_flag != "" and not out.has(item.upgrade_flag):
				out.append(item.upgrade_flag)
	return out


## Every flag a conversation sets (R09.12), from the flags-only content pass.
static func dialogue_flags() -> PackedStringArray:
	if _dialogue_flags_built:
		return _dialogue_flags
	_dialogue_flags_built = true
	_dialogue_flags = PackedStringArray()
	var v := ContentValidator.new().run(true)
	for f: String in v.producers:
		if _from_dialogue(v.producers[f]):
			_dialogue_flags.append(f)
	_dialogue_flags.sort()
	return _dialogue_flags


static func _from_dialogue(paths: Array) -> bool:
	for p: String in paths:
		for d in DIALOGUE_DIRS:
			if p.begins_with(d):
				return true
	return false


# --- Secret stashes and shard spots ---------------------------------------------------

## persist_id -> {kind, secret} for every Collectible in the district rooms.
static func collectible_index() -> Dictionary:
	if not _collectibles.is_empty():
		return _collectibles
	for path in SliceStats.room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		var secret := secret_bundles_in(inst)
		_secret_by_room[path] = secret
		for n in inst.find_children("*", "Collectible", true, false):
			var c := n as Collectible
			_collectibles[c.persist_id] = {"kind": int(c.kind), "secret": secret.has(c.persist_id)}
		inst.free()
	return _collectibles


## The secret Scrap stashes of one room instance (in the tree or not): a
## SCRAP_BUNDLE within config().secret_spot_radius of a BreakableWall or of
## a fragment/shard spot. Positions are summed up to `room` by hand, so an
## instance outside the tree works too.
static func secret_bundles_in(room: Node) -> Dictionary:
	var r := config().secret_spot_radius
	var spots: Array[Rect2] = []
	var bundles: Array = []
	for n in room.find_children("*", "", true, false):
		if n is BreakableWall:
			spots.append(Rect2(_pos_in(room, n), (n as BreakableWall).size))
		elif n is Collectible:
			var c := n as Collectible
			if c.kind == Collectible.Kind.SCRAP_BUNDLE:
				bundles.append(c)
			else:
				spots.append(Rect2(_pos_in(room, c), Vector2.ZERO))
	var out := {}
	for c: Collectible in bundles:
		var at := _pos_in(room, c)
		for rect in spots:
			if _distance_to_rect(at, rect) <= r:
				out[c.persist_id] = true
				break
	return out


## Whether `c` (a live Collectible) is a secret stash of its room.
static func is_secret_bundle(c: Collectible) -> bool:
	if c.kind != Collectible.Kind.SCRAP_BUNDLE:
		return false
	var room := c.owner if c.owner != null else c.get_parent()
	if room == null:
		return false
	var key := room.scene_file_path if room.scene_file_path != "" else str(room.get_instance_id())
	if not _secret_by_room.has(key):
		_secret_by_room[key] = secret_bundles_in(room)
	return (_secret_by_room[key] as Dictionary).has(c.persist_id)


## Scrap a secret stash pays in this cycle (R09.2: a quarter in NG+).
static func stash_payout(amount: int) -> int:
	return roundi(amount * config().secret_scrap_scale) if cycle() >= 1 else amount


static func _pos_in(room: Node, n: Node) -> Vector2:
	var p := Vector2.ZERO
	var cur := n
	while cur != null and cur != room:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p


static func _distance_to_rect(p: Vector2, rect: Rect2) -> float:
	var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	return p.distance_to(q)


# --- Begin ------------------------------------------------------------------------

## Why the last begin() refused ("" after a success): tests and the dev page.
static var last_refusal: String = ""


## Archive, convert, save, emit, travel. Returns false if refused (nothing
## changed on disk or in Game then, except the title's load of profile 1).
## options: {from: "title" | "", remix: bool, keep_dash: bool}.
static func begin(options: Dictionary) -> bool:
	last_refusal = ""
	var from_title := String(options.get("from", "")) == "title"
	if from_title:
		# At a fresh boot Game.state is the default GameState, and after Save &
		# Quit it is stale: the title only loads in _continue.
		if not Game.load_game(1):
			last_refusal = "no save"
			return false
	if not can_begin(Game.state.to_dict()):
		last_refusal = "Act I not closed"
	elif Challenges.active():
		last_refusal = "a challenge is running"
	elif Cinematics.locks_input():
		last_refusal = "a scene is playing"
	elif SceneRouter.transitioning:
		last_refusal = "a room is loading"
	if last_refusal != "":
		return false
	# In play (the dev page), the archive must hold the cleared state as it
	# is now, not the last Anchor save.
	if not from_title and Game.save_game() != OK:
		last_refusal = "save failed"
		return false
	if SaveManager.archive_profile(Game.profile_id, "cycle%d" % cycle()) != OK:
		last_refusal = "archive failed"
		return false
	var s := carry(Game.state, config(), options, Game.onboarding)
	# Like Game.start_campaign: a fresh campaign clock that may post a best.
	s.igt_frames = 0
	s.igt_splits = {}
	s.igt_complete = true
	Game.state = s
	Game.abilities = PlayerAbilities.new()
	for key: String in s.abilities:
		if key in Game.abilities:
			Game.abilities.set(key, bool(s.abilities[key]))
	# A new session: no respawn from the finished run's entry (T11 reads these).
	Game._session_entry_room = ""
	Game._session_entry_id = &""
	EventBus.game_state_reset.emit()
	EventBus.ng_plus_started.emit(cycle())
	Game.save_game()
	Playtest.begin_session("ng_plus")
	SceneRouter.transition_to(Game.campaign_start_room(), Game.campaign_start_entry())
	return true


## SkipGate helper: a seen_seq_* / mem_seen_* flag (or a conversation's flag)
## the profile saw in an earlier cycle.
static func knows_seen_flag(f: String) -> bool:
	if f == "":
		return false
	return (Game.state.ng_archive.get("seen_flags", []) as Array).has(f)


## Every flag in `flags` is known from an earlier cycle (T11 DialogueBox).
static func knows_all(flags: PackedStringArray) -> bool:
	if flags.is_empty() or cycle() < 1:
		return false
	for f in flags:
		if not knows_seen_flag(f):
			return false
	return true


static func clear_cache() -> void:
	_config = null
	_collectibles = {}
	_secret_by_room = {}
	_dialogue_flags = PackedStringArray()
	_dialogue_flags_built = false
	last_refusal = ""
