class_name PlayerCombatConfig
extends Resource
## Player-side combat tuning (health, buffers, hurt, perfect dodge).
## Weapon/attack numbers live in WeaponData/AttackData instead.

@export_group("Health")
## Health in pips. Early enemy attacks deal 1 (bible §7: forgiving early game).
@export var max_health: int = 5
## Invulnerability after taking a hit.
@export var hurt_invuln_time: float = 0.9
## Loss of control after taking a hit.
@export var hurt_stun_time: float = 0.22
@export var hurt_knockback: Vector2 = Vector2(150, -160)
## Delay between death and respawn; short on purpose (bible §7 near-instant restart).
@export var respawn_delay: float = 0.4

@export_group("Healing")
## Injectors held after resting at an Anchor (bible §7 "limited healing injectors").
@export var injector_max: int = 2
@export var heal_amount: int = 2
## Channel time standing still; getting hit interrupts it without using the injector.
@export var heal_time: float = 0.55

@export_group("Input")
@export var attack_buffer_time: float = 0.15
## After a chain attack ends, the next light continues the chain within this window.
@export var combo_reset_time: float = 0.35
## Stick Y below this counts as "up" (launcher, aim up).
@export var up_threshold: float = -0.5

@export_group("Air")
## How many air attacks per airtime may set vertical speed (hang). Stops infinite floating.
@export var air_hang_uses: int = 3

@export_group("Perfect dodge")
## A hit that lands within this many seconds of starting a dodge/dash is "perfect".
@export var perfect_dodge_window: float = 0.14
@export var perfect_dodge_hitstop: float = 0.08

@export_group("Movement tech")
## A hit within this time after a slide/dodge/dash counts as a movement transition (style).
@export var movement_tech_window: float = 0.45

@export_group("Hazards")
@export var hazard_damage: int = 1
@export var hazard_bounce: Vector2 = Vector2(0, -330)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_health <= 0:
		errors.append("max_health must be > 0")
	if hurt_stun_time > hurt_invuln_time:
		errors.append("hurt_invuln_time must cover hurt_stun_time")
	if perfect_dodge_window <= 0.0:
		errors.append("perfect_dodge_window must be > 0")
	return errors
