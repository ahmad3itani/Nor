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

## D-025: Main now boots into the Combat Lab (superseded by D-029)
- M2 is the current milestone, so the game starts in the Combat Lab. **F12** switches to the Movement Lab. Both labs share the same Room, player, camera and dev keys.

---

# M3: Vertical Slice

## D-026: The slice ships placeholder art and audio, not production quality (FLAG)
- **Context:** Bible §36 says M3 "establishes production-quality art/audio". This build environment has no artists, no licensed assets, and no way to author or judge final pixel art or music. §37.10 also says not to mass-generate final assets before the slice is approved.
- **Decision:** Everything visual and audible is procedural placeholder work that follows a written spec:
  - `DistrictTheme` palettes;
  - a parallax skyline with rain;
  - `Decor` props and `NeonSign`s;
  - synthesized SFX;
  - five procedural music stems.

  `Docs/ART_BIBLE.md` (bible §40) fixes the canvas, scale, origins, palettes, animation and export rules. Final sprites, tiles and audio can then replace placeholders one at a time, with no code changes (`override_stream`, same stem layout, same origins).
- **Needs a human call:** who produces the production art and audio, and whether the §44 test runs on placeholders (recommended: yes, since feel and structure are what §44 measures) or waits for art.

## D-027: New top-level `progression/` folder (FLAG, low risk)
- Bible §31 has no folder for profile state and the economy. `GameState`, `ItemCatalog`, `ShopData`/`ShopItem`, `MemoryFragmentData` and `SliceStats` live in `progression/`. Circuits, quests and dialogue use the bible's own folders (`circuits/`, `quests/`, `dialogue/`).

## D-028: The slice route uses 6 of Lowlight's 10 rooms (FLAG)
- Bible §15 lists Lowlight as Flooded Alley, Market Run, Apartment Stack, Neon Roofs, Power Block, Security Station, Rainline Chase, Smuggler Route, Bell Tower and Warden Tower. The slice builds **Flooded Alley, Market Run, Apartment Stack, Neon Roofs, Bell Tower and Warden Tower**, plus a Relay mini-hub placed next door.
- **Why:** M3 asks for "one polished route" at 15–25 min. Six rooms with a hub, a quest, secrets and a boss is the smallest set that exercises every system.
- **Risk:** pure bot traversal takes ≈ 2 min, so a human run may fall below 15 min. If the playtest says it's short, add Power Block (a power-routing puzzle) and Rainline Chase (a chase room) next. Both are movement-heavy and fit bible §41's "chase rooms, collapsing spaces".
- In the bible's full game, the Relay comes after the Undercity (§42 onboarding). The slice starts at the Relay, with contextual hints standing in for the Undercity's teaching.

## D-029: The game boots to a title screen
- The title offers **Continue** (when a save exists), **New Game**, the two labs, Settings and Quit. `Main.start_room` skips the title for dev tools and capture tours. F12 still cycles the labs. This supersedes D-025.

## D-030: Save schema v2: one JSON profile, migrations, atomic writes
- `GameState.to_dict()` / `from_dict()` holds all profile progress (see the M3 report, §3). `SaveManager` migrates v0 → v1 → v2 in order, writes to a temp file, then renames it, so a crash mid-save can't corrupt the profile. Tests cover round trips and every migration step.
- Room *layout* state (opened walls, collected items, used levers) is stored as persistent ids and flags, not as room snapshots, so rooms can be re-edited without breaking saves.

## D-031: Death, pits and Scrap
- **Death** (bible §7): respawn at the last Anchor after a short beat. Permanent progress is kept. Health, injectors and the Core refill. **Unbanked Scrap drops** as one recoverable cache where you died: dying again before recovering it loses the old cache (the genre rule). Resting at an Anchor banks Scrap, so it's safe. `Settings.currency_loss = false` keeps Scrap on death (the accessibility option §7 asks for).
- **Pits** cost one pip and put you back on the last **safe** ground, never at an Anchor (bible §2.8). Safe means floor at least `safe_ground_reach` (20 px) past your centre on both sides. The route bot found that respawning on a lip while holding forward could chain pit falls into a death.
- **Boss runbacks** (bible §7 "stay short"): the Bell Tower's top Anchor sits one room from Krail.

## D-032: Quest state is derived from flags; dialogue is flag rules
- A quest stage is "done" when its flags are set, so quests have no saved state of their own and can't disagree with the world after a migration or a sequence break. For example, if you trigger a repeater before talking to Orr, the quest shows it done as soon as it starts.
- NPC dialogue is an ordered list of rules (`NpcProfile`): the first rule whose required and forbidden flags match plays its lines, sets flags and gives items. That's enough for bible §19 "conditional dialogue and state" at slice scale. A dialogue editor belongs to M6 tooling.

## D-033: No map, fast travel or Nix in the slice (FLAG)
- Bible §20 (map) and §13 (Nix, fast travel) are M5 scope in §36, and M3 doesn't list them. The slice is linear enough to navigate without a map. The Bell Tower lift is the one shortcut back to the Relay. Please confirm this is acceptable for the §44 test ("did you get lost?" is on the playtest checklist).

