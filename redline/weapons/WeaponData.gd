class_name WeaponData
extends Resource
## A weapon (bible §9). Melee weapons define a light chain plus contextual
## attacks; ranged weapons define one shot AttackData with a ProjectileData.

enum Kind { MELEE, RANGED }

@export var id: StringName
@export var display_name: String = ""
@export var kind: Kind = Kind.MELEE

@export_group("Melee")
@export var light_chain: Array[AttackData] = []
@export var heavy: AttackData
## Heavy while holding up on the ground: launches enemies (follow with a jump-cancel).
@export var launcher: AttackData
@export var air_light: AttackData
@export var air_heavy: AttackData

@export_group("Ranged")
@export var shot: AttackData
@export var fire_interval: float = 0.2
@export var ammo_max: int = 8
## Seconds without firing before the magazine refills (also starts when empty).
@export var reload_time: float = 1.0
## Pushback on the shooter: small on the ground, a real nudge in the air
## (a movement interaction; the full Recoil Launch is a later unlock).
@export var ground_recoil: float = 20.0
@export var air_recoil: float = 0.0
## Where shots leave from, relative to the feet, in facing space.
@export var muzzle_offset: Vector2 = Vector2(8, -20)
@export var fire_sfx: StringName = &"shoot_pistol"


func all_attacks() -> Array[AttackData]:
	var out: Array[AttackData] = []
	out.append_array(light_chain)
	for a in [heavy, launcher, air_light, air_heavy, shot]:
		if a:
			out.append(a)
	return out


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("weapon has no id")
	match kind:
		Kind.MELEE:
			if light_chain.is_empty():
				errors.append("%s: melee weapon needs a light chain" % id)
		Kind.RANGED:
			if shot == null or shot.projectile == null:
				errors.append("%s: ranged weapon needs a shot with projectile data" % id)
			if ammo_max <= 0 or fire_interval <= 0.0:
				errors.append("%s: ammo_max and fire_interval must be > 0" % id)
	for a in all_attacks():
		errors.append_array(a.validate())
	return errors
