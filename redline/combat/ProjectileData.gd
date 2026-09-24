class_name ProjectileData
extends Resource
## How a ranged AttackData travels. Damage/stagger/knockback stay on the
## AttackData so melee and ranged hits resolve through the same code.

@export var speed: float = 520.0
@export var lifetime: float = 0.6
## Number of projectiles per shot (Scattergun pellets).
@export_range(1, 16) var pellets: int = 1
## Total fan angle; pellets are spaced evenly across it (deterministic, readable).
@export var spread_deg: float = 0.0
@export var color: Color = Color("ffe28a")
## Tracer length in px (visual only).
@export var tracer_length: float = 8.0
## Extra targets the projectile passes through before stopping.
@export_range(0, 8) var pierce: int = 0
