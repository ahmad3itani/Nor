class_name RuleWatch
extends RefCounted
## A run's rules (M9 D2 §3.3): no hit, movement only and the time limit. It
## only listens and reports through `on_fail(outcome, cause)`; Challenges
## decides what ends. Deaths go through Room.death_override instead.
##
## A hit is a hit (D-148, D4 §8.2): fail_on_damage fails on ANY
## player_damaged emission, amount 0 included (the damage assist can reduce a
## hit to nothing but still emits), and falls and Core burnout count too. The
## message names the cause neutrally ("Run over: fell"), never "FAILED" (§24).
## fail_on_attack listens to the player's own attack_started and fired, never
## EventBus.ranged_fired, which a reload also emits.

## (outcome: int, cause: String) -> void
var on_fail: Callable
var challenge: ChallengeData
## Hits this stage (every damage emission, rules or not: the rank reads it).
var hits: int = 0
## The cause line of the last hit.
var last_cause: String = ""
var armed: bool = false
var _player: Player = null


func _init(ch: ChallengeData = null, fail: Callable = Callable()) -> void:
	challenge = ch
	on_fail = fail


func connect_bus() -> void:
	if not EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.connect(_on_player_damaged)


func disconnect_all() -> void:
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)
	_unbind_player()
	armed = false


## The room's player (each room load spawns a new one).
func bind_player(p: Player) -> void:
	_unbind_player()
	_player = p
	if p == null or challenge == null or not challenge.fail_on_attack:
		return
	p.combat.attack_started.connect(_on_attack)
	p.combat.fired.connect(_on_attack)


func _unbind_player() -> void:
	if _player and is_instance_valid(_player) and is_instance_valid(_player.combat):
		if _player.combat.attack_started.is_connected(_on_attack):
			_player.combat.attack_started.disconnect(_on_attack)
		if _player.combat.fired.is_connected(_on_attack):
			_player.combat.fired.disconnect(_on_attack)
	_player = null


## The neutral line for a damage source (PlayerCombat.last_damage_source).
static func cause_line(source: String) -> String:
	match source:
		"pit":
			return Loc.t("Run over: fell")
		"burnout":
			return Loc.t("Run over: Core ran dry")
	return Loc.t("Run over: hit taken")


func _on_player_damaged(_amount: int, _health: int) -> void:
	if not armed:
		return
	hits += 1
	var src := _player.combat.last_damage_source if _player and is_instance_valid(_player) else ""
	last_cause = cause_line(src)
	if challenge and challenge.fail_on_damage and on_fail.is_valid():
		on_fail.call(ChallengeData.Outcome.FAILED_HIT, last_cause)


func _on_attack(_what: Variant = null) -> void:
	if armed and challenge and challenge.fail_on_attack and on_fail.is_valid():
		on_fail.call(ChallengeData.Outcome.FAILED_ATTACK, Loc.t("Run over: attack used"))


## TIME_LIMIT: true once the clock reaches the limit.
func time_up(frames: int) -> bool:
	return challenge != null and challenge.end_on == ChallengeData.EndOn.TIME_LIMIT and challenge.time_limit_s > 0.0 \
		and frames >= roundi(challenge.time_limit_s * RunClock.FPS)