## D-034: Circuits are declarative stat modifiers
- See `Docs/CIRCUITS.md`. Capacity is 4 plus the Core Shards found, and loadouts change only at Anchors (bible §7, "Anchors … permit loadout changes"). Saved loadout *presets* (§11) wait until there are enough Circuits to need them.

## D-035: Warden Krail and the Dash unlock
- **Arena:** exactly one screen wide (480 px), so every attack starts on screen ("no cheap offscreen hits"). The gates lock during the fight; losing sends you back to your last Anchor (the Bell Tower's top Anchor is one room away).
- **Krail:** he never repeats an attack back to back, and a backstep breaks up close-range pressure. **Phase 2** at 50%: telegraphs 18% faster, and he summons two Needles once. The ground-slam shockwave is jumpable, and a test proves it.
- **Dash** (bible §15 Lowlight unlock) drops from Krail, so the slice's one Dash-gated secret (the Flooded Alley shard) is a post-boss revisit. That's the bible's "ability-gated revisiting" in miniature. D-005 still applies: Dash replaces the ground dodge.

## D-036: The Neon Roofs slide-jump gap teaches but can't gate (FLAG: tuning question)
- **Measured in the room:** under the M1 tuning, a well-timed slide-jump (jump 2–4 frames after the slide starts, at the lip) clears about 8–15 px more than a run-jump. A late slide bleeds speed to friction and does *worse* than a run-jump. A perfect coyote run-jump or a dodge-jump can also clear the 112 px gap.
- **Decision:** keep the gap at 112 px, where a proper slide-jump lands with about 5 px of margin. Put a **service well** underneath, so a miss costs a short climb instead of a pip. The hint teaches the technique.
- **Open question for the playtest:** should the slide-jump be a stronger long-jump? Options are raising `slide_jump_bonus` (30 → 60 px/s) or `slide_jump_height_ratio` (0.8 → 0.9). Either changes M1 feel, so it's the playtesters' call, not an M3 change.

## D-037: Music is procedural stems mixed by game state
- `MusicDirector` renders five synced stems (pad, bass, drums, arp, lead; 96 BPM, A minor) once at startup on a worker thread, then fades layers by state: title, hub, explore, flow (combat), boss and aftermath. Real music later supplies five equal-length stems per district with the same names (Art Bible §10). Headless runs skip rendering.

---

# M4: Validation

## D-038: M4 delivers the measuring equipment; the measurement needs people (FLAG)
- Bible §36 M4 is "playtest and measure … change design before scaling". Playtesting needs external humans, and this environment has none.
- **Decision:** build everything a playtest needs so that one round produces decision-ready data: local session recording, in-game moment reports, a §44 survey, a report generator with heatmaps, one experiment arm, and a facilitator kit.
- Design changes are **not** made up front: changing things before measuring would defeat the point of M4. M4 closes after at least one human round and the data-driven changes that follow it.

## D-039: Recording is on by default, local only, and disclosed (FLAG: privacy call)
- Sessions go to `user://playtests` on the tester's machine. There is no networking code. The title screen states that recording is on and where the files go; *Settings → Playtest recording* turns it off, which also ends the current session. Files hold no names or accounts.
- **Why on by default:** the build exists to be playtested, and a facilitator forgetting a toggle loses a tester.
- **Needs a human call:** switch the default to off (`Settings.playtest_recording`) for any public or demo build.

## D-040: New top-level `playtest/` folder (FLAG, low risk)
- Bible §31 has no folder for validation tooling that ships inside the game. `PlaytestSession`, `PlaytestConfig`, `PlaytestVariant`, `SurveyQuestion` and `PlaytestAnalyzer` live in `playtest/`, the recorder is `autoload/Playtest.gd`, and the tuning is in `data/playtest/`. The whole folder can be dropped from a release build.

## D-041: How the §44 "most of the following" is scored (FLAG: interpretation)
- Each of the 10 §44 lines has one survey question. A tester passes a line with a 4 or 5 on a 1–5 agree scale, a "yes", or naming any enemy (anything but "none").
- A line is **met** when at least 60% of the testers who answered pass it. The slice **passes** when at least 6 of the 10 lines are met. All three thresholds are data (`PlaytestConfig.pass_ratio`, `criteria_needed`, `SurveyQuestion.pass_at`).
- The survey adds three informational questions (controls, getting lost, favourite activity) that aren't scored.

## D-042: One experiment at a time, applied to a copy
- `PlaytestVariant` overrides data on a duplicate of the movement config, so the shipped preset never changes. Auto mode rotates arms per session, starting from a random per-install offset so each tester's first session doesn't always land on the same arm. Facilitators can pin an arm.
- Only one experiment runs: the slide-jump strength (D-036). With 5–8 testers, each extra arm halves the data per arm. More variants can be added as data once this question is settled.

## D-043: Damage carries its source
- `PlayerCombat.take_damage()` gets a `source` string ("needle/needle_stab", "hazard", "pit", "burnout"), kept as `last_damage_source`. Telemetry reads it on `player_damaged` and `player_died`. No new coupling: combat doesn't know telemetry exists.

