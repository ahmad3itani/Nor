# REDLINE: Decisions Log

Each entry records what was decided, why, and whether it needs a human call.
**FLAG** means the entry deviates from or reads into the Design Bible (`Docs/DESIGN_BIBLE.md`, rule §37.14). Please confirm or overrule these.

---

## D-001: Project lives in `redline/` inside the Nor repository (FLAG)
- **Context:** This session can only reach `ahmad3itani/Nor`, which is an Arabic football-news Next.js app. The bible assumes REDLINE has its own repository.
- **Decision:** The Godot project is self-contained under `redline/` (its own `project.godot`, `.gitignore`, docs), so it doesn't touch the Next.js app's build, lint or deploy.
- **Recommendation:** Move `redline/` into a dedicated repository before M2. `git subtree split --prefix=redline` keeps the history.

## D-002: Engine: Godot 4.3 stable, GDScript, GL Compatibility renderer
- 4.3 is the version this project was built and tested with headless. It has no .NET/C# dependency.
- The Compatibility renderer runs on the widest range of hardware, including older GPUs and Steam Deck. The 2D graybox doesn't need Forward+. We can revisit when 2D lights and VFX arrive (M3).

## D-003: Reference canvas 480×270, Rook collider 12×34 px
- The bible allows 426×240 or 480×270. 480×270 scales by an exact integer to 1080p (×4) and 4K (×8). 426×240 doesn't: it gives ×4.5 at 1080p.
- Rook's standing collider is 34 px tall, inside the bible's 32–48 px target. The low stance (crouch and slide) is 16 px. Both sizes live in `PlayerMovementConfig`.
- The sprite size is not locked. The bible says to validate camera and readability first, which needs human playtesting.

## D-004: Pixel gameplay in a SubViewport, UI at native resolution
- `Main.tscn` renders the world into a 480×270 `SubViewport` with nearest filtering. The window uses the `canvas_items` stretch mode with integer scaling. UI layers such as the debug overlay sit outside the SubViewport, so their text stays sharp. This follows bible §25: "high-resolution UI may overlay pixel gameplay" and "no arbitrary mixing of pixel densities".

## D-005: Dodge and Dash share one input; Dash replaces the ground dodge once unlocked (FLAG)
- **Context:** Bible §8 lists "dodge/dash" as a single combat input. §5 makes Dodge part of the starting moveset and Dash a Lowlight unlock. §36 (M1) asks for dodge *and* dash feel.
- **Decision:** One action, `dodge` (Shift / L / C, pad B / RT):
  - Without the Dash unlock, it performs a **Dodge**: 0.22 s, i-frames, one air dodge per airtime.
  - With the Dash unlock, on the ground it performs a **Dash**: faster and shorter, it exits above run speed, and it has short i-frames so the upgrade never feels worse than Dodge. In the air it stays an air dodge until **Air Dash** is unlocked.
- In the lab, **F2** toggles the Dash unlock so testers can compare the two.
- **Open question for design:** should Dash replace the dodge, or live on a separate button (dodge = defensive, dash = traversal)? Moving to two buttons is a small change: add a `dash` action and have `Player.evade_state()` read it.

## D-006: Input map in `project.godot`, parity enforced by a test
- Every gameplay action has at least one keyboard binding and one controller binding. `tests/unit/test_input_map.gd` fails if an action is missing either. Combat actions (`attack_light`, `ranged`, `grapple`, `heal`, …) are already bound for M2 but do nothing yet.
- The debug-only hotkeys F2, F4, F5 and F6 are keyboard-only on purpose. The overlay toggle (L3) and the station cycle (R3) have pad bindings.

## D-007: Movement is a small explicit FSM plus a "motor" body
- `Player.gd` owns timers, collision stance and the physics helpers (gravity, horizontal acceleration, jump, forgiveness). Each state in `player/states/` owns one movement mode and returns the id of the next state. When a state hands off, the next state runs in the same tick, so a press is never lost to a dead frame.
- Rise, apex and fall are **one** Air state with sub-phases, because they differ only in gravity and air control.
- States read a `PlayerInputFrame`, never `Input` directly. The input source can be swapped, which is how tests (and later replays and ghosts, bible §29) drive the player.

## D-008: Jumps are authored as height + time-to-apex, compensated for fixed-step physics
- Designers set `jump_height` and `jump_time_to_apex`, and gravity and launch speed are derived from them. Launch speed is solved for the 60 Hz step, so the height you type is the height you get (56.4 px in play vs 56 authored; the extra is apex hang).

## D-009: Movement additions not named in the bible (FLAG, low risk)
These are standard in the genre and support pillars §2.1 and §2.2. Each can be tuned or disabled in data:
- **Fast-fall:** hold down while falling. To disable it, set `fast_fall_gravity_multiplier` equal to `fall_gravity_multiplier` and `fast_fall_speed` equal to `max_fall_speed`.
- **Land-into-slide:** holding down while landing at speed goes straight into a slide.
- **One-way platform drop-through:** down + jump.
- **Crouch-walk** under low ceilings. A slide that ends under a ceiling becomes a crouch, never a pop-up into geometry.

## D-010: Custom 60-line test runner instead of GUT
- The bible's rule §37.9 says to document every new dependency, and the simplest way to comply was to add none. `tests/TestRunner.tscn` finds `tests/unit/test_*.gd` files and runs every `test_*` method. Tests can await physics frames and return exit code 1 when anything fails. If the suite grows, GUT is the natural upgrade.

