class_name UpgradeLibrary
extends RefCounted
## Every UpgradeData in res://data/upgrades (D-182), with the buy / grant /
## rebranch rules the stations share. Static, no autoload and no preload of
## data (the autoload preload pitfall): the folder is listed through DataDir
## (X-5) and cached until clear_cache() (Cinematics frees it at exit).
##
## Ownership is flags only: upg_<id> = tiers owned (a Mk III branch counts as
## one tier), upg_<id>_branch = the branch owned (1 Power, 2 Flow, 3 Utility).

const DIR := "res://data/upgrades"

static var _all: Array[UpgradeData] = []
static var _built: bool = false


static func all() -> Array[UpgradeData]:
	if _built:
		return _all
	_built = true
	_all = []
	for path in DataDir.list(DIR):
		var res := load(path)
		if res is UpgradeData:
			_all.append(res as UpgradeData)
	return _all


static func clear_cache() -> void:
	_all = []
	_built = false
	SchematicList.clear_cache()


static func get_upgrade(id: String) -> UpgradeData:
	for u in all():
		if u.id == id:
			return u
	return null


## Tiers owned (0 = none).
static func tier(u: UpgradeData) -> int:
	return Game.flag_int(u.flag())


## The branch owned (0 = none yet).
static func branch(u: UpgradeData) -> int:
	return Game.flag_int(u.branch_flag())


## What the station offers next: [] at max, the three branch tiers together
## when the next step is the branch group, otherwise one tier.
static func next_tiers(u: UpgradeData) -> Array[UpgradeTier]:
	var out: Array[UpgradeTier] = []
	var n := tier(u)
	if n >= u.max_tier():
		return out
	var b := u.branch_start()
	if b >= 0 and n == b:
		for i in range(b, u.tiers.size()):
			out.append(u.tiers[i])
	elif n < u.tiers.size():
		out.append(u.tiers[n])
	return out


## The tier's `requires` that do not hold now (the menu's "Needs:" line).
static func missing(t: UpgradeTier) -> PackedStringArray:
	var out := PackedStringArray()
	for c in t.requires:
		if not Game.check_condition(c):
			out.append(c)
	return out


## Buyable now: it is the next step, not a story-granted tier, every
## requirement holds, the Scrap is there, and no challenge run owns the
## state (D-147: never write Game.state in a run).
static func can_buy(u: UpgradeData, t: UpgradeTier) -> bool:
	if u == null or t == null or t.granted or Challenges.active():
		return false
	if not next_tiers(u).has(t):
		return false
	return missing(t).is_empty() and Game.state.total_scrap() >= t.price


## Spends the Scrap and installs the tier. Returns false (nothing changed)
## when can_buy says no.
static func buy(u: UpgradeData, t: UpgradeTier) -> bool:
	# D-147: a challenge run owns Game.state; never buy into the sandbox. A
	# refusal rather than an assert, so a caller in a run just gets false.
	if Challenges.active():
		push_warning("UpgradeLibrary.buy refused inside a challenge run (D-147)")
		return false
	if not can_buy(u, t):
		return false
	if not Game.state.spend_scrap(t.price):
		return false
	EventBus.scrap_changed.emit(Game.state.total_scrap())
	_install(u, t, t.price)
	return true


## A story beat installs a granted tier free (D-218). Only
## DialogueData.give_upgrade reaches it (through give()); never kits, sandbox
## states or challenges, so ghosts stay byte-stable.
static func grant(u: UpgradeData, t: UpgradeTier) -> bool:
	if u == null or t == null or not t.granted or Challenges.active():
		return false
	if not next_tiers(u).has(t):
		return false
	_install(u, t, 0)
	return true


## Game.apply_dialogue: grants the next tier of `id` when it is a granted one.
static func give(id: String) -> bool:
	var u := get_upgrade(id)
	if u == null:
		return false
	var nx := next_tiers(u)
	return nx.size() == 1 and grant(u, nx[0])


## Swaps the owned Mk III branch at the workbench (repair 2): a repeatable
## sink, reported outside the one-time bands. Refused in challenges.
static func rebranch(u: UpgradeData, to_branch: int) -> bool:
	if u == null or Challenges.active() or u.branch_start() < 0:
		return false
	if tier(u) < u.max_tier() or to_branch < 1 or to_branch > 3 or to_branch == branch(u):
		return false
	if not Game.state.spend_scrap(u.rebranch_price):
		return false
	EventBus.scrap_changed.emit(Game.state.total_scrap())
	Game.set_flag(u.branch_flag(), to_branch)
	AudioManager.play_sfx(&"upgrade_install")
	EventBus.upgrade_purchased.emit(u.id, tier(u), u.rebranch_price)
	return true


static func _install(u: UpgradeData, t: UpgradeTier, paid: int) -> void:
	var n := tier(u) + 1
	Game.set_flag(u.flag(), n)
	if t.branch != 0:
		Game.set_flag(u.branch_flag(), t.branch)
	AudioManager.play_sfx(&"upgrade_install")
	EventBus.upgrade_purchased.emit(u.id, n, paid)
	_after_install(u, t)


