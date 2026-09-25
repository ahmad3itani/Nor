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

---

# M5: World Framework

## D-044: M5 started before the §44 playtest (FLAG: process)
- Bible §44 says not to scale production before external playtesters pass the slice. You asked for M5 while the M4 playtest is still pending.
- **Decision:** build the M5 *framework* (systems) on top of the existing slice, and add only what it needs to be exercised: one NPC (Nix), one quest, set dressing and Scrap stashes. No new rooms or districts. The playtest kit covers the new systems, so one round tests both.

## D-045: The map is data plus the room scenes themselves
- `data/world/world_map.tres` holds one offset per room. Everything drawn comes from the room scenes via `WorldMapIndex`. Tests prove exits and entries meet on the map and rooms don't overlap. Lifts are declared transit links.
- This fits M6 (content pipeline): a new room only needs an offset.

## D-046: Fog of discovery rules
- 64 px cells, revealed within 112 px of Rook. Outlines are known once a room is visited or its district's base map is owned. Geometry and Anchor/gate icons appear only in explored cells. NPC and boss pins appear once the room is visited.
- This follows bible §20: "Nix provides base maps; exploration fills detail."

## D-047: Transit needs Nix's pass and starts at Anchors (FLAG, low)
- Bible §7 says Anchors "later [permit] fast travel", and §13 gives Nix "transit". Transit costs a 60-Scrap pass. It goes from any Anchor menu to any Anchor you've rested at, and arriving counts as resting there (it sets the respawn point).
- **Open question:** free with the first Anchor instead? Also allow travelling from the map?

## D-048: Secret hints show a count per room, never a position
- The Surveyor's lens (Nix, or the Chart Lowlight reward) draws "?n" at the centre of each room that still hides n secrets. Bible §20: "indicate that something remains undiscovered without giving exact coordinates."

## D-049: Economy targets (FLAG: numbers)
- These are tested in `test_economy`:
  - a thorough first run covers 45–85% of all stock (currently 59%);
  - the essentials are affordable early;
  - a full re-clear of respawning enemies pays at most 15% of stock.
