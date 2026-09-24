# REDLINE Changelog

## 0.3.0-m3: Vertical Slice (awaiting the human playtest)

All M3 scope from bible §36 except production art/audio (D-026). Development stops here for the §44 playtest. Report: `M3_VERTICAL_SLICE_REPORT.md`.

### World framework
- `GameState` profile, and save schema v2 with v0→v1→v2 migrations and atomic writes.
- `SceneRouter` room transitions: fade, entry markers, carried momentum.
- Anchors: save, heal, refill, bank Scrap, set respawn, open the loadout.
- Death returns you to the last Anchor, and unbanked Scrap drops as a recoverable cache (toggle in Settings).
- Pits cost one pip and return you to safe ground, never to a ledge lip (`safe_ground_reach`).
- Healing injectors: channelled, and interruptible without using the injector. Mara sells an upgrade.
- Interaction system: prompts with device glyphs, levers and flag switches, gates, and ability pickups.

### Content
- **The Relay** hub: Orr, Mara and Vell, two shops, an Anchor, and the lift shortcut.
- **Lowlight route:** Flooded Alley, Market Run, Apartment Stack, Neon Roofs, Bell Tower and Warden Tower.
- **Enemies:** Hopper, Watcher (a mounted sentry that needs line of sight) and the Enforcer elite, joining the Needle, Shield and Scout Drone.
- **Boss: Warden Krail.**
  - 6 attacks, with no repeats;
  - phase 2 at 50%: faster telegraphs and two summoned Needles;
  - a jumpable shockwave;
  - a locked, one-screen arena that remembers the win.
  
  He drops the **Dash** module.
- **Weapons:** Split Katars and the Heavy Revolver, for 5 in total.
- **Circuits:** 12 declarative Circuits, Core Capacity with Core Shards, and loadouts at Anchors. See `CIRCUITS.md`.
- **Quest: Dead Air.** Three signal repeaters; the reward is Scrap, Longline, and Emergency Loop unlocking in the shop.
- **Secrets:** 10 (breakable walls, 3 Memory Fragments with lore cards, 3 Core Shards) and a Dash-gated revisit.

### Presentation (placeholder)
- District themes: a procedural parallax skyline, rain, props and neon signs.
- `MusicDirector`: five procedural stems mixed by state.
- Menus: title, pause, journal, settings (now saved), loadout, shops and dialogue. All are controller-first.
- HUD: injectors, Scrap, interaction prompts, hints, the area banner, the boss bar and lore cards.
- `Docs/ART_BIBLE.md`: the rules final assets must follow.

### Tooling and tests
- 130 tests (59 new).
- `devtools/RouteBot` plays every slice room entrance-to-exit with real physics (`test_slice_routes`).
- Structural checks cover links, spawns, persistent ids and boss wiring.
- `PerfProbe` takes `--room=` and `--at=`.
- The capture tour has `--tour=slice` and `--tour=ui`.
- The debug overlay shows the world state: Scrap, Anchor, Circuits, quests and secrets.
- The test runner counts scripts that fail to parse as failures instead of hanging.

### Fixed (found by the route bot and captures)
- Main-path climbs were 55 px against a 56.4 px jump.
- A sign pole walled off Neon Roofs.
- A scaffold you bonked on.
- Dash platforms blocked the alley floor.
- An unreachable stash.
- A pit respawn on a ledge lip could chain into a death.
- A stale "Rest" prompt carried across rooms.
- The boss arena was wider than the screen.

## 0.2.0-m2: Combat Lab (awaiting the human playtest)

All M2 scope from bible §36. Development stops here for a playtest.

### Combat core (`combat/`, `weapons/`)
- Data resources: `AttackData`, `ProjectileData` and `WeaponData`.
- Hit plumbing: `HitInfo`, `CombatResult`, `Hurtbox`, and query-based hit delivery (D-017).
- Ray-cast projectiles that can't tunnel through geometry.
- Weapon data for the Pulse Blade (3-hit chain, heavy, launcher, air light, air heavy), the Service Pistol and the Scattergun.

### Player
- `PlayerCombat` component:
  - health pips;
  - attack buffers and contextual melee selection;
  - hit delivery;
  - ammo and reload;
  - recoil;
  - damage intake, perfect dodge and hazards.
- New `MeleeState` (data-driven lunge, air hang and cancels) and `HurtState`.
- Hitstop that keeps buffering presses during freeze frames.
- Launcher → jump-cancel → air combo loop, slide attacks, dodge-cancels.

### Enemies (`enemies/`)
- A shared `Enemy` body with telegraphed attacks, poise/stagger, armor, launch physics, enemy-on-enemy impacts, wall slams, hazards and death flight.
- `EnemyBehavior` children for the **Needle**, **Shield** (frontal guard, slow turn) and **Scout Drone** (hovers, aimed bolt).
- `EncounterDirector` caps simultaneous attackers at 2.
- `ai_enabled=false` turns any enemy into a practice dummy.

### Reactor and style
- `ReactorCore`:
  - drains only in Flow Zones and burns out at zero;
  - refills from hits, kills, environmental kills, perfect dodges and movement feats;
  - modes: Normal, Story/Assist, Redline Challenge (`Settings.reactor_mode`).
