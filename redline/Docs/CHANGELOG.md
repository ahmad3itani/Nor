# REDLINE Changelog

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