- To reach this, walls and secret spots now hold Scrap, instead of prices being cut. See `ECONOMY.md`.
- **M7 audit (D5b), all eleven new rooms merged:** one-time 1,772, sinks 2,230 (Iko +660), coverage 79%, one re-clear 332 against a cap of 334. No trim was needed: the Medical Ruin dormant Needle already drops 0, and the other remedies (First Pursuit's pair-2 Needle, halving the Undercity stashes, the Collector at 60) stay in reserve. **FLAG:** the re-clear is 2 Scrap under its cap, so the next respawning enemy placed on the map fails the rule; the next district needs new sinks before new enemies. Full JSON and the per-district table: `ECONOMY.md`. Core Shards 3 → 5 (max capacity 9) keep capacity at about 43% of the catalog's total Circuit cost (was 41%): budget confirmed, see `CIRCUITS.md`.

## D-050: NPC state = talk counts + conditions; world state = switches
- `talks_<npc>` counts conversations. Dialogue rules accept `Game.check_condition` expressions (`atleast:`, `ability:`, `collected:`, `flag:`, `!`). `WorldStateSwitch` shows set dressing by condition, so the Relay visibly changes with progress (bible §13).
- Relationship values, choices and branching arcs belong to M8 (narrative).

## D-051: The map shares the pad View button with the lab reset (FLAG, low)
- The `map` action is M / pad View. In the labs, View also resets; the map opens only in world rooms, so they never both fire in one place. Keyboard and controller parity holds (`test_input_map`).

## D-052: New folders `world/map/` and `ui/map/` (low risk)
- The bible's §31 layout has no map folder. Map data and logic live in `world/map/` (with the rooms), and drawing lives in `ui/map/`.

---

# M6: Content Pipeline

## D-053: M6 built before the §44 playtest (FLAG: process)
- As with D-044, this is tooling rather than content. The only new content is the Signal Drone, a pipeline test that isn't placed in the slice.

## D-054: Level metrics are recorded, not calculated
- Gap and step sizes come from arcs recorded from the real Player (`TraversalMetrics`). Formulas drift from what feel-tech really produces: apex hang, slide friction, cancel windows.
- A test re-records the arcs and fails when tuning changes, so metrics and templates can't silently go stale.
- Gap widths assume take-off *at* the lip, because players jump a few px early (that's what the route bot found).

## D-055: Templates bake their nodes into scenes
- In the editor, a template writes ordinary nodes into the room. Maps, validators, heatmaps and the game then read plain geometry, and designers can still hand-tweak the result.
- An unbaked template (for example written by a script) builds itself at runtime and is expanded by the tools. Editing a baked template's numbers rebuilds its nodes.

## D-056: The room generator is committed as a dev tool, and the scenes stay authoritative (FLAG, low)
- `tools/roomgen/` (Python 3, standard library only) is in the repo. This adds a **dev-only dependency** (bible §37.9); the game doesn't need Python.
- The `.tscn` files are what ships. `--check` shows which rooms have drifted from their script after editor edits.
- This fixes K-39.

## D-057: Enemies are data brains; bosses may stay bespoke
- Six enemies moved from scripts to `EnemyBrain` data made of shared, stateless modules; per-enemy memory lives in `ModularBehavior`. Parity is proven by the unchanged test suite, and CPU cost is unchanged.
- Warden Krail keeps his script: phases and summons are one-offs, and bosses are few (bible §17).
- New behaviors get new *modules*, never per-enemy scripts.

## D-058: Art swaps in through data; accessibility aids stay
- `SpriteSheetSpec` on `EnemyData.sprite` or the player visual replaces the placeholder drawing. Animations fall back by name, so partial art sets work.
- Telegraph outlines, the "!", health bars, afterimages and the hurt blink keep drawing on top of sprites (Art Bible §6: the aids should stay available).

## D-059: Dev console only in debug and editor builds
- Backquote opens it, keyboard only, like the other debug keys (D-006). `DevActions.available()` is false in release exports, so playtest builds exported as *release* don't expose it.
- **Note for facilitators:** export playtest builds as release.

## D-060: RouteBot holds jump through landing
- It used to release at the apex and lost the apex-hang gravity (about 10 px), which under-measured what a real player does. All routes and the D-036 experiment still pass.


---

# M7: District Production, batch 1 (Undercity + Lowlight complete)

Batch 1 builds bible §36 M7 for Act I: the new 00 Undercity district (the real opening, §42) and the remaining four Lowlight sequences. Ironworks and later districts are batch 2+ and not started. Each entry below says what was planned and, where it differs, what was built ("As built"). The district sheet is `DISTRICTS.md`; the report is `M7_DISTRICT_REPORT.md`.

## D-061: M7 started before the §44 playtest (FLAG: process)
- You asked for M7 ("START M7") while the M4 playtest is still pending. As with D-044 and D-053, it is logged instead of silently ignoring §44.
- The §44 playtest is still the gate for batch 2+. D-068 asks which build it uses.

## D-062: The Undercity is the New Game opening (FLAG)
- New Game starts unarmed in Undercity/Wake. The switch is data: `data/world/onboarding.tres` (`OnboardingConfig`, `enforce = true`, start room Wake, entry `start`, no weapons, `core_hud_hidden` set). `Game.START_ROOM` stays the Relay for tests, fallbacks and the debug Relay start; `TitleMenu` calls `Game.start_campaign()` and `Game.campaign_start_room()/campaign_start_entry()`.
- The Pulse Blade comes from a rack in Medical Ruin (`PulseBladeRack.tscn`, sets `got_pulse_blade`). The Service Pistol is the Collector Drone's reward (`ServicePistolDrop.tscn`). §5's "initial moveset" (the movement verbs) is kept; the weapons move to pickups, per §42.
- This merges the Undercity doc's NewGameProfile with the mechanics doc's OnboardingConfig. `OnboardingConfig.validate()` also rejects an equipped start weapon that is not owned.

## D-063: Pre-Anchor deaths respawn at the last room entry (FLAG, bible §42 vs §23)
- Until an Anchor has been rested at, death and Continue go to the last room entry used (`GameState.last_entry_room` / `last_entry_id`, `Game.respawn_room()`). This applies in every district; the mechanics doc's gentle-rooms-only variant was rejected as unnecessary.
- First Pursuit adds a mid-room checkpoint (D-088).

## D-064: The Collector Drone
- 400 HP, a card deck (Drop Press, Tag Volley, Claw Dive, Hook Sweep), absolute lanes, poise locked while down, ranged poise ×0.3 (`ranged_poise_scale`), telegraphs ×0.85 in phase 2, no summons (`bosses/CollectorDroneBehavior.gd`, `data/enemies/collector_drone.tres`). Subtitle "Civic Recovery Unit C-00". Its own arena, Collector Bay, sits between Broken Lift (Anchor `uc_lift`) and Escape Tunnel.
- Superseded: the Undercity doc's 240 HP hover-72 sketch and its LiftWinch room; the boss doc's Collector Bay → Relay transit; the "Route 00 Manifest" fragment (its "Units collected: 41" contradicted the intake log's 14). The reward is the Service Pistol.
- **As built:** the cruise lane is `arena_x = (84, 428)`, not (76, 428). Collector Bay's vent roof (x 16..64) blocks the 40 px body left of x 84, so dive setups in [76, 84) could never be reached and those cards timed out.
- **As built:** the blade `BossBot` wins in about 26 s, close to the 25 s lower bound. HP is the first tuning knob if playtesters find it short.

## D-065: Radios and terminals are bodiless NPCs
- `NpcProfile.figure = false` plus a `verb` ("Listen", "Read"). The mechanics doc's RadioTerminal class is not built.
- **As built (choices the plan left open):** Orr's radio speaks as "Radio" in the rules that can play before he has named himself and as "Orr" after; the intake terminal speaks as "Terminal" (sea-green; cyan is the radio's alone, so Orr's radio profile uses the Undercity CYAN), the crew note as "Note". The Undercity timeline keys the first NPC on the "Radio" name.

## D-066: Identical lessons share hint ids across districts
- `alley_attack`, `alley_dodge`, `alley_slide`, `alley_gap`, `stack_heal`, `relay_anchor` and `market_shoot` are reused in the Undercity, so a lesson seen once is not repeated in Lowlight.

## D-067: No hazards in the Undercity
- Spikes and pits ignore i-frames (D-020), which contradicts "move through it". The Undercity uses catch wells only.

## D-068: Which build the pending M4 playtest uses (FLAG: needs a human decision)
- New Game now plays 20–37 min of Undercity before the Relay. A debug-only title entry, "Slice (Relay start)", starts the old slice (full kit, Relay) and records its sessions as `new_relay`, which the Undercity timeline excludes.
- **Note:** the entry exists only in debug builds, and D-059 asks for release exports for playtests. To run the old slice on a release export, a human has to choose (for example, an export with `enforce = false`).

## D-069: The Collector eye is an unkillable rail pursuer
- `CeilingTracker` (`world/props/`, data `data/props/collector_eye.tres`) rides the ceiling, uses no attack token, and fires one slow bolt after 1.0 s of lock in its ±32 px cone. It delivers First Pursuit's "keep moving". The mechanics doc's ChaseDirector is not used in the Undercity.
- **As built:** the lock builds only while Rook is nearly still (`still_speed` 20 px/s) and drains at `move_drain` 2 s/s while he moves in the cone; it still resets when he leaves it. With the spec's "reset only on leaving", a Rook centred under a 110 px/s eye needed about 0.8 s to run out of the cone, so the "short stops are free" promise and a fair warning could not both hold. The red fill grows from 0.5 s (not from 0), and LOCK is drawn at 70% alpha so Rook stays visible. Jumping in place still builds the lock; the playtest should say whether the eye still feels threatening.

## D-070: Flow Zones can scale and floor their drain
- `FlowZone.drain_scale` (the largest overlapping scale applies) and `FlowZone.drain_floor` (the highest overlapping floor applies). Only Broken Lift's FZ1 uses them (scale 0.5, floor 1.0), so the Core is "introduced safely" (§42) in every Core mode. See D-085.

## D-071: The Lowlight thesis is "The Grid"
- A `Breaker` (player hits only) drives a latching `PowerShutter` (countdown, 24 px slot, safety sensor), and Warden Krail's arena tests it with the `GridClamp`. The mechanics doc's PowerJunction and `Gate.open_when` are deferred (D-078).
- The clamp is taught in the arena: on arming it shows "Breakers live. Drop the clamp on him." once, no earlier than `ClampTiming.hint_min` (1.0 s). `test_warden_tower_clamp_in_room` drops it on Krail in the real Warden Tower.
- **As built:** a shutter whose panel sits over a floor gap extends down to the real floor, so no gap can let Rook under a closed panel. When both sides of the clamp are blocked, Rook is shoved to the nearer side (`ClampTiming.shove`).

## D-072: Scanner beams respect dodge i-frames (FLAG vs D-020)
- `ScannerBeam` ignores Rook during dodge i-frames and when he moves faster than `blur_speed` (300 px/s) horizontally, so Dash passes. Spikes still ignore i-frames. Scanners are a support hazard only: the Lockdown, the mechanics doc's LaserGrid, SecurityCamera and AlarmSystem are cut or deferred.
- **As built:** measured windows differ slightly from the spec and are what the tests assert: a run-jump clears the LOW bar for take-offs from 87 to 19 px before the beam (spec 80..21), and the FULL static dodge window is 10..38 px (spec 5..33), because i-frames start on the third dodge frame. Calibration beams shove harder (200, -160) so the shove lands about 30 px back.
- **Note:** on old saves walking west (D-075), the Security Station roof costs about 1 pip to the live searchlight, because its breaker is reachable only after passing the light from the east.

## D-073: One chase system, with the Sweeper's rules (FLAG)
- `ChaseDirector` + `Pursuer` + `ChaseCheckpoint`, data in `data/world/chase/rainline.tres`. Catches and pits during a chase are nonlethal (1 pip, clamped to leave 1, after circuit multipliers) and return Rook to the highest checkpoint passed. The chase arms only when Rook enters the start area moving along the path, or spawns inside it; walking in from the far end never arms it. `chase_rainline_done` is set on crossing x 3620 during the chase only.
- The `timing_assist` setting and Assist-scaled pursuer speed are not built (§23 forbids silent changes); see TODO.
- **As built:** `PursuerData.derail_x` (3560 in `rainline.tres`) is where the Sweeper derails at the end of the run, and `runout_speed` (160 px/s) its speed after the end area. Catches count only in CHASE, not during WARN. The warn and repeat hints show once per room load (no persistent flag).

## D-074: Rainline keeps a 112 px slide-jump on the main path (FLAG, K-24/D-036)
- G3 is a slide-jump because a no-pip LowRoad catch sits below it, under the pursuer. The mechanics doc's ≤ 90 px main-path cap is rejected. K-44 tracks the risk.

## D-075: The Smuggler Route is an optional loop (FLAG)
- Reached from the Power Block basement (the bible's 8th sequence played 5th), unbolted from the tunnel side by the den lever (`shortcut_smuggler_route`), with the den Anchor `smuggler_den` in transit (needs Nix's pass; the Anchor has its own pin).
- Old saves with `shortcut_bell_lift` can reach the Power Block basement from the east through Security Station's unflagged left exit. That route is bounded by the unlatched shutters, keeps the Anchor, lever and Smuggler exit reachable, and is tested (`test_power_block_backward_from_security`, `test_security_station_backward`, `test_rainline_old_save_via_bell_lift`).

## D-076: Iko is met in the den, then moves to the Relay (FLAG, §13)
- `NPC.present_when` shows the den Iko until `met_iko`, then the Relay Iko. Orr's post-Krail rule guarantees the meeting. Iko's stock (Bootleg Injector 260, Hot Wire 150, Live Current 120, Slipstream 130; +660 sinks) keeps the economy rules passing. Map pins follow `present_when`.
- **As built:** the Relay Iko stands at x 580 (the plan's fallback): at x 760 her body overlapped Vell's first step. Her `map_label` is "Black Market", so both Iko pins show; blank it if Iko should have no pin.

## D-077: Boss rewards cannot be missed
- `BossArena.reward_position` places the reward; the arena caches the death spot and spawns the reward in `_ready` when the boss is already defeated. Collector Bay drops the pistol at (252, 0); Warden Tower drops the Dash module at (208, 0), fixing its mid-air drop.

## D-078: Mechanics deferred because no batch-1 room uses them
- PowerJunction, LaserGrid, SecurityCamera, AlarmSystem, MovingPlatform, CollapsingPlatform, CoreConduit and a dormant Core, RadioTerminal, the OnboardingValidator, the "Shaft Sentinel" mini-boss and a RouteBot `await` step.
- Kept from the systems doc: the content protocol (`content_errors` / `content_flags` on nodes), `debug_draw`, nonlethal damage, `pit_override`, and fixture generators (`tools/roomgen/fixtures_*.py`).

## D-079: The Collector Drone is the §42 "first mini-boss" (FLAG: please confirm)
- It is scaled as a confidence-building first boss rather than a §17 Major boss. In §44 terms Warden Krail stays the "first boss": the survey's `boss_fair` still names Krail and keeps its criterion, and a separate unscored `collector_fair` question covers the Collector.

## D-080: Map offsets and per-district chart thresholds
- Bell Tower moved (8604, -758) → (15228, -384) and Warden Tower (9308, -1814) → (15932, -1440) to make room for the four new Lowlight rooms. The Undercity sits at negative map x and positive map y.
- `WorldMapData.district_thresholds` + `threshold_for()`; `Game.map_reveal` reads it.
- **As built:** the interim Lowlight value (D0 to D8b) was 0.34 (0.7 × 1465 / 3012 cells, "as hard as before"), not the plan's 0.46, which miscounted the new rooms. The final values are **Undercity 0.40 and Lowlight 0.50**, not the planned 0.5 / 0.55. Measured standable coverage is 0.618 (Undercity) and 0.630 (Lowlight); 0.55 lay above 0.85 × 0.630, and 0.5 left the full Undercity walk (0.44) uncharted. `test_thresholds_match_standable_coverage` keeps each in [0.6, 0.85] × standable.

## D-081: The Core HUD stays hidden until the first Flow Zone
- The code flag `core_hud_hidden` hides the Core bar in campaign runs until the first Flow Zone entry clears it (through `Game.set_flag`, so `flag_changed` fires and the HUD updates). The Core itself stays active; it only drains in Flow. No dormant Core.

## D-082: Core Shards 3 → 5, secrets 10 → 22, fragments 3 → 5 (FLAG: numbers)
- New shards `cs_uc_tunnel_dash` and `cs_smuggler_dash`, so max Circuit capacity is 9. The budget is confirmed in `CIRCUITS.md` (D5b).
- **As built:** secrets are 22, not the plan's 20 (the plan miscounted): 10 before M7, 6 in the Undercity (`uc_shaft_closet`, `mf_undercity_01`, `uc_pursuit_cache`, `uc_tunnel_panel`, `cs_uc_tunnel_dash`, `uc_collector_vent`) and 6 new in Lowlight (`pb_meter_cabinet`, `ss_cell4_bars`, `mf_lowlight_04`, `rc_signal_box`, `sr_den_cache`, `cs_smuggler_dash`). Fragments are exactly 5 (`test_slice_totals_count_content`).
- **As built:** the Smuggler shard is 282 px away and 64 px below its ledge, not 225 px at one height (D-094).

## D-083: Pacing against §42 (FLAG)
- Estimated Relay arrival is 19.5 / 28.25 / 37 min (low / mid / high) against §42's 30–60, and Dash 43 / 59.5 / 76 against about 60–90. Every earlier §42 item is in band at the mid and high ends. At the low end the first NPC (13 min) and the safe Core introduction (14 min) land 1–2 min before the 15–30 band; this is accepted too.
- These are estimates from the room specs, not measurements (K-45). If the playtest's median Relay arrival is under about 25 min, deepen Medical Ruin and First Pursuit first. The table is in `M7_DISTRICT_REPORT.md` §3.

## D-084: World skeleton first
- One D0 change landed stub scenes for all 11 rooms (final bounds, doors, spawns), the world map, the existing-room door plumbing and `test_door_contracts` before any room task, so every room change passed the validator and the full suite. `FlagDeclaration` nodes stood in for cross-room flag producers until their rooms merged; `test_no_stub_declarations_left` now asserts none remain.

## D-085: FlowZone.drain_floor, and Challenge mode in Escape Tunnel (FLAG)
- Broken Lift's FZ1 is floored at 1, so the Core's introduction never burns in any mode (measured: 30 s idle in Challenge ends at 1, no burnout).
- Escape Tunnel's FZ3 has no floor: in Challenge, lingering about 11 s or more burns. That is the mode's contract (K-50).
- **Measured** (`test_fz3_pace`): Normal from 70 reaches 0 at about 20.5 s with the two in-zone kills and no burnout; Assist from 90 keeps about 65; an 8 s Challenge pass from 100 keeps about 56. The Normal margin is nearly zero, so any change to drain, kill rewards or blade `reactor_gain` will fail this test (K-51).

## D-086: Orr's and Mara's Undercity intros key on the Collector
- `orr_intro_undercity` and `mara_intro_undercity` require `collector_drone_defeated`, not `met_orr_radio`, so skipping both optional radios cannot give a campaign player the legacy "first time we meet" lines. Every radio rule stands alone (the post-boss rule also sets `met_orr_radio`). `orr_iko`, `orr_rainline` and `orr_report` require `met_orr`. Legacy saves hear their own radio line.
- The flag-derived quest **The Way Up** (`way_up`, 30 Scrap) starts on any radio call and completes on meeting Orr.

## D-087: No save schema bump for the pre-Anchor respawn keys (FLAG vs CLAUDE.md)
- `last_entry_room` / `last_entry_id` are new optional `GameState` keys. `GameState.from_dict` defaults them to "" like other optional keys, so `SaveManager.CURRENT_SCHEMA_VERSION` stays 3 and there is no migration.
- This contradicts the old `CLAUDE.md` rule ("if you change a save field, bump the version and add a migration"); see D-090. A real pre-M7 v3 save is checked in (`tests/fixtures/save_v3_slice.json`, no `last_entry_*` keys) and `test_onboarding::test_v3_fixture_walks_to_undercity` loads it and walks into the Undercity.

## D-088: EntryCheckpoint, a mid-room respawn point before the first Anchor
- `interactables/EntryCheckpoint.gd` (roomgen `respawn_point()`). First Pursuit places one at x 1800 with spawn `pursuit_mid` at x 1820, so a death in the 4224 px room's section C does not replay the eye section. The Collector eye loads GONE for any spawn past its `lost_x`.

## D-089: The first composition moved to the Maintenance Shaft
- Needle + Scout Drone moved from First Pursuit section C to Maintenance Shaft Floor 2 (`max_attackers` 2), so it lands at about 7–12 min. The dormant Medical Ruin Needle uses `needle_dormant.tres` (drops 0 Scrap). The Service Pistol drop has a 24×150 trigger so the catwalks cannot skip it.

## D-090: New optional save keys don't bump the schema (CLAUDE.md rule amended)
- The rule now reads: bump `CURRENT_SCHEMA_VERSION` and add a migration when a save key changes meaning, is renamed or removed. A new optional key only needs a default in `GameState.from_dict` and a test that an old save loads (the v3 fixture). This records D-087 as a convention, so the next task doesn't "fix" it.

## D-091: Room places the player at its spawn before adding it (engine pitfall)
- `Room.gd` sets `player.position` to the active spawn *before* `add_child`. Otherwise the body enters the physics space at the room origin for one step, and an exit rect containing the origin fires. Collector Bay's west exit (0, -96, 16, 96) did exactly that: both spawns bounced straight to Broken Lift.
- This is shared engine code outside the world-skeleton task's scope; it was the smallest sound fix (the alternative was changing the contracted bounds). Any room whose exit covers (0, 0) now works.

## D-092: Door contracts are a test, and stricter than planned
- `tests/unit/test_door_contracts.gd` holds one table for every M7 door (exit rect, target room/entry, own entry position and facing, `requires_flag`). It asserts `requires_flag` exactly, empty included, so main-path doors stay unflagged; it also asserts room bounds, default spawns and the non-door spawns (Wake `start`, Relay `start`) and forbids undeclared exits in the listed rooms. The side of an exit is judged by its centre against the bounds centre (Collector Bay's west exit sits at x 0).
- **Correction to the plan:** the Apartment Stack hatch targets `SmugglerRoute/from_stack`, as the contract table says. The plan's D2a/D7b text ("from_smuggler") was wrong; `from_smuggler` is the Stack's own entry for the reverse direction.

## D-093: Air swings hang only when they connect (FLAG: combat feel)
- Found while closing the Flooded Alley Dash gate. Every air swing used to set the fall speed (three hangs per airtime), and a light pressed on the jump frame kept the grounded swing's 0.5 gravity scale (a 56 → 87 px "super jump"). Chained air lights, with or without an air dodge, outreached a dash-jump, so no gap could separate them from Dash.
- Now an air swing takes its hang and gravity scale only on a hit (`AttackData.air_velocity_on_hit`); a whiff falls like a jump. The katar dive keeps its start-of-swing plunge. `test_combat::test_air_hang_only_on_hit` covers the rule. This changes how air combat feels everywhere; the playtest should check that juggling still feels good.

## D-094: Dash gates drop 64 px, and every air-dodge frame is swept
- A gap at one height cannot separate a dash-jump (~242 px flat) from a dodge-jump plus a late air dodge (~229 px, more with coyote take-offs). Gates now put the target below the take-off:
  - **Smuggler Route:** shrine at x 740..778, y -176, 64 px below a one-way DashLedge (1060..1104 at -240), across 282 px. The floodgate moved 48 px west (692..740), the top step became `oneway(1064, -192, 40)`, and the Flow zone now spans x 300..692. A take-off at the very end of the coyote window plus a perfect air dodge can still land, so its marker says "Too wide to jump (mostly)".
  - **Flooded Alley** (`cs_alley_dash`): a one-way take-off at -144 (x 100..160) and a DashShelf at x 450..506, y -80, 290 px away, shard at 468. A dash-jump reaches it from take-offs at x 154–174.
  - **Escape Tunnel** (`cs_uc_tunnel_dash`): unchanged, a 230 px gap at x 1830 whose sweep covers delays 0..27 from the step edges only. It probably leaks the same way (K-48).
- Both sweeps try every air-dodge frame the cooldown allows and count any landing on the target as a leak. The alley sweep takes off at the lip and 8, 16 and 20 px past it; the Smuggler sweep takes off at the lip and 8 px past it (16–20 px is the admitted residue, K-48).

## D-095: Breakers are placed out of every grounded swing's reach
- `Breaker.content_errors` measures the union of the light chain, heavy and launcher of every melee weapon in the catalog, with each lunge integrated under ground friction (the blade heavy reaches 38 + ~11 + 6 px), and widens the one-way band by that reach. The Warden Tower breakers moved beside the clamp column (x 120..172 and 244..296) because a grounded light from the arena one-ways tripped them.
- `test_warden_tower_clamp_in_room` swings every grounded attack with both melee weapons from each one-way's nearest end.

## D-096: HintTrigger.skip_when
- A hint can be silenced by a `Game.check_condition` expression (reported to the validator through `content_flags`). The Apartment Stack's "Bolted from the other side." hint skips once `shortcut_smuggler_route` is set, because the `from_smuggler` spawn sits inside its box.

## D-097: Enemy data variants for placement problems
- `needle_dormant.tres` (drops 0, Medical Ruin practice target) and `needle_ledge.tres` (aggro range 160 instead of 200, Broken Lift FZ1). At 200 the ledge Needle woke while Rook walked the shaft floor 194 px below, tracked him to the ledge lip and lunged off it, which broke the "Needle in Flow" lesson. Any Needle placed on a ledge above a walkway may do the same.

## D-098: Room layouts that differ from the plan
Each was found by a route test and changed as little as possible:
- **Wake:** the sill is a solid 60×8 block at (540, -100), not a one-way, so a tap from below can't grab its Scrap; it is reached from the side with a held jump (tested both ways). The grate and eye decor sit at y -244 and -250.
- **Broken Lift:** the car roof moved from x 250..330 to 224..304 (Scrap at 264): walking off the climb only carries Rook about 30 px sideways.
- **Rainline Chase:** a one-way coupler step at (2920, -48) east of Car C (its 96 px face made the line one-way westbound), a back wall `BoxBack` on the signal box (Car C's roof otherwise reached the stash around the breakable front), and the Sweeper wreck decor moved into the canal (3540, 196).
- **Power Block:** the top steps of shafts B and D sit 32 px under the floor lip, so a player dropping down zigzags west first (traversable, tested; playtesters may bump their heads).
- **Collector Bay:** the plan's catwalk RouteBot targets (190, 330) landed in the gaps; the tests use 210 and 360. The geometry is unchanged.
- **Decor origins are bottom-centre.** The plan placed several props by their top (Security Station's Monitor Wall at y -300, First Pursuit's hatch housing, Broken Lift's cables, Power Block's B3 cable), which would have drawn them inside ceilings or floors; they were moved to fit. Decor banners carry no text, so "PULSE EXTRACTION" and "CIVIC RECOVERY → BELL TOWER LIFT" exist only as generator comments (K-53).

## D-099: PowerShutter pass margins read the open clock
- `shutter_passed` reports `open - t_open` while the panel is still up, so a low pass under a closing shutter reads as a small margin. Power Block's intended S4b low line reaches the slot about 3.37 s after its breaker and reports about 0.23 s, although its real margin against the slot (open + drop + slot - t_open) is about 1.08 s. The route test asserts the ≥ 0.5 s margin for S1–S4a and a low pass for S4b. The playtest report will list S4b as a close call (K-52).

## D-100: Boss exits open on the reward, not the win (audit fix)
- `BossArena` sets `<boss>_defeated` at the kill but spawns the reward `death_time + 0.2` s later (1.8 s for the Collector, 1.6 s for Krail). Both way-out doors keyed on the defeat flag, so a Rook standing by the east door when the boss died could leave before the reward existed: Escape Tunnel (the pistol lesson) without the Service Pistol, the Relay (whose end card names the Dash) without Dash. Standing east of the drop, he could also leave without passing it.
- Now Collector Bay's east exit and `ExitGate` key on `got_service_pistol`, and Warden Tower's on `unlocked_dash` (door contracts updated). `BossArena` lists `ExitGate` in `gate_paths`, so a re-armed fight (`quick_boss_restart` with the reward owned) seals it too. When a fight ends, `_set_gates(false)` skips a Gate whose own `open_flag` is not set yet. The reward scene's pickup flag is reported through `BossArena.content_flags()` (and `AbilityPickup.content_flags()`), so the flag lint sees who produces it.
- Tests: `test_collector_bay_exit_waits_for_pistol` and `test_warden_tower_exit_waits_for_dash` kill the boss with Rook at the door and hold right for 2.5 s. `test_quick_boss_restart_rearms_krail` checks the re-sealed gate.

## D-101: The Undercity's §41 combine beat comes after its boss (FLAG vs §41)
- §41: "introduce a mechanic safely, reinforce it, combine it, then test it in the boss." In the Undercity as built, the eye is introduced in First Pursuit and the Core in Broken Lift FZ1. The Collector Drone's Drop Press tests only the eye half of "Keep moving"; Collector Bay has no Flow Zone. The Core is reinforced and combined with the new pistol and in-zone enemies in Escape Tunnel's FZ3, which plays after the boss as the district's epilogue. The Core is first tested under pressure in Lowlight.
- Kept as built: a tutorial district, the §42 "first mini-boss" scale (D-079), and a new-mechanic room right before the first boss would break "one concept at a time" (§23). The alternative is a Core-feeding element in the Collector fight plus a combine beat before the bay. `DISTRICTS.md`'s §41 row and the M7 report's acceptance line now describe the real order. **Please confirm or overrule.**

## D-102: The Undercity has no loop or shortcut (FLAG vs §14/§21)
- The Undercity is a strict line (Wake → … → Escape Tunnel → Relay), one door forward and one back per room. §21 asks every district for alternate routes and §14 for loops and shortcuts. This is deliberate for the onboarding district: it is revisited through `uc_lift` transit and the Relay balcony door, and its revisit content (the Dash shard `cs_uc_tunnel_dash`) sits on that line. **Please confirm**, or add a small loop (e.g. an Escape Tunnel → Broken Lift return).

## D-103: HUD hints queue; one lesson line at a time (audit fix)
- `CombatHud` used to overwrite its single hint slot, so a hint fired right after another was never read: Security Station's "these are on calibration" line (the spawn sat inside its box, the low-beam box started 0.2 s of running later) and the Maintenance Shaft's dodge line (replaced by the air-attack line about 1 s later).
- A hint now waits until the current one has been up `HINT_MIN_SECONDS` (2.0 s) or has ended. At most 2 wait, newest kept, and duplicates are not queued (`test_hud_hints_queue_with_a_minimum_hold`). The rooms are fixed too: Security Station folds the calibration note into the first beam's hint (`ss_low`, "Scanners on calibration: harmless. Low beam: jump it"; `ss_calib` is gone). The Maintenance Shaft's `uc_air` box moved from x 180..240 to 300..360, under the Scout, past where its first bolt is dodged.

## D-104: A broken tube is its own NeonSign state (audit fix)
- The secret cue `neon(..., SEA, 1, True)` differed from the ambient tubes only by its stroke count, and seven ambient tubes (Medical Ruin, First Pursuit, Broken Lift) used exactly the cue's signature. `NeonSign.broken` now draws the tube askew, half lit, with a stutter of three quick dropouts every 1.5 s (steady but still askew and half lit under flash reduction). `RoomGen.neon(..., broken=True)` sets it. Only the four secret cues use it: the Maintenance Shaft closet, the First Pursuit cache roof, the Escape Tunnel panel, and a new cue inside the Collector Bay vent alcove. The ambient tubes use the 3-stroke form.
- Sodium is kept to the route: the pump wheel (Maintenance Shaft) and the tram (Escape Tunnel) now use a steel accent.
- The Collector Bay vent lip had run over `ArenaGateLeft` and the vestibule, so Rook could drop out of a sealed fight. The alcove floor over x 16..56 is now solid (`VentFloor`), and only the lip in front of the panel (x 56..72) drops through, into the arena.

