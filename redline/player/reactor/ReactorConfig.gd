class_name ReactorConfig
extends Resource
## Redline Core tuning for one difficulty mode (bible §6). The core only
## drains inside Flow Zones; kills, perfect dodges and stylish play refill it.
## At zero it burns health until refilled.

@export var mode_name: String = "Normal"
@export var max_charge: float = 100.0
@export var start_charge: float = 70.0
@export var drain_per_second: float = 5.0
## At or below this the core is "critical": heartbeat, HUD pulse, vignette.
@export var critical_threshold: float = 25.0
## At zero charge, lose 1 health pip every this many seconds.
@export var burnout_interval: float = 1.5
## Multiplies every gain below (Assist > 1, Challenge < 1).
@export var gain_multiplier: float = 1.0

@export_group("Gains")
## Each landed hit adds its AttackData.reactor_gain x this.
@export var hit_gain_scale: float = 1.0
## Hits right after a slide/dodge/dash add this on top (movement feats).
@export var movement_hit_bonus: float = 1.5
@export var perfect_dodge_gain: float = 10.0
## Environmental kills (launched impacts, hazards) add this on top of the kill.
@export var environmental_kill_bonus: float = 8.0
## Kill gain (EnemyData.reactor_reward) grows by this fraction per style rank.
@export var style_rank_kill_bonus: float = 0.15

@export_group("Challenge")
## Reserved for score attack (Redline Challenge mode); not used in M2.
@export var score_multiplier: float = 1.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_charge <= 0.0:
		errors.append("%s: max_charge must be > 0" % mode_name)
	if start_charge > max_charge or start_charge <= 0.0:
		errors.append("%s: start_charge must be within (0, max_charge]" % mode_name)
	if critical_threshold >= max_charge:
		errors.append("%s: critical_threshold must be below max_charge" % mode_name)
	if drain_per_second < 0.0 or burnout_interval <= 0.0:
		errors.append("%s: invalid drain/burnout" % mode_name)
	return errors
