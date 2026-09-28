class_name JuiceDirector
extends Node
## Rook's event-driven combat juice (presentation overhaul T06). PlayerFeedback
## creates one per Player; it only listens to EventBus and spawns visual
## nodes into Rook's room, so gameplay never depends on it:
##   enemy_killed    -> Pulse motes stream from the body into Rook's seam
##   perfect_dodge   -> the perfect_dodge flourish (+ an afterimage when the
##                      visual offers spawn_afterimage)
##   player_healed   -> the heal rise at Rook's feet
##   circuit_granted -> PowerFlourish "circuit" (an upgrade installed)
##   weapon_granted  -> PowerFlourish "weapon" (the weapon rises into Rook)
## and keeps a CoreAura on Rook exactly while he is in Flow.
##
## Every sprite has the old placeholder behind it (HitSpark particles, drawn
## motes). It uses its own RandomNumberGenerator, never the global one, so
## route, boss and ghost runs stay byte-stable. No camera access: shake stays
## with EventBus.camera_shake_requested at the gameplay call sites.

const MOTES_MIN := 4
const MOTES_MAX := 8
const BOSS_MOTES := 16
const DODGE_AFTERIMAGE := 0.6
## The heal placeholder (the sparks PlayerCombat.finish_heal used to spawn).
const HEAL_FALLBACK_COLOR := Color("7dff9a")

var player: Player
var aura: CoreAura
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "JuiceDirector"
	rng.seed = 0x7E06
	if player == null:
		player = _find_player()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.perfect_dodge.connect(_on_perfect_dodge)
	EventBus.player_healed.connect(_on_player_healed)
	EventBus.circuit_granted.connect(_on_circuit_granted)
	EventBus.weapon_granted.connect(_on_weapon_granted)


func _exit_tree() -> void:
	for pair in [[EventBus.enemy_killed, _on_enemy_killed], [EventBus.perfect_dodge, _on_perfect_dodge],
			[EventBus.player_healed, _on_player_healed], [EventBus.circuit_granted, _on_circuit_granted],
			[EventBus.weapon_granted, _on_weapon_granted]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _find_player() -> Player:
	var n := get_parent()
	while n != null and not (n is Player):
		n = n.get_parent()
	return n as Player


func _ok() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and player.get_parent() != null


func _world() -> Node:
	return player.get_parent()


func seam() -> Vector2:
	return player.global_position + PulseMotes.SEAM_OFFSET


func _process(_delta: float) -> void:
	if not _ok():
		return
	var flow := player.reactor != null and player.reactor.config != null and player.reactor.in_flow()
	if flow and not is_instance_valid(aura):
		aura = CoreAura.attach(player)
	elif not flow and is_instance_valid(aura):
		aura.queue_free()
		aura = null


## Motes for a kill: 4-8 (a boss 16) before the ambient motion scale.
func mote_count(boss: bool) -> int:
	return BOSS_MOTES if boss else rng.randi_range(MOTES_MIN, MOTES_MAX)


func _on_enemy_killed(enemy: Node2D, _hit: HitInfo) -> void:
	if not _ok() or not is_instance_valid(enemy):
		return
	var at := enemy.global_position
	var boss := false
	if enemy is Enemy and (enemy as Enemy).data != null:
		var data := (enemy as Enemy).data
		at += Vector2(0, -data.body_size.y * 0.5)
		boss = data.boss
	PulseMotes.spawn(_world(), at, player, mote_count(boss), rng)


func _on_perfect_dodge(_attacker: Node2D) -> void:
	if not _ok():
		return
	var at := player.global_position + Vector2(0, -18)
	if VfxOneShot.spawn(_world(), &"perfect_dodge", &"flourish", at, {"facing": player.facing}) == null:
		HitSpark.spawn(_world(), at, Vector2.UP, Color("a9a3b8"), 8, 80.0)
	if player.visual and player.visual.has_method(&"spawn_afterimage"):
		player.visual.call(&"spawn_afterimage", DODGE_AFTERIMAGE)


func _on_player_healed(_health: int) -> void:
	if not _ok():
		return
	if VfxOneShot.spawn(_world(), &"heal", &"heal_rise", player.global_position, {"follow": player}) == null:
		HitSpark.spawn(_world(), player.global_position + Vector2(0, -18), Vector2.UP, HEAL_FALLBACK_COLOR, 12, 70.0)


func _on_circuit_granted(_id: String) -> void:
	if _ok():
		PowerFlourish.spawn(_world(), seam(), &"circuit", player)


func _on_weapon_granted(id: String) -> void:
	if _ok():
		PowerFlourish.spawn(_world(), player.global_position + Vector2(0, -16), &"weapon", player, {"weapon_id": id})
