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
## --- Combat (M2) ---
## An enemy resolved a hit (any source). result is a CombatResult value.
signal enemy_damaged(enemy: Node2D, hit: HitInfo, result: int)
## An enemy died. hit.attacker is credited (environmental kills credit whoever launched it).
signal enemy_killed(enemy: Node2D, hit: HitInfo)
signal player_damaged(amount: int, health: int)
signal player_died
## A hit landed inside the perfect-dodge window of a dodge/dash.
signal perfect_dodge(attacker: Node2D)
signal ranged_fired(weapon: Resource, ammo_left: int)
signal ranged_weapon_changed(weapon: Resource)
## Reactor charge changed (bible §6). critical = at/below the critical threshold.
signal reactor_changed(charge: float, max_charge: float, critical: bool)
## Style meter changed (bible §10). rank indexes StyleConfig.rank_names.
signal style_changed(points: float, rank: int)
## --- World & progression (M3) ---
## GameState was replaced (new game / load). Systems re-read it.
signal game_state_reset
signal flag_changed(id: String, value: Variant)
signal scrap_changed(total: int)
## The current room is about to be freed (persist the player's state now).
signal room_leaving(room: Node)
## Shown on entering a world room: district + room name banner.
signal room_entered(district: String, room_name: String)
## Contextual prompt for the nearest interactable ("" = hide).
signal interact_prompt_changed(text: String)
## A short contextual hint (bible §42: tutorial text short and contextual).
signal hint_requested(text: String, seconds: float)
signal anchor_rested(anchor: Node)
signal memory_fragment_found(fragment: Resource)
signal quest_updated(quest: Resource)
## Show a conversation (DialogueBox listens). Game pauses while it is open.
signal dialogue_requested(dialogue: Resource, npc_name: String)
signal dialogue_finished(dialogue: Resource)
## Open a UI menu by id: "loadout", "shop_vell", "shop_mara", "pause".
signal menu_requested(menu_id: StringName)
signal circuit_granted(id: String)
## Equipped Circuits or weapons changed (live player re-applies its loadout).
signal loadout_changed
signal weapon_granted(id: String)
## A breakable secret wall or hidden route was opened.
signal secret_found(id: String)
signal player_healed(health: int)
## Boss fight lifecycle (HUD boss bar, music state).
signal boss_started(boss: Node2D, title: String)
signal boss_phase_changed(boss: Node2D, phase: int)
signal boss_defeated(boss_id: String)
## The vertical slice's ending beat (Relay after the boss): stats card.
signal slice_completed

# M5 world framework.
signal map_pins_changed
signal fast_traveled(from_key: String, to_key: String)
signal map_opened

# M7 district mechanics (Undercity / Lowlight set pieces). Each is recorded by
# autoload/Playtest.gd and reported by PlaytestAnalyzer.
## A power breaker was struck; everything wired to `circuit` reacts (shutters,
## scanners, clamps listen for their own circuit).
signal breaker_hit(circuit: StringName)
## Rook got under a timed power shutter before it dropped. margin_s is the
## time that was left on its countdown (small = a close call).
signal shutter_passed(shutter_id: String, margin_s: float)
## A scanner beam saw Rook. mode is the ScannerData mode when tripped
## (LOW/HIGH/FULL). It does not say live vs calibration (calibration =
## damage 0): Playtest looks the beam up by name and reads its data instead.
signal scanner_tripped(beam_id: String, mode: int)
## A grid clamp dropped; staggered_boss = it landed on a boss and staggered it.
signal clamp_dropped(clamp_id: String, staggered_boss: bool)
## A chase set piece began (Rook crossed its start area).
signal chase_started(chase_id: String)
## The pursuer caught Rook; he restarts from checkpoint index `checkpoint`.
signal chase_caught(chase_id: String, checkpoint: int)
## Rook reached the chase's end area. min_lead is the smallest gap (px of path progress)
## he kept over the pursuer, for tuning how tense the chase really was.
signal chase_completed(chase_id: String, seconds: float, catches: int, min_lead: float)
## A ceiling tracker (Collector eye) locked on to Rook.
signal tracker_locked(tracker_id: String)

# M4 playtest instrumentation.
signal item_purchased(shop_id: StringName, item_id: String, price: int)
## Settings changed in the menu (overlay visibility, volumes).
signal settings_changed
## Tuning panel asks to discard live edits and reload the active preset from disk.
signal movement_config_reload_requested