## D-011: Physics at 60 Hz, no physics interpolation (for now)
- This keeps the simulation deterministic for tests and for future ghosts and leaderboards.
- The risk is visible stutter on 120/144 Hz monitors. Two experiments are listed in `M1_MOVEMENT_REPORT.md`: Godot 4.3's 2D physics interpolation, and 120 Hz ticks.

## D-012: Camera is custom-driven, not Camera2D smoothing
- A focus point moves only when the player leaves the dead zone. It settles vertically on the floor height, so ordinary jumps don't bob the view.
- Look-ahead scales with speed and holds its position when the player stops. The camera looks down during fast falls.
- Landing kicks use a spring. Shake is trauma² noise, multiplied by `Settings.screen_shake_scale`, which is the accessibility slider hook (0 turns shake off).
- All values live in `CameraConfig` (`data/camera/default_camera.tres`).

## D-013: Placeholder SFX are synthesized from data, not committed as files
- Bible §28 asks for readable audio on jump, land and dash, and §37.10 says not to mass-produce final assets early. Each placeholder sound is a small `SfxDefinition` (waveform, pitch sweep, noise, tone, cooldown) rendered to WAV at startup. That puts zero binary files in git and makes every sound tweakable in the inspector.
- To swap in real audio later, set `override_stream` on the definition. No calling code changes.

## D-014: Presentation lives in `PlayerFeedback`, not in the states
- Sound and dust react to `Player` signals (`jumped`, `landed`, `state_changed`). This keeps the movement motor testable without audio or VFX, and lets M3 art and audio replace feedback wholesale.

## D-015: The tuning panel writes to the live resource
- Sliders change the active `PlayerMovementConfig` in place, so there's no copy-and-apply step and states see the change on the next tick. Save writes the preset `.tres` when run from the editor. Exported builds can't write `res://`, so they save to `user://tuning/`. The panel is mouse-driven and its controls never take keyboard focus, so movement keys keep working while it's open. Like the other debug tools, it has no controller binding (D-006).

## D-016: Shared combat code lives in `combat/` (FLAG, low risk)
- Bible §31 has no folder for code that both the player and enemies use. `AttackData`, `HitInfo`, `Hurtbox`, `Projectile`, `CombatQuery`, `CombatLayers` and `CombatResult` now sit in a top-level `combat/` folder instead of being duplicated under `player/combat` and `enemies/`. `WeaponData` stays in `weapons/`, enemy code in `enemies/`, and player-only combat code in `player/combat/`.

## D-017: Hits are delivered by queries, not by Area2D signals
- Melee hitboxes are rectangles in each attack's data, checked with a physics shape query on every active tick. Projectiles cast a ray each tick. Hurtboxes are passive `Area2D`s.
- This is deterministic within a tick (Area2D overlap signals arrive a frame late), and the tests can rely on it.
- An attack hits each target at most once per swing.

## D-018: Scattergun gets a small mid-air recoil nudge (FLAG)
- **Context:** bible §9 asks for "movement interaction" on every weapon, but **Recoil Launch** is a separate traversal unlock in §5.
- **Decision:** in the air, the Scattergun pushes Rook 190 px/s away from where he aims. Shooting straight down cancels the fall and gives a small hop, well below a jump. The ground push is 90 px/s. The Pistol's recoil is negligible.
- Recoil Launch can later scale `air_recoil` up, or add a charged blast.
- **Open question for design:** keep this nudge, or zero `air_recoil` until the unlock?

## D-019: Perfect dodge = getting hit early in a dodge
- A hit that arrives while dodge/dash i-frames are active **and** within 0.14 s of starting the dodge counts as perfect: no damage, a short freeze, style and core rewards (bible §8).
- Later dodge i-frames still avoid damage, but give no reward.
- An evaded attack can't hit again during the same swing (generous, bible §8 "generous Dodge").

## D-020: Hazards ignore dodge i-frames
- Spikes hurt Rook even mid-dodge and bounce him out. Hazards test positioning, not timing, and this is the common genre convention. Enemies die on spikes, which counts as an environmental kill.

## D-021: Health is in pips; enemy attacks deal 1 in M2
- Rook has 5 pips (bible §7: forgiving early game). Player attacks use normal HP numbers against enemies (Needle 30, Shield 60, Drone 20). The field is the same `AttackData.damage`, interpreted by the receiver.

## D-022: Burnout drains health rather than killing instantly (FLAG)
- The bible says the core "burns energy continuously" but doesn't say what happens at zero. The prototype drains 1 pip every 1.5 s at zero (3 s on Assist, 1 s on Challenge), so an empty core is urgent but recoverable by fighting.
- **Open question for design:** instant death, health drain, or something else, such as losing access to abilities?

## D-023: Style rewards stay small
- Bible §10 says style must never block story. The only mechanical reward in M2 is a bigger core refill on kills at higher ranks (+15% per rank). Scrap, medals and leaderboard score come with M3 or later.

## D-024: Enemies don't physically block Rook
- Enemy bodies collide with the world, but not with Rook or with each other. A simple separation force stops them from stacking.
- This keeps high-speed movement (pillar §2.1) from getting snagged on crowds, at the cost of Rook being able to stand inside an enemy. Point-blank shots handle that case (see the report, §6).
- Revisit if playtests say enemies feel "ghostly".

## D-025: Main now boots into the Combat Lab
- M2 is the current milestone, so the game starts in the Combat Lab. **F12** switches to the Movement Lab. Both labs share the same Room, player, camera and dev keys.