- `StyleMeter` and `PlayerStyle`: ranks D → REDLINE, variety penalty, aerial and movement multipliers, kill and environmental bonuses, decay, damage loss.

### World and UI
- **Combat Lab:** safe dummies plus three Flow Zone arenas with spikes, a slam wall and platforms. Enemies auto-respawn.
- **Hazards and zones:** `SpikeHazard`, `FlowZone`, `EnemySpawner`.
- **HUD:** health, core bar, ammo, style rank, and a critical vignette that respects flash reduction.
- **Debug overlay:** now also shows combat, core and style state.
- 18 new synthesized SFX.
- Dev keys: F9 ranged weapon, F10 respawn enemies, F11 core mode, F12 switch lab.

### Tooling and tests
- 71 tests (34 new).
- The test runner takes `-- --filter=<substring>`.
- `devtools/PerfProbe`: wall-time CPU cost under fight load.
- The capture tour gained `--tour=combat`.

### Fixed
- Point-blank shots missed enemies that overlapped the muzzle or the shooter.
- Projectiles could pass a freed shooter to receivers, which crashes Godot 4.3.
- The M1 performance figure came from an unreliable monitor; corrected in `KNOWN_ISSUES.md`.

## 0.1.1-m1 — M1 polish (still awaiting the human playtest)

Everything here is M1 polish that didn't need playtest feedback. M2 has not started.

- **Live tuning panel (F3):** one slider per numeric `PlayerMovementConfig` value, generated from the resource's properties. Edits apply on the next physics tick. **Save** writes the preset `.tres`, or a copy in `user://tuning/` in exported builds. **Revert** reloads the file from disk.
- **Placeholder SFX** for jump, slide-jump, soft and hard landings, slide, dodge, dash and respawn. Each sound is described as data (`data/audio/placeholder_sfx.tres`) and synthesized to WAV at startup, so no temporary audio files are committed. It plays on a new `SFX` bus that follows `Settings.sfx_volume`.
- **Pixel dust:** on jump takeoff, landings (two sideways puffs that scale with impact), slide start plus a trail while sliding, and ground dashes.
- **High-refresh experiments:** F7 toggles physics interpolation and F8 switches between 60 and 120 Hz physics. Respawns and teleports reset interpolation so they never smear across frames. The overlay shows the tick rate and interpolation state.
- `PlayerFeedback` node: movement events become sound and dust here, so `Player` and the states stay pure physics.
- 37 tests (was 29): SFX bank validity and render levels, feedback sound ids, tuning-panel coverage, write-through and save, and jump height at 120 Hz.
- Added `Docs/.gdignore` so Godot doesn't import report screenshots as game assets.

## 0.1.0-m1 — Movement Lab (awaiting human playtest)

### M0 Foundation
- Godot 4.3 project in `redline/`, with the folder architecture from bible §31.
- Input map with keyboard and controller bindings for every gameplay action, plus debug hotkeys.
- Autoloads:
  - `EventBus`: typed signals.
  - `Settings`: shake, hitstop, flash, vibration and volume, persisted to `user://settings.cfg`.
  - `Game`: ability unlocks.
  - `SaveManager`: versioned JSON, migrations, atomic write and `.bak` recovery.
  - `AudioManager`: stub.
  - `SceneRouter`: loads rooms.
- `Main.tscn` boots a 480×270 pixel SubViewport with native-resolution UI on top.

### M1 Movement
- `PlayerMovementConfig` resource holds every movement value. Three presets ship: default, tight, floaty.
- A state machine drives movement: idle, run, crouch, slide, air, dodge and dash (Dash needs the unlock).
- Feel tech:
  - Coyote time and a jump buffer.
  - Variable jump (jump cut), apex hang with bonus air control, and fast-fall.
  - Turn acceleration, and overspeed decay that preserves momentum.
  - Corner correction and ledge forgiveness.
  - Slide-jump, dodge/dash jump-cancel, and an evade buffer.
  - One-way platforms with drop-through.
- Placeholder Rook: squash/stretch, state tints, a facing visor, afterimages and an i-frame flash.
- `PlayerCamera`: dead zone, speed-sensitive look-ahead, fall look-down, landing spring impulse, and trauma shake scaled by settings.
- Graybox Movement Lab with 8 stations and spawn markers. Reset is instant (R / Back), and falling out of bounds respawns you. Tab / R3 cycles stations.
- Debug overlay (F1 / L3): state, velocity, grounded/low/facing/i-frames, timers, FPS, physics time, last-jump height, distance and airtime, and action counts.
- Dev hotkeys: F2 toggles Dash, F4 toggles slow-mo, F5 hot-reloads the config, F6 cycles presets.

### Tooling and tests
- Headless test runner with 29 tests: data validation, input parity, save/settings, physics-driven movement tests, and lab traversal validation.
- `devtools/MovementProbe`: prints measured jump, slide, dodge and dash distances for each preset.
- `devtools/CaptureTour`: scripted screenshot tour for reports.

### Fixed during M1
- Held jumps peaked about 2.5 px below `jump_height` because of fixed-step integration. Launch speed is now solved for the step.
- The jump-height metric under-reported by one frame of rise.