## First-use tips, once per save (hint_<name> flags, carried by NG+). Keyed
## by what the tier does, never by which upgrade it is.
static func _after_install(_u: UpgradeData, t: UpgradeTier) -> void:
	if t.values.has("charge_heavy") and not Game.has_flag("hint_charge"):
		Game.set_flag("hint_charge")
		EventBus.hint_requested.emit(Loc.f("Hold heavy to charge  [{action}]", {"action": _glyph(&"attack_heavy")}), 4.0)
	if t.values.has("surge") and not Game.has_flag("hint_surge"):
		Game.set_flag("hint_surge")
		EventBus.hint_requested.emit(Loc.f("SURGE  [{action}]  Spend Core for a burst. Damage up while it lasts.", {"action": _glyph(&"surge")}), 5.0)
	if t.values.has("parry") and not Game.has_flag("hint_parry"):
		Game.set_flag("hint_parry")
		EventBus.hint_requested.emit(Loc.f("PARRY  [{action}]  Heavy just as it swings.", {"action": _glyph(&"attack_heavy")}), 5.0)


static func _glyph(action: StringName) -> String:
	return InputGlyphs.label(action) if InputMap.has_action(action) else String(action)


## Every upgrade flag (NG+ carry, FlagSandbox, the Deep Rig copy).
static func all_flags() -> PackedStringArray:
	var out := PackedStringArray()
	for u in all():
		out.append(u.flag())
		if u.branch_start() >= 0:
			out.append(u.branch_flag())
	return out


## The owned tiers whose stats apply (the owned branch only).
static func stats_for(u: UpgradeData) -> Array[UpgradeTier]:
	var out: Array[UpgradeTier] = []
	var n := tier(u)
	var b := u.branch_start()
	var plain := u.tiers.size() if b < 0 else b
	for i in mini(n, plain):
		out.append(u.tiers[i])
	if b >= 0 and n > b:
		var br := branch(u)
		if br >= 1 and br <= 3:
			out.append(u.tiers[b + br - 1])
	return out


## Tiers bought with Scrap (count:upgrades:n, the upgrades_bought stat):
## granted tiers are not purchases.
static func total_owned() -> int:
	var n := 0
	for u in all():
		for t in stats_for(u):
			if not t.granted:
				n += 1
	return n


## The act of a tier (0 on the tier = the upgrade's act).
static func tier_act(u: UpgradeData, t: UpgradeTier) -> int:
	return u.tier_act(t)


## The highest tier of `u` whose act is <= `act`, and the branch to hold
## with it (1 when the branch group is included, else 0). Dev/test maxima.
static func act_max(u: UpgradeData, act: int) -> Vector2i:
	var n := 0
	var b := u.branch_start()
	var plain := u.tiers.size() if b < 0 else b
	for i in plain:
		if u.tier_act(u.tiers[i]) > act:
			return Vector2i(n, 0)
		n += 1
	if b >= 0 and u.tier_act(u.tiers[b]) <= act:
		return Vector2i(n + 1, 1)
	return Vector2i(n, 0)


## Sets every upgrade to its act maximum (FlagSandbox.apply_act1_max_state;
## DevActions.unlock_all passes raise_only so a higher tier is kept).
## Writes Game.state through set_flag.
static func apply_act_max(act: int, raise_only: bool = false) -> void:
	for u in all():
		var m := act_max(u, act)
		if raise_only and tier(u) >= m.x:
			continue
		Game.set_flag(u.flag(), m.x)
		if u.branch_start() >= 0:
			Game.set_flag(u.branch_flag(), m.y)


## One-time Scrap sink of every upgrade up to `act_max`, counting only
## tiers whose act is in `final_acts` (empty = every act). A branch group
## counts one price (the highest), a granted tier none (D-218).
static func sink_total(act_limit: int = 99, final_acts: Array = []) -> int:
	var total := 0
	for u in all():
		total += sink_of(u, act_limit, final_acts)
	return total


static func sink_of(u: UpgradeData, act_limit: int = 99, final_acts: Array = []) -> int:
	var total := 0
	for row: Vector2i in sink_rows(u):
		if row.x <= act_limit and (final_acts.is_empty() or final_acts.has(row.x)):
			total += row.y
	return total


## The one-time sinks of `u` as Vector2i(act, price): one per plain tier
## that is bought (granted tiers are skipped) and one for the branch group
## (its highest price, only one branch can be bought).
static func sink_rows(u: UpgradeData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := u.branch_start()
	var plain := u.tiers.size() if b < 0 else b
	for i in plain:
		var t := u.tiers[i]
		if t != null and not t.granted:
			out.append(Vector2i(u.tier_act(t), t.price))
	if b >= 0:
		var top := 0
		for i in range(b, u.tiers.size()):
			top = maxi(top, u.tiers[i].price)
		out.append(Vector2i(u.tier_act(u.tiers[b]), top))
	return out
