extends Node
## Global, explicitly typed signals for cross-system communication.
##
## Rule (bible §31): only add signals here when two systems genuinely have no
## better owner to talk through. Every signal is declared and documented; no
## generic "event(name, payload)" dumping ground.

## A player instance entered the world and is ready to be observed (camera, debug UI).
signal player_spawned(player: Node2D)
## The player was reset to a spawn marker (death, reset hotkey, teleport).
signal player_respawned(player: Node2D, spawn_id: StringName)
## Movement state machine transition, for debug UI / future audio + VFX hooks.
signal player_state_changed(from_state: StringName, to_state: StringName)
## Player touched ground after being airborne. impact_speed is the pre-landing fall speed (px/s).
signal player_landed(impact_speed: float)
## Ask the active camera to add shake trauma (0..1). Scaled by Settings.screen_shake_scale.
signal camera_shake_requested(trauma: float)
## Ask the active camera for a one-off positional kick (px), e.g. landing/hit impulse.
signal camera_impulse_requested(offset: Vector2)
## A room finished loading into the world viewport.
signal room_loaded(room: Node)
## Movement tuning was swapped or hot-reloaded (debug overlay shows the preset name).
signal movement_config_changed(config: Resource)
