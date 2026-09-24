class_name EnemyData
extends Resource
## Stats and tuning for one enemy archetype (bible §16). Behaviour-specific
## knobs live on the behavior node in the variant scene; everything the shared
## Enemy body needs lives here.

@export var id: StringName
@export var display_name: String = ""

@export_group("Durability")
@export var max_health: float = 30.0
## Poise absorbs stagger damage; at 0 the enemy staggers and poise refills.
@export var max_poise: float = 10.0
@export var stagger_time: float = 0.45
## Knockback is divided by mass.
@export var mass: float = 1.0
## Armored enemies shrug off most knockback unless staggered or launched.
@export var armored: bool = false
@export_range(0.0, 1.0) var armor_knockback_scale: float = 0.15

@export_group("Movement")
@export var move_speed: float = 50.0
@export var accel: float = 600.0
@export var friction: float = 700.0
@export var gravity: float = 900.0
@export var max_fall_speed: float = 420.0
## Flying enemies ignore gravity until staggered/launched/killed.
@export var flying: bool = false
@export var body_size: Vector2 = Vector2(12, 26)

@export_group("Awareness & attacks")
@export var aggro_range: float = 220.0
@export var attacks: Array[AttackData] = []
## Pause between the end of one attack and the next wind-up.
@export var attack_cooldown: float = 1.0

@export_group("Launch physics")
## Launched/killed bodies moving faster than this damage what they hit.
@export var impact_speed: float = 170.0

@export_group("Rewards")
@export var reactor_reward: float = 12.0
@export var style_value: float = 40.0
@export var scrap_drop: int = 5

@export_group("Look")
@export var color: Color = Color("c75b5b")


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("enemy has no id")
	if max_health <= 0.0 or max_poise <= 0.0 or mass <= 0.0:
		errors.append("%s: health, poise and mass must be > 0" % id)
	if attacks.is_empty():
		errors.append("%s: needs at least one attack" % id)
	for a in attacks:
		errors.append_array(a.validate())
		# Readability rule (bible §17): enemy wind-ups must be long enough to see.
		if a.startup < 0.3:
			errors.append("%s/%s: telegraph (startup) shorter than 0.3s" % [id, a.id])
	return errors
