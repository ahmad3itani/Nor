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


## D-105: M8 batch = narrative systems + Act I integration; endings framework unreachable until Act V (FLAG)
- Acts II-V do not exist, so M8 builds the sequence, memory, arc, world-state and ending systems fully and integrates them into Act I. Endings: complete framework + four placeholder sequences + credits, reachable only via the dev Ending theatre/tests; real conditions are data gated by future flags.
- FLAG (process; redline/CLAUDE.md: 'Do not start M7 batch 2 (Ironworks) or any later district or milestone unless the user asks — bible §44 says not to scale content before the slice passes.'; bible §44: 'Do not scale production unless external playtesters independently report most of the following:'): M8, like M5-M7, starts before the §44 human playtest because the user asked ('START M8').

## D-106: One sequence system; memory vignettes share its skip, subtitle and mode plumbing
- Scripted scenes are SequenceData step lists run by the Cinematics autoload; a skip (and INSTANT) runs every remaining finish() so no effect is lost; an abort (room left, Save & Quit, test teardown) runs no finish(), sets no flag and only restores, so the scene replays (amends A1 §1.1/§2.2). Memory vignettes are a separate content type (tableau + beats + pan/detail) because they are player-paced and interactive, but they use the same CinematicMode, SkipGate, SubtitleStyle and cinematic_skip action.
- As built (T03): a skip records `step_index` as the step the skip landed on. Non-blocking steps are `finish()`ed at the end only when their `run()` did not complete, and `SeqMark` is idempotent per play. A non-locking play ignores `hold_for_input`'s tap wait. The skip prompt and the title card follow the Subtitle size setting.
- As built (T03): an abort reverts actor position and modulate changes (`SequencePlayer.note_abort_restore`), so `SeqActorFlash`/`SeqActorMove` stay usable in non-locking repeat intros. Any other world state a step's `run()` leaves (an NPC mid-move, a pose) stays partial after an abort; acceptable because aborts happen only on a room leave, Save & Quit or test teardown, and the scene replays (K-M8-24).
- Audit repair (M8): `act1_close` sets `act1_complete` under its fade, three steps before its end, so an abort in that window used to keep the flag (and the arc stages its listeners enter, e.g. Orr's `on_air`) while the close and card replayed. `SliceEndTrigger` now snapshots the flags when the close starts and puts them back on an abort, so "an abort sets no flag" holds for it (`test_quit_late_in_close_reverts_flags`). A trigger that finds another play running, or is refused, retries (every `trigger_retry_seconds`; `SliceEndTrigger` once that play ends with Rook still inside) instead of waiting for Rook to leave and re-enter. While a locking scene holds Rook, direct damage (pits, chase catches, spikes, burnout) is ignored like hits, and the pause menu hides Map (the `MenuHost.can_open` rule).

## D-107: Headless runs resolve sequences and memories instantly; boss intros keep the M7 timer under INSTANT
- CinematicMode INSTANT is the headless default (override --cinematics=), which keeps every route/boss test unchanged; AUTO drives sequence tests and the story tour.
- As built (T07): the INSTANT boss-intro path sets `ctx.camera = null`, so the restore contract never snaps the camera and every M7 frame (e.g. `s_boss_fight`) stays byte-identical. `CaptureTour` forces INSTANT for every tour but `story` and writes its settings to `user://capture_tour_settings.cfg`, so a developer's `settings.cfg` never leaks into captures.

## D-108: Skip is always a hold and a tap only advances; repeat boss intros never take control (FLAG)
- SkipGate (T01): a tap (< 0.25 s, fired on release) completes/advances text and memory beats; a skip is a hold of cinematic_skip (first view 0.8 s, repeat view 0.4 s), or two taps under the 'Skip scenes: Press twice' setting, or PauseMenu 'Skip scene'; 0.25 s grace; presses begun before the gate saw them (entry mash, Resume, a menu key) are ignored. Boss intros lock and play in full on the first attempt only; retries play title/roar/shake as a non-locking overlay and the boss acts after the legacy retry_intro_time 0.6 s. FLAG vs §17 'skippable repeated intros': repeat boss intros are not skipped, because they never take control (§17 'fast restart'); other repeat views (journal and dev replays) need a 0.4 s hold instead of one press, because a tap advances text.
- As built (T01): under 'Press twice' a skip window opens only after a tap (a press that included an advance action); a tap of `cinematic_skip` alone neither advances nor arms. The 'again to skip' prompt shows only while a window is pending; hold mode shows its prompt from frame 0 on repeat views. `notify_unpaused()` blocks any press still down until it is released.
- As built (T07): repeat boss intros never lock (`repeat_locks_input = false`) and release the boss after the legacy 0.6 s. First views: `ll_krail_intro` 12.575 s, `uc_collector_intro` within its 10 s budget.
- Audit repair (M8): these times, the 0.35 s letterbox, the 0.5 first-view early-advance share, the 70 cps typing rate, the line auto-time formula, the DialogueBox choice arm (0.4 s) and the trigger retry (0.5 s) are data in `data/cinematics/cinematic_config.tres` (`CinematicConfig`, read through `CinematicMode.config()`), like `MemoryConfig` on the memory side (§37.3). Values unchanged.

## D-109: Act I sequences never move Rook; new M8 text never names Rook (FLAG)
- R1 is validator-enforced (RouteBot safety). FLAG (existing canon inconsistency, for a human): orr.tres dialogue `orr_report` 'And Rook - don't go up that tower tired.' vs mf_lowlight_04 'This one came in without a name' and mystery 5 ('another name'). M8 avoids the name; decide who names him in Act I. The only Act I choice is also worded around the missing name ('I can tell Lowlight it was you', orr_idle_named 'your description'); whoever decides Rook's name also decides whether Orr's on-air line should use it (flags unchanged either way). Also for the same human decision: (a) Krail ('Fourteen. You were meant to come up in a crate.') and the Wake PA ('Fourteen of fourteen processed') use a ward designation as a de-facto name; (b) pronouns conflict: bible §1 'implanted in their chest' vs data mf_undercity_01 'Then leave it in him' (spoken verbatim in its vignette), while A3 avoids pronouns. Whoever decides Rook's name (mystery 5 'another name') decides these too. The knowledge lint (T10) warns on 'Rook' in Act I text, so that orr_report line stays a visible warning until then. The §44 survey also uses the name: data/playtest/playtest_config.tres question curious_world 'I'm curious about Veyra and Rook.' (criterion 'curious about Veyra/Rook'); since M8 text never names him, a playtester may meet the name first in the survey. Decide it with the rest.
- As built: M8 memory text avoids the name; `mf_undercity_01`'s 'Then leave it in him' is spoken verbatim in its vignette (the pronoun question above). `test_content_validator.gd:test_knowledge_lint_warns` pins exactly one shipped knowledge warning (orr.tres 'Rook'); update it when this is decided.

## D-110: Subtitle size/background/speaker labels, subtitle speed, skip mode and 'memories at Anchors' land in M8; text auto-advance stays M9 (FLAG)
- FLAG vs Settings.gd header 'Full accessibility menu arrives with M9' and bible §36 'M9 — Endgame / Steam / Accessibility: ... settings': six rows move forward, on a 'Subtitles & scenes…' sub-page. From §24: 'subtitle size/background/speaker labels', 'cinematic skip' and 'hold/toggle options' (Skip scenes: Hold / Press twice). Not literally in §24: subtitle speed (sequence lines run on a clock; §24 'accessibility settings never shame the player') and memories at Anchors (D-112). Text auto-advance is cut from M8 (M9 TODO). Defaults render exactly as M7.
- As built (T01): the six rows sit on a 'Subtitles & scenes…' sub-page; the main Settings page measures 259 of 270 px, so a future main-page row needs another sub-page or a scroll. `--subtitle-size=N` overrides the size for one session without saving (captures). `SubtitleStyle.line_spacing()` uses the font's real row height (11/13/16 px at sizes 7/9/11), so size-2 text never spills out of its box; the default 62 px box is unchanged. With background 'Outline' the DialogueBox draws no box and no red accent line; text and speaker label get a 1 px dark outline. The italic narration face is a `FontVariation` slant on the fallback font (placeholder, D-026).
- As built (M9, T03/T09/T11): text auto-advance ships as the Subtitles setting `text_auto_advance` (default Off, R03.12) with consumers in DialogueBox (T11 R11.9) and SequencePlayer/memory beats (T09 R09.9); default-off timing is byte-identical (D-157).

## D-111: New autoload Cinematics and input action cinematic_skip (physical Space/Enter/K/Z + pad A: every jump key plus Enter)
- Contexts are exclusive (input locked); §37.9 dependency note in CLAUDE.md; rebinding stays M9. The overlap with jump/ui_accept is resolved by the tap/hold split (D-108), not by context alone. Also overrides the built-in ui_accept (Enter/KP Enter/Space + pad A) and ui_cancel (Escape + pad B): the 4.3 defaults have no joypad event, so no menu was usable from a controller before M8 (pre-existing gap, fixed because every M8 menu flow needs it).
- Behaviour change for controller players (T01): `MenuScreen` buttons now press on pad A and menus close on pad B everywhere.

## D-112: Memories surface at Anchors, never on pickup
- Pickup stays instant (no input lock during danger, route safety); the HUD card becomes title + 'Rest at an Anchor to remember.'; the journal's 'Remember now' is the fallback; setting to disable Anchor playback. At most one vignette per rest (MemoryConfig.max_per_rest 1), so the first rest before the Collector stays short; the card and hint texts live in MemoryConfig.
- As built (T04): Anchor `max_per_rest` 1; `MemoryScenePlayer.play()` during a playback queues instead of refusing, and an empty or unknown id still emits `memory_playback_finished`, so an Anchor always gets its loadout. Beat text types at `MemoryConfig.chars_per_second` 70 (the DialogueBox rate); a tap completes the line, then advances once `min_seconds` has passed. Every player-facing vignette string and timing lives in `MemoryConfig`.
- Audit repair (M8): the Anchor saves again when its rest memories finish (`rest_at_anchor` saved before they ran), so `mem_seen_*`, details and the arc stages they unlock survive a quit. An aborted playback emits `memory_playback_aborted` (not `_finished`): MusicDirector leaves MEMORY and the Anchor drops its one-shot loadout follow-up.

## D-113: One surfaced memory 'Count the Last One' on the first Anchor rest (FLAG)
- FLAG (content/canon): invents a companion and a bridge; not a collectible so the fragment count stays 5 (D-082). Guarantees a first-time §44 player sees the system once. FLAG vs §18 'Rook's memories were fragmented and distributed through the city' and §43 'survival resource tied to stolen memory': this memory surfaces on the first rest without being recovered from the city. Alternative for the human: gate it on an existing main-path Act I source (e.g. unlock_condition flag:read_uc_intake_log, the Undercity intake terminal) so the city still triggers it; the cost is that a player who skips the terminal sees no vignette before the Relay.
- As built: `mem_first_rest` 'Count the Last One' is SURFACED at timeline slot 100 (undated bridge).

## D-114: Act I memory timeline order (FLAG)
- FLAG (canon): Clinic -> Cell Four -> Ledger -> Execution -> Extraction, bridge memory undated at slot 100; slots spaced by 100; the gallery never shows a total. Consequence to confirm: with Rain Clinic dated before Cell Four and the Execution, the gallery implies Rook carried the Core (and was operated on) before the arrest, which touches mysteries 2 and 6 and Project REDLINE (Act II/IV). Mara's seen_one line no longer adds 'not Civic work' to that; if the order is not canon, leave Rain Clinic undated (slot 0) in the strip.
- As built: slots Rain Clinic 200, Cell Four 300, The Warden's Ledger 400, Execution Order 7-R 500, It Won't Come Out 600. `detail_from_beat` is stored 0-based (A2 counts beats from 1).

## D-115: Vignettes use memory blue full-screen; red only on redacted shapes (FLAG)
- FLAG vs ART_BIBLE §3 reserved gameplay colours: used on purpose inside paused vignettes only, never as a telegraph. One standard for HUD, art and dialogue: nothing in Act I ties memories to the Core (§18's hidden truth is only seeded by mf_lowlight_02's 'whatever it's eating'). So the HUD Core bar never pulses on a memory, the vignette's edge burn is neutral static (not Core red), Core red appears only on `redacted` shapes, and Mara's line is 'If you start seeing things, tell me.' (not 'If the Core starts showing you things').
- As built (T04): vignette tones #2a4050 / #5f93b3 / #9fd8ff, neutral edge burn #c8ccd8, #e8283c only on `redacted` shapes (the companion's face shows from beat index 3, when the text says 'only static'). Shape layouts are placeholder compositions of A2's shape lists (D-026).

## D-116: All M8 state is flags (bool/int); no GameState key, no schema bump; act1_complete derived on load
- D-087/D-090. GameState key set pinned by test. A pre-M8 save with slice_end_seen gains act1_complete on load (the only derivation). A skipped memory counts as remembered.
- As built (T02): `Game.set_flag` is a no-op when the new value is numerically equal to the stored one (a JSON round trip turns ints into floats), and flag values are type-checked (bool/int only). The act1_complete derivation needs no schema bump (D-087/D-090). A skipped memory counts as remembered.

## D-117: NPC arc = spine + reactions, sticky, derived from flags; pick order story > beat > idle > fallback
- Always-true repeating rules move to stage idles; ArcTracker is a QuestTracker sibling.
- As built (T05): `NpcArc.validate()` holds the structural rules (ids, `min_stage`, reactions without idles or notes, an unconditional last beat, a heard flag per beat, idles set nothing, no give_*, note length, threads produced); `content_check()` holds the cross-file ones (exactly one owning profile, speakers, the shop rule, `validate()` on every embedded dialogue, `open_menu` ids), so each bad case errors exactly once. Automation (RouteBot, CaptureTour) always picks choice 0, so bots set `orr_air_named` (K-M8-9).

## D-118: Rook's first words are dialogue choice labels (FLAG)
- FLAG: the bible never says Rook is silent but no line voices him. Labels stay terse; if a silent Rook is wanted, swap labels for action verbs, flags unchanged. Also FLAG: the choice (orr_on_air, the only Act I 'meaningful choice' of §19) enters on act1_complete, i.e. after the 'ACT I COMPLETE — RUN' card, so §44 players who stop at the card never see it and the card's standing lines cannot reflect it; in practice it is an Act II threshold beat. Alternative for the human: gate it on warden_krail_defeated + met_orr before the close and add a standing line for orr_air_named/ghost.
- As built (T05): `thread_orr_air` is on `orr_on_air`'s own `set_flags`, not on each choice (choice flags must be disjoint); each choice sets only `orr_air_named` or `orr_air_ghost`.

## D-119: count:<metric>:<n> condition kind; no AND/OR in the grammar
- Metrics fragments/shards/circuits/secrets. AND stays structural (lists, nested switches); OR stays per-caller.
- As built (T02): `ContentValidator.COUNT_METRICS` lists the metrics; an unknown `count:` metric is reported through `_consume_condition`.

## D-120: Pending-beat tick over NPCs (FLAG)
- FLAG (low) vs §19 'no giant objective markers': 2x5 px, room-local, never on the map. Colour UiTheme.TEXT with a 1 px dark outline (not amber, which ART_BIBLE §3 reserves for the elite outline and the Relay's M8 lights would swallow; defined once for a colourblind swap). Also shown over the bodiless radio board for unheard chatter. Playtest question.
- As built: `NPC.PENDING_TICK_COLOR := UiTheme.TEXT` with a `UiTheme.PANEL` outline, defined once. Bodiless NPCs opt in with `NpcProfile.cue_new_lines` (a `heard_<dialogue_id>` code flag); `relay_board.tres` sets it.

## D-121: mara_after_boss becomes one-shot and plays after her intro; Iko gets a Relay intro for Orr-path players
- Legacy-save behaviour change; no test pinned the old starvation.
- As built (T05, A3 D-A5): a legacy save that reached Krail with Mara unmet now hears `mara_intro` (with the Scattergun) first. Iko gets `iko_relay_word` on the Orr path.

## D-122: Arc dialogues are economy-neutral
- No give_* in arc data (validator); K-49 headroom untouched.

## D-123: World state is visual-only switches + NPC posts + text
- Linted: no collision, rewards, enemies or interactables under a switch. Posts are NPC_<id>_<post> nodes with exclusive present_when; Mara moves only after act1_complete (outside the §44 path); sequences may target only primary NPC_<id> nodes.
- As built (T02/T08): `ContentValidator` lints a `WorldStateSwitch` subtree (solid blocks, enemies, pickups, interactables are errors, e.g. 'SolidCrate under a WorldStateSwitch (visual only)'); `roomgen` gained `switch(parent=)`, `npc(name=)` and `mapmarker(shown_when=)`. Arc props key on `arc_<npc>_<stage>` and `orr_air_*`; arcs set no world flags. Audit repair (M8): an arc stage needs its met beat first, so an arc prop shows what Rook has *heard* from that person (Mara's bench lamp, Nix's tower sheet, Iko's Spire crates), and appears the first time he talks to her after the event. World facts do not wait for a conversation: Vell's sign (`VellSignLive` / `VellSignDry`) now keys on `warden_krail_defeated`, since the cut supply line is a fact. Mara's bench lamp stays lit after she moves to the door post (her work is left running; K-M8-38). `orr_radio.tres` rule 0 needs `act1_complete` **and** `met_orr_radio`, so a legacy (v3) save that gets `act1_complete` from `slice_end_seen` still hears the legacy call first. Iko's stall awning is 20 px wide (570..590) to clear the pillar and Mara's bench; `MaraBench` (Mara's lamp on her own bench at 628) is exempt from the workbench-overlap test by design.

## D-124: One map-note mechanism: MapMarker.NOTE with shown_when
- Rumours and arc notes are NOTE markers in rooms (known rooms only, never within 96 px of a secret, §20); arcs carry no map fields.
- As built (T02): a NOTE marker may never sit within 96 px of a secret (validator); `MapMarker.content_flags()` reports `shown_when` as a condition.

## D-125: Hub music layers are data
- data/audio/hub_music.tres; act1_complete adds lead 0.2.
- As built (T02): `HubMusicLayer`/`HubMusicLayers` with `active_mix()` and `content_check()` (invalid conditions, unknown stems). `MusicDirector` enters MEMORY on `memory_scene_started` and leaves it on `memory_playback_finished`.

## D-126: Endings are data; EndingResolver is pure; priority redline > release > sever = crown; no finale trigger in M8
- choice_condition + requires / requires_memories / requires_arcs (§37.2: the finale is future work).
- As built (T06): `SeqCredits` has optional `mark` / `mark_after_seconds` (default 5), so `ending_<id>_credits` fires 5 s into the roll (and once from `finish()` on a skip); `ending_<id>_title` is a plain `SeqMark` before the title card. A5's trailing fade after the credits was dropped: `SeqCredits` stays the last blocking step and the restore contract clears the fade. `CreditsSection.HEADING_MAX` is 40 (A5's longest heading is 37 chars); the credits column is 300 px so it fits at the largest subtitle size.

## D-127: Endings unreachable by construction through FutureFlagSet
- Future flags count as produced, Act I content may not read them, real producers are errors until the entry is removed; the 'needs a future flag' rule is removed when Act V lands.

## D-128: Ending theatre runs in a flag sandbox
- Theatre plays never mark the profile or telemetry; real play marks ending_seen_<id> on finish or skip.
- As built: `EndingDirector` restores `CinematicMode.theatre` to its prior value instead of forcing it off. The dev sequence preview (T09) also runs inside a `FlagSandbox`, so previewing `act1_close` never leaves `act1_complete` in the profile; the view is forced only through `SequenceContext.first_view`. `replay_act1_close` sets `warden_krail_defeated` and `slice_end_seen` inside its sandbox so the Relay's `SliceEndTrigger` (no theatre guard) cannot start a second close. DevConsole `PAGE_ROWS` is 11 (measured: 12 rows + Back + Close = 276 px > 270), so the sequence theatre paginates.

## D-129: Release threshold memories_remembered >= 24, planned_memories 24 and planned arc stages are provisional (FLAG)
- FLAG (numbers): bounds, not tuning; the Act II-V content plan must confirm them. Also FLAG (Act V design, §37.2): the ending data ties Act V outcomes to specific, missable Act I content: redline requires flag:read_uc_intake_log (the Undercity intake terminal) and requires_memories flag:mem_seen_mf_lowlight_03 (the Ledger memory); release reads Act I arc stages. These links are placeholders for the Act V pass and need human confirmation; they can be replaced by future flags without code changes.
- As built (T06): `FlagSandbox.apply_act1_max_state` normalises every shop upgrade counter to an int ≥ 1, because `chart_lowlight`'s reward flag `map_lens` is also Nix's shop counter (K-M8-27).

## D-130: Redline requires The Null, which the bible schedules for M9 postgame (FLAG)
- FLAG vs §18/§30/§36: the hidden ending cannot be reached before M9 even once Act V exists; changing that would change §18.
- M9 (D-154): satisfied as data. `null_depth_reached` is produced (The Floor and the descent); the ending stays unreachable through its other future flags.

## D-131: Act I card 'ACT I COMPLETE — RUN' with 'where things stand' lines (FLAG)
- People and places, never a score (§18 no morality meter). SliceEndMenu stays the card so the §44 kit flow is unchanged; observers must know the header changed. act1_close has no title card, so the menu header is the only 'ACT I COMPLETE — RUN'; at most 3 standing lines so the card fits 270 px. FLAG vs §18 'Act I — Run: survive, reach Relay, assume the city authority is the enemy': M8 defines Act I as Undercity + Lowlight ending at Krail (the Relay is reached mid-act), and the header, act1_complete and the standing lines make that boundary canon (M7's card said only 'ACT I — LOWLIGHT CLEARED'). Needs human confirmation. The Act I choice (Orr on air, D-118) happens after this card, so the card never reflects it.
- As built (T06): `ActLibrary.standing_lines` always shows the fallback line and fills the other `max_standing - 1` slots with the first passing conditional lines, so on a completed Act I the Orr and Nix lines usually take both slots and the ledger, Iko and memories lines show only when fewer earlier lines pass.

## D-132: Act I knowledge lint
- Warns when Act I-visible text uses Act II+ terms (Project REDLINE, Architect, The Null, neural, harvest, Redline disaster); endings and theatre sequences exempt.
- As built (T10): 12 terms (`data/story/knowledge_lint.tres`): Project REDLINE, Architect, The Null, neural, harvest, Redline disaster, conscious, 'Pulse is', 'stores memor', 'made of memor', research, Rook. It scans dialogue lines, choice labels and replies, fragment titles and bodies, memory beats and SURFACED titles, sequence lines outside theatre-only sequences, standing lines, map notes and the `MemoryConfig` gallery strings; `data/endings` is exempt. The one shipped warning is orr.tres 'Rook' (D-109).
- Audit repair (M8): the first build did not read map-marker labels or arc journal notes although this entry said it did. The lint now also scans every `MapMarker` label (notes, landmarks, gates), each spine stage's `journal_note` (the journal People page), NPC display names and speaker labels (`DialogueLine.speaker`, memory beat speakers, `speakers.tres`). `test_knowledge_lint_reads_notes_journal_and_speakers` plants a term in each.

## D-133: New script folders cinematics/ and story/ in ContentValidator.SCAN_DIRS; resource content protocol
- Resources lint themselves via content_flags()/content_check(), mirroring the node protocol.
- As built: the SCAN_DIRS additions (`res://cinematics`, `res://story`) landed in T10. Every M8 runtime directory scan goes through `DataDir.list` / `DataDir.list_scenes`, which read `.tres.remap` / `.tscn.remap` in exported builds (K-M8-22). The validator keeps producer/consumer multimaps, and `check_resource()` is the test API for in-memory resources. `validate_story()` runs the cross-area rules (future flags produced or read outside `data/endings` are errors; a sequence nothing plays is a warning; `@boss`/`@arena` actors, the ending id set, the credits ENGINE line).

## D-134: Arc canon commitments (FLAG)
- FLAG for a human: Mara has seen a Redline Core before ('It wasn't in a person then'); Orr's crew call sign (three short, three long) means 'still here', the Cell Four tapper used it (so a crew member was in the next cell), and Orr's board picks it up again after Rook remembers Cell Four (someone still uses it); Rook is not said to know the code (A3's 'Nobody outside the crew should know it' was cut because it implied Rook's crew past, Act IV / mysteries 5-6); Wardens asked Vell about uncapped Cores; Iko: 'the Spire always comes to collect'; relay board 'someone is counting'. None answers a §18 mystery; each constrains later acts. The act1_close band line shares no sentence with Execution Order 7-R (now '...all Recovery units. Priority unchanged. Signature still active.'; test-enforced) so the order's author stays open (mystery 1). SecurityStation's CellFourKnock chalk marks are old marks left by the tapper that Rook only notices after remembering, never his own hand (A4 §3.1's intent cut for the same reason as the tap-code line). A3's 'Later act' continuations (e.g. Circuits refined from Pulse research stock, Warden bounty patrols, Iko's Ironworks crate) are non-binding notes for later acts, not canon, and pre-answer nothing in M8 data or docs.
- FLAG (audit repair, same human review): three M8 hidden-detail and radio lines seed Act II+ truths and are canon commitments until confirmed. (1) `mem_first_rest` detail 'The last car has no markings. Its doors are welded shut.' suggests human cargo, i.e. the industrial-scale harvest (the knowledge lint's 'harvest' term); neutral swap: drop 'Its doors are welded shut.'. (2) `mf_lowlight_02` detail 'On the tray, a second dressing the shape of your scar. Already used.' commits canon to another subject fitted at the Rain Clinic (Project REDLINE subjects, mystery 2, Act II); neutral swap: 'a second dressing, fresh'. (3) `relay_board` `board_dead` 'Static. Orr says it used to be a whole city in there.' touches mystery 4 (is the Pulse an accumulation of memories); neutral swap: 'Static. Orr says it used to be busier.'. Confirm or swap before Act II writing.

## D-135: First-time Act I pacing grows (~73 s of locked scenes at Normal subtitle speed, ~20-30 s first memory) (FLAG)
- FLAG vs §42/D-083 pacing estimates: budgets are validator-enforced (lines ~15 cps; subtitle speed Slow/Slower is opt-in), everything is skippable, repeat intros cost no control, and the §44 report measures first-view skip rate and cinematic_s. If first-view skips exceed 50%, cut the opening to its two lines.
- Nominal first views (Normal subtitle speed, the `ValidateContent` story table): `uc_opening` 17.0 s (budget 18), `uc_collector_intro` 8.2 s (10), `relay_arrival` 11.7 s (13), `ll_krail_intro` 12.6 s (14), `act1_close` 23.2 s with Iko (26): 72.7 s of locked scenes. Repeat boss intros are 0.8 s non-locking overlays. (The plan said ~75 s; the heading now gives the built 72.7 s.) The first-rest memory adds about 20-30 s. Telemetry: `seq_end` carries `first` and `locked`; the report's timeline column subtracts only locking-sequence time.

## D-136: No pause menu over DialogueBox conversations or Orr's choice; vignettes have their own pause panel (FLAG)
- FLAG vs §24 'pause during dialogue': MenuHost opens menus only on an unpaused tree (ui/menus/MenuHost.gd:_process: `not get_tree().paused`), and both a vignette and ui/dialogue/DialogueBox.gd:open (`get_tree().paused = true`) pause the tree, so the pause menu cannot open during a vignette, any NPC conversation, the new arc beats or Orr's choice (which waits indefinitely). M7's DialogueBox header already reads §24 'pause during dialogue' as 'the world pauses while a conversation is open', which M8 keeps: nothing progresses without input, so stepping away is safe. Opening PauseMenu over them is not safe today: PauseMenu.close_menu (MenuScreen.close_menu) unpauses the tree under the box, its Journal/Map rows close it first (unpausing), and DialogueBox/MemoryScenePlayer (PROCESS_MODE_ALWAYS) would read the Resume press as an advance. The fix (MenuHost opens PauseMenu while DialogueBox.is_open() or a vignette plays; PauseMenu restores the prior paused state; the boxes ignore input while a menu is open) moves to M9 with the settings work (TODO + KNOWN_ISSUES). A vignette lasts <= 60 s and is skipped with a hold; Settings is reachable right before and after. Update (repair 7): memory vignettes (up to 60 s, and a first view's only exit was a hold-skip that marks it remembered, so the Anchor never replays it) now handle `pause` themselves with an in-player panel: Resume / Skip memory / Subtitle size (A2 §3.2). Only the DialogueBox and choice-mode case remains for M9.
- As built (T04): the vignette pause panel has Resume / Skip memory / Subtitle size, freezes the vignette clock and calls `notify_unpaused` on close.
- Resolved in M9 by D-159: the pause menu opens over DialogueBox conversations and Orr's choice.

## D-137: Placeholder ending text is provisional canon (FLAG)
- FLAG for a human (with D-134): ending narration is limited to paraphrases of the §18 ending definitions, but these lines still ship in data: Crown 'The city runs through you now.'; Release 'Three short. Three long. This time the tapping finishes.' (Cell Four payoff), Mara 'You came back. That's new.', Vell 'Relay's full...'; Sever Orr/Mara lines; Nix 'The map redraws itself every morning now.' Review them before Act II writing; knowledge lint exempts data/endings, so this review is the only guard.

## D-138: Memory gallery lives in the journal, not with Sera (FLAG)
- FLAG vs bible §13 'Sera — Archivist: memories/translations/scenes': Sera, a Relay NPC, is not built in Act I, so M8 puts memory replay in the JournalMenu gallery with no NPC (design_arcs R9). A later act may move replay and translation to Sera (TODO); the gallery data (MemoryLibrary, timeline slots) does not depend on where it is shown.

## D-139: M8 story assumes the Undercity campaign start; the debug Relay start shows no opening (FLAG)
- FLAG (process, with D-068): the §44 build is still undecided (Docs/DECISIONS.md D-068). On the Undercity campaign start a first-time player sees uc_opening (Wake 'start' spawn) and relay_arrival. On the debug-only 'Slice (Relay start)' entry (ui/menus/TitleMenu.gd:_new_relay_game, session kind new_relay, Game.START_ROOM/START_ENTRY = Relay 'start') no opening and no Relay arrival plays (require_spawn 'start' in Wake / 'from_undercity' in the Relay), and the first-rest memory surfaces at the Relay Anchor. M8 adds no Relay-start variant (its lines would presume the Undercity radio contact). So the §44 kit must use the Undercity campaign start (onboarding enforce = true) for the M8 story to be seen; a human confirms this together with D-068. Pinned by test_act1_sequences.gd:test_relay_start_plays_no_sequence and noted in PLAYTEST_KIT.

## M9: Endgame / Steam / Accessibility (D-140..D-169)

Numbers follow the plan (`scratchpad/m9/plan.json`, repair rounds 3-5). D1..D7 draft numbers (D-138..D-172, C-0..C-12) are superseded.

## D-140: M9 is Act I scope and starts before the §44 playtest (FLAG)
- FLAG (process, scope).
- The user asked (START M9). CLAUDE.md and §44 say not to scale before the slice passes, the same situation as D-105. Achievements, challenges, NG+, the Null and the demo cover only Undercity, Lowlight, the Relay, the Collector Drone, Warden Krail and the Dash. Later acts add data files. Every number (thresholds, pars, medals, remix values) is provisional until §44. §30 postgame items: challenges, NG+, The Null, achievements and local boards are built in M9. 'Advanced Circuit builds': deferred. Act I has 15 Circuits and all 15 are obtainable (13 sold: 10 by Vell in data/shops/shop_vell.tres and hot_wire, live_current, slipstream by Iko in shop_iko.tres; scavenger from Vell and longline from Dead Air), Core capacity is 4 + 5 shards = 9, and the 15 cost 21 in total (Docs/CIRCUITS.md:6,49; ~43% fits, so builds are real choices). A build-constrained challenge is buildable today (kits carry circuits and ChallengeRules checks capacity); it is deferred because which builds are worth a challenge needs §44 data on what players actually slot, not because of capacity. TODO row (T14 R14.13). circuits_8 asks for 8 of the 15. 'Secrets/endings': the Redline ending stays data-only and unreachable (D-154); no new secrets beyond Act I's. 'Mastery' beyond challenges and achievements (e.g. mastery tokens, weapon mastery): deferred with D-148. Medal thresholds are provisional (D-150).
- As built (T14): 30 achievements, 16 challenges (4 rematches, 4 time trials, 1 movement-only, 1 no-hit, 2 Pulse Pit, 3 Deep Rig strata + the descent), NG+ with remix, the Deep Rig, settings/accessibility, localization readiness and an Undercity demo. Step 3b (T09b) was skipped: `KNOWN_DASH_SKIPS` was empty, so the early-Dash walk found no broken room. TODO rows: Advanced Circuit builds challenge and weapon mastery challenges after §44 (R14.13).

## D-141: One Platform autoload over PlatformBackend; local backend only; Steam is a documented slot (FLAG)
- FLAG vs §36 M9 ("Steam") and §29: no storefront integration is built; Steam achievements, cloud saves, boards and presence stay a documented adapter slot per the user's no-networking rule (§37.7); building the adapter needs an owner decision.
- The local store is the truth and a backend only mirrors it (§37.7). There is no GodotSteam, no SDK and no network code (CrossRules X-4 plus a test). Docs/PLATFORM_SERVICES.md describes the adapter slot: achievements, stats, boards, presence tokens and Auto-Cloud paths.
- As built (T02): `PlatformBackends` knows only `local`; an unknown id warns and plays on local. PlatformRules PL-14 bans network/storefront symbols in `platform/` and `autoload/Platform.gd` (comments stripped); CrossRules X-4 extends the ban to every script under `res://` (comments and string literals stripped; OS.shell_open and JavaScriptBridge included), and build.py PY-NET covers the Python tools (it follows import aliases and `--check` self-tests its checkers, T05).
- Repair (M9 audit): X-4 also bans WebRTC, DTLS and `ClassDB.instantiate("<network class>")` (checked on the literal), bans `OS.execute`/`create_process` outside `res://tests` (tests run the Python `--check`s), and scans every `.tscn`/`.tres` for network node or resource types and embedded GDScript.

## D-142: One M9 save layout; settings and platform data are global; only profile 1 is used (FLAG)
- FLAG vs §29 (multiple profiles; settings saved per profile).
- Profile JSON gets 7 optional keys (igt_tags added in repair round 4) and 7 new flags (no schema bump). user://platform/ holds achievements.json, records.json and ghosts/, keyed by profile where needed. settings.cfg stays global with [meta] version (not a save file). There is still no profile picker (Game.profile_id = 1).
- As built (T01): the seven optional keys are `stats`, `dev_tainted`, `igt_frames`, `igt_splits`, `igt_complete`, `ng_archive`, `igt_tags`; `CURRENT_SCHEMA_VERSION` stays 3 (`test_m9_cross::test_kitchen_sink_save_roundtrip`). Writes go through `AtomicJson` (tmp → .bak → rename).

## D-143: Achievements are global; stats are kept per profile and for the lifetime; unlocks are retroactive
- Unlocks store the earning profile. Re-evaluation on game_state_reset unlocks what an old save already earned. Four or more unlocks at once collapse into one toast.
- As built (T02): only the first evaluation pass after `game_state_reset` is retroactive; if that pass is blocked (theatre, a run, headless), later unlocks are live ones. A conversion to NG+ unlocks only NG+ achievements (`test_m9_cross::test_ngplus_conversion_no_retro_toast_storm`). The toast collapses at `platform_config.toast_collapse_at` (4).

## D-144: Achievements never read Settings and never need something an assist removes (FLAG)
- FLAG vs §6 ('Redline Challenge ... leaderboard eligibility').
- Difficulty-tagged goals belong to challenges. Validator rule PL-10 enforces this.

## D-145: Dev-fabricated profiles, theatre, labs and challenge sandboxes do not earn
- GameState.dev_tainted is set by DevActions.unlock_all, apply_story_preset, grant_all_fragments, force_arc_stage, apply_endgame_state and FlagSandbox.apply_act1_max_state. A dev toggle overrides it. Achievement evaluation is suspended while Challenges.active(), and lifetime stats do not count in runs; challenge_finished is counted once. Amended: a whitelist of challenge feats counts toward lifetime stats only (boss no-hit per boss, Krail clamp stagger, clean Rainline, Pulse Pit best style rank), so one-shot mastery achievements are earnable without replaying Act I; lifetime-only achievements evaluate during runs and toast after the result card. satisfy_ending does not taint (theatre replays are sandboxed); NG+ carries dev_tainted.
- As built (T01, T02, T08): the whitelist is R02.3 (lifetime only, outcome FINISHED, a tainted held profile counts nothing); `lifetime_allowed()` ignores a run's own theatre while the run is active or finishing, the Ending theatre still blocks. Dev challenge finishes and unlock-bypassing starts taint the real profile (T08 review).

## D-146: No grind: counter targets ≤ 25; completion achievements equal the live SliceStats totals (FLAG)
- FLAG (tuning; circuits_8 affordability is tested: test_achievements::test_circuits_8_affordable).
- Counter achievements cap at 25 (platform_config grind_cap, PL-6); there are no 'die N' or 'kill N' achievements. Completion achievements (all_secrets 22, all_fragments 5, all_shards 5) must equal the live SliceStats totals (PL-7), so content changes can never make them unreachable. FLAG (tuning): circuits_8 (8 of the 15 Act I Circuits) is guarded by test_circuits_8_affordable (the 6 cheapest sold Circuits plus the free scavenger and longline must cost no more than EconomyAudit.compute().one_time minus Nix's essentials; about 430 vs 1,772 today), so a price change cannot make it unreachable; the targets are provisional until §44 (D-140).
- As built (T07): PL-6 also warns (full runs only) that style_s and style_redline have no recorded reachability evidence (`AchievementRules.STYLE_EVIDENCE` is empty) until a scripted run reaches those ranks.
- FLAG (repair, M9 audit): the no-unreachable promise is enforced for completion targets and circuits_8 but not yet for style_s (rank S) and style_redline (rank REDLINE): no StyleBot/Pulse Pit run proves Act I reaches them. DemoRules DM-4 now requires STYLE_EVIDENCE before a demo lists a style-rank achievement, so both left `data/release/demo.tres`; the full game keeps them (style never gates, §10). Recording the evidence (or deferring style_redline) needs an owner decision (K-M9-S1).

## D-147: One run director (Challenges) over ProfileSandbox; The Null is a challenge group
- A run swaps Game.state for a sandbox (a kit-built state, or a copy of the profile for Null runs) and keeps the profile object in Game.held_profile. Game.save_game() writes held_profile during a run. Room.death_override lets the director own deaths. Outcomes (records, null_depth_reached) are applied after the restore. It replaces D2's ChallengeSession/save_locked and D3's NullRun/save_source/challenge_space. Sandbox swaps set Game.suppress_leave_capture so the leaving room never writes its player into the wrong state (round 4).
- Size (repair, M9 audit, §37.4): `autoload/Challenges.gd` is the largest non-test script (about 1,100 lines). It stays one director on purpose: the run lifecycle, clocks, fast reset, result timers and notices share one phase machine and one sandbox swap, and splitting them before §44 would spread that state across files. The pure parts already live in `challenges/` (ProfileSandbox, RunClock, RecordStore, GhostCodec); fast reset, ghost-mode cycling and the unlock notices are the next helpers to move out (TODO).
- As built (T04): every RoomExit in a run room is switched off, not only the finish exit, so a run can never walk into a sandboxed world room (finish_room must be empty or the start room, ChallengeData.validate); on_finish_flags apply when ANY attempt of the session finished; reset also works during the 1 s finish beat; the start fade adds no profile play time.

## D-148: Act I challenge set (16); no weapon mastery; no rewards or Mastery Tokens (FLAG)
- FLAG vs §29 (weapon mastery) and §12 (Mastery Tokens).
- Boss rematch ×4 (Collector and Krail, normal and no-hit), time trial ×4, movement-only ×1, no-hit room ×1, Pulse Pit style and endurance, Null strata ×3 plus the descent. Medals, records and achievements are the reward. §29 challenge types map as: no-hit → br_collector_nohit, br_krail_nohit, nh_security_station; time trial → tt_*; movement-only → mo_maintenance_shaft; style target → pit_style; survival AND reactor endurance (§6 Redline Challenge) → pit_endurance (FLAG: one challenge covers two §29 types in Act I); boss rematch → br_*; weapon mastery → not built (deferred: per-weapon challenges need weapon-specific targets that only §44 data can set, and Act I has only the 5 kit weapons; revisit with Act II weapons; TODO row, T14 R14.13). For no-hit rules, falls and Core burnout count as hits; the result card names the cause (fell / Core ran dry / hit taken).
- As built (T08): nh_security_station, br_krail and br_krail_nohit have `dev_bot = none` (no rig ghost). tt_neon_roofs, tt_rainline and nh_security_station unlock on `flag:warden_krail_defeated` instead of `chase_rainline_done` (that flag is only set on an armed chase, so a player who skipped it would be locked out for good); tt_rainline keeps `reveal_when flag:chase_rainline_done`.

## D-149: Assists and reduced hitstop are recorded as neutral tags; same boards, same medals, no filter; medal tiers named in data, distinct from style ranks (FLAG)
- FLAG vs §6 leaderboard eligibility; vs §10 (rank ladder D→…→REDLINE): medals are not style ranks, so they use a separate 5-tier ladder named in data (Clear, Bronze, Silver, Gold, Redline); vs §24 (the assist tag must never shame: neutral glyph and word only).
- Settings.active_assists() lists reactor_assist, damage_assist, aim_assist and no_burnout. Comfort options are never tagged, with one exception: hitstop_reduced (hitstop_scale < 1.0) is recorded as a separate timing tag because it shortens run times (Enemy.gd:248,285); it is shown with its own neutral word 'reduced hitstop', never 'assist' (FLAG vs §24, which lists hitstop intensity as an accessibility option: the tag describes the timing, it is not a judgement, and it never filters or penalises). jump_hold_mode ('Always full height') is not tagged: it only produces inputs a player can make by holding jump. Campaign IGT boards carry the same tags (GameState.igt_tags), plus the neutral timing tag 'checkpoints' (word: 'room checkpoints') while Settings.generous_checkpoints is on, because respawning at the room entry instead of the Anchor runback (Game.respawn_room, autoload/Game.gd:396) shortens campaign IGT; challenge runs do not use it. Run records union tags over the whole run (challenge_started, every settings_changed, finish), like the campaign clock (T04 R04.28/R04.29). Only pit_endurance forces the Challenge Core. Null boards are not split by Core mode (D3's split is cut).
- As built (T04, T08): tier names come only from `RankLadder` (no letter constant in ChallengeData); the list and the result card show '◇ assist' / '◇ reduced hitstop'; `test_m9_cross::test_assist_tags_neutral_everywhere` checks the same medal with assists and no shaming word in any M9 string (CrossRules X-8).

## D-150: Ghosts: transform playback plus an input track; personal best and developer ghosts only (FLAG)
- FLAG vs §29 (leaderboard ghost not viable offline).
- Developer ghosts are baked by RouteBot/BossBot through the real challenge path (GhostBake --check). There is no Krail developer ghost (no bot beats Krail). Ghost files are binary and never Resources from user://. Medals anchor on the developer ghost with a margin: Redline = dev time × ChallengeConfig.bot_margin (1.1) rounded up to 0.5 s, because the bot is frame-perfect with no reaction time; players see it as the 'Rig ghost' (never 'developer') until a human-recorded ghost replaces it; CH-15 warns when Silver < Redline × 1.5 + 3 s; Gold ×1.35, Silver ×1.7, Bronze ×2.4 (FLAG: provisional; a bot time is frame-perfect, so the human tiers leave wide room); CH-10 floor where no ghost exists; CH-13 warns when Gold is within 3 s of Redline. 'Top Marks' asks for Silver.
- As built (T08): seven rig ghosts baked by GhostBake; Krail uses the provisional 3600-frame Redline and the Security Station a Redline from a pacified measuring bake. `ChallengeDevActions.promote_pb_ghost` can promote a hand-played ghost (`dev_hand`, skipped by `--check`).

## D-151: Pad View is map in the campaign and fast reset in runs
- MenuHost.can_open(&'map') is false while Challenges.active(). The rebind catalog whitelists the map/reset overlap (and D-pad Up = interact + move_up).
- As built (T01, T03): `MenuHost.can_open(&"map")` is false in a run; after a user rebinds reset to another pad button, View still opens the map (`test_m9_cross::test_pad_view_is_map_in_campaign_reset_in_challenge_and_null`).

## D-152: IGT counts physics frames (world rooms, unpaused, not transitioning, not in runs); it is not play_time_sec
- Saves from before M9 get igt_complete = false and never post a campaign best. Scripted scenes count, because they can be skipped. Splits: 7 milestone splits (flags and the Relay) plus automatic first-entry room splits (SplitList.auto_room_splits), display-only in 'IGT + splits' mode.
- As built (T04): the run HUD shows campaign IGT only in world rooms (`CampaignClock.in_world_room`) when `speedrun_timer > 0`, splits at 2; the last campaign split clears on `game_state_reset`.

## D-153: NG+ converts the same profile (archived first) and carries the kit; remix is optional data applied at room load; economy-neutral; harder bosses are data variants, not HP (FLAG)
- FLAG vs §29 multi-profile; economy (K-49 headroom); vs §30 (NG+ is postgame after the finale; M9 offers it after the Act I close because only Act I exists); vs §30/§44 (FLAG: no player-facing restore of the cleared save in M9, a deliberate Act I scope cut; a title 'Restore cleared save (cycle N)…' row reusing the DevNgPlusPage restore path is the proposed fix if §44 players ask).
- Remix EnemyData files have scrap_drop = 0, but a SET/SWAP replacement spawns with the replaced enemy's drop and only ADDed enemies drop nothing (T09 R09.11), so remix on pays the same Scrap as remix off (tested with EconomyAudit). Boss HP stays within +10%. §17 telegraph floors hold. WeaponPickup marks its flag when the weapon is already owned, so carried kits keep progression gates (CollectorBay exit). The pre-NG+ save is archived to profile_<id>.cycle<N>.json; restoring it is dev-only in M9 and the NG+ menu says so plainly. Core Shards stay found (husk markers); secret stashes refill at 25% Scrap (NgPlusConfig.secret_scrap_scale, EconomyAudit-checked).
- As built (T09): remixed SET/SWAP keep the base drop, ADD drops 0 (R09.11); secret stashes refill at 25 % and shard spots show husks (R09.2); the Act I card drops the death count (R09.13). NewGamePlus.begin outside the title saves first, so the archive holds the cleared state of that moment. There is no player-facing archive restore in M9 (a deliberate Act I scope cut, FLAG for §44; the proposed fix is a title 'Restore cleared save (cycle N)…' row reusing the dev restore path, R09.15). Playtest's ng_plus event records the remix option (T14).

## D-154: The Null opens after Act I; 3 lore-free strata; null_depth_reached becomes a produced flag (FLAG)
- FLAG vs §15/§23 (postgame after the finale), vs D-132 (the name 'The Null' is kept out of player text: the player-facing label is 'Deep Rig'; only res://world/rooms/challenge is added to knowledge_lint exempt_dirs), vs D-127/D-130 (future-flag entry removed; the Redline ending stays unreachable by construction). Pars are placeholders.
- The Null opens with null_open (derived from act1_complete) and needs the Dash. It has 3 lore-free strata (Static Lane, Breaker Run, The Floor with a Krail data variant) and a Descent run; ranks use the medal ladder names. FLAG vs §15/§23: the bible places The Null as postgame after the finale; M9 opens it after Act I because only Act I exists. FLAG vs D-132: 'The Null' is a knowledge-lint term (data/story/knowledge_lint.tres), so the challenge space is called 'Deep Rig' in every player-facing place (ChallengesMenu group header 'DEEP RIG', room banner district_name in data/districts/null.tres, the Null challenge text in data/challenges/null_*.tres); 'null' is an internal id only. Only res://world/rooms/challenge is added to exempt_dirs; data/challenges and data/districts are linted, and the shipped knowledge warnings stay exactly orr.tres 'Rook'. null_open is derived from act1_complete in Game.set_flag and on load, so every state with act1_complete (including FlagSandbox.apply_act1_max_state and DevActions.apply_endgame_state) has it. FLAG vs D-127/D-130: null_depth_reached moves from the future-flag list to a produced flag (set on finishing The Floor or the Descent); the Redline ending stays unreachable by construction through its other future flags (8 remain). Stage pars are placeholders measured by the route tests; after §44 they are retuned in data and the story role of The Null may rename or move it.
- As built (T10): measured at fixed 60 fps: static_lane 11.63 s with no hit (par 40, redline 30); breaker_run 12.00 s intended, 12.95 s by the bot's expert line (par 50, redline 36; shutter margins NS1 0.45, NS2 0.62, NS3a 1.38, NS3b 0.72 s); The Floor harness kill 2.40 s after the intro (par 100, redline 70). The pars stay placeholders until §44. D-130 (Redline requires The Null) is satisfied as data: null_depth_reached is produced (The Floor and the descent), and the ending stays unreachable through its 8 other future flags. Departures from the D3 design: scanner modes LOW/HIGH (D3 said 'mode 2' for all three), 48 px spike beds with bare 24 px ends, WaveSet as a flat entry list with a wave index, the landing beam at x 1610 (D3: 1580) and NS1 at x 760 / NS2 at x 1400 tuned by the route test.

## D-155: The Null may put a ranged enemy on a breaker clock (FLAG)
- FLAG vs DISTRICTS.md Lowlight rule.
- Breaker Run keeps ≥ 0.35 s of margin with one dodged bolt (measured by a test).
- As built (T10): NS2's Scout Drone keeps 0.62 s of margin in the route test (≥ 0.35 s with one dodge).

## D-156: New challenge-only rooms before §44 (PulsePit + 3 Null strata) in world/rooms/challenge/ (FLAG)
- FLAG (content before playtest).
- The folder is off-map (ContentValidator.OFF_MAP_DIRS), outside WORLD_ROOM_DIRS, and has no economy or secret impact. Their theses (mechanic, visual, enemy ecosystem, boss test) are written into Docs/DISTRICTS.md by T14 (R14.10); the redline/CLAUDE.md 'theses before rooms' rule is kept in substance but the doc lands after the rooms because the doc files are T14's (FLAG: order only).
- As built (T10, T14): the theses are in `DISTRICTS.md` 'Deep Rig and Training Pit (challenge spaces, off-map)'.

## D-157: Settings are catalog-driven; settings stay global; reduced boss damage is its own assist; the assist tag definition (FLAG)
- FLAG vs §29 (settings per profile), §6 (reduced boss damage tied to Story/Assist), §24 hold/toggle (jump only in M9) and §37.2/§44 (new rumble feedback on by default before the playtest).
- Settings are catalog-driven: every option is a SettingDef row in data/settings (label, section, key, kind, default, clamps, description) and Settings.gd loads and saves through the catalog, so a new option is data, not menu code (T03). Settings stay global in user://settings.cfg, not per profile (FLAG vs §29): M9 uses one profile (D-142) and accessibility needs must not reset when a profile changes. Reduced boss damage is its own assist (damage_assist, bosses-only scope available) instead of being tied to the Story/Assist Core mode (FLAG vs §6), so a player can take one without the other. An assist, for tags (D-149), is exactly what Settings.active_assists() returns: reactor_assist, damage_assist, aim_assist and no_burnout; comfort, visual and timing options are not assists. Crouch/slide hold-toggle is deferred (slide ends on release; a latch changes slide semantics and needs §44 data); M9 ships only the auto full jump (FLAG vs §24 hold/toggle options). Text auto-advance ships as a Subtitles setting stored in [accessibility] (default Off; closes D-110's M9 deferral). Rumble keeps the existing vibration_strength default 1.0 (on for pad users) and M9 adds the first rumble output (nothing calls Input.start_joy_vibration today); the HapticEvent list and strengths are provisional until §44 and M10 controller validation (FLAG vs §37.2/§44: if the owner declines, strengths go to 0 in data and the slider stays). Boss Assist: damage_assist's bosses-only scope covers 'more pips'; slower boss telegraphs are deferred (§17 floors are tuned per attack; §23 note).
- As built (T03, T11, T12): the Haptics table is `AccessibilityConfig.haptics`; the rumble default stays 1.0 (the FLAG stands, with the data-only fallback). Text auto-advance closes D-110's M9 deferral (DialogueBox T11, SequencePlayer and memory beats T09). Damage assist in bosses-only scope covers the Boss Assist 'more pips' TODO row; slower telegraphs stay deferred (R11.8).

## D-158: Rebinding rules (FLAG)
- FLAG vs §24 full rebinding (menu actions ui_* stay fixed so a player can never lock themselves out; revisit in M10 with a safe-reset chord); FLAG (debug pad bindings).
- ui_* are not rebindable. Esc and Start stay on pause. cinematic_skip mirrors jump + Enter + pad A. P is a second pause key (web fullscreen eats Esc). The debug_* pad events (L3/R3) are stripped when DevActions.available() is false, so players can bind L3 and R3. Backspace is a fixed back key through its own ui_back action (ignored while a text field has focus), reserved from rebinding; it cancels a rebind capture.
- As built (T01, T03, correcting the plan): Backspace is **not** in `ui_cancel` (Godot 4.3's LineEdit/TextEdit take `ui_cancel` as 'release focus', so a Backspace there could never delete text). Backspace is a fixed back key through its own non-rebindable `ui_back` action, ignored while a text field has focus (`MenuScreen.cancel_pressed()`), reserved from rebinding. A rebind capture can always be cancelled with Esc, Backspace or Start, in ARMING and in LISTENING, and ARMING lasts at most 1 s (`RebindCapture.arm_max_sec`, R03.7/R03.17). Rebound and captured events use device -1 (all devices), as project.godot does. Every sub-page has an explicit Back row (`test_m9_cross::test_web_keyboard_can_back_out_without_esc`). Memory scenes still skip only on `ui_cancel`/pause, not Backspace.

## D-159: Pause over DialogueBox conversations and Orr's choice (closes the D-136 deferral)
- MenuScreen restores the prior paused state on close. The boxes ignore input while a menu is open. PauseMenu hides Map and Journal over a dialogue.
- As built (T11): DialogueBox (class_name) joins the MenuScreen pause owners and ignores input while `MenuScreen.open_count > 0`; Save & Quit aborts a conversation without its effects (it replays).

## D-160: The adaptive assist suggestion is a paused card on respawn (FLAG)
- FLAG vs §23 ('Optional adaptive assistance may suggest settings').
- 'Not now' is focused. At most 2 per session, 20 min apart. Suppressed in challenge runs, labs and theatre. It never applies anything by itself (§23). assist_suggestions is ON by default: the feature is optional because one press ('Don't suggest again') turns it off and it never changes a setting by itself; if §44 players find it intrusive the default flips in data.
- As built (T11): the card answers only after its arm time (R11.11); a Redline Core player is never offered a Core change (R11.12).

## D-161: Colour-blind support is always-on shape cues plus 3 data palettes, with no daltonization shader; 'Always full height' jump may break short-hop routes (FLAG)
- FLAG (risk).
- The route suites run with jump_hold_mode = 1, and the KNOWN_SHORT_HOP list may not grow. §24 says 'high-contrast modes': M9 ships one high-contrast mode plus background dim; a dark-on-light variant needs a second world palette pass and is deferred until final art.
- As built (T11, T12): palettes default / protan-deutan / tritan in `data/accessibility/palettes`, AccessRules AC-1..AC-4; the shape cues are ScannerBeam LOW dashed / HIGH dotted / FULL solid with a '!' lamp, chase chevrons, the Collector eye ring vs disc, hollow empty injector pips and elite corner notches. KNOWN_SHORT_HOP holds only `test_wake_tap_is_not_enough`.

## D-162: Localization uses PO with the English msgid as key (plus msgctxt) and location-key comments; translate at the edge (FLAG)
- FLAG vs the brief wording 'translation keys' and the D1 draft's ACH_* keys.
- Decided: gettext PO catalogs where the msgid is the English source text (with msgctxt only to split homonyms) and a stable location key as a '#.' comment; runtime lookup is Loc.t/f/tn at the display edge, and logic never compares display strings. FLAG vs the brief ('move all user-facing strings to translation keys') and vs the D1 draft's ACH_<ID>_TITLE keys: the location comment is the stable key for tooling, but the lookup key is the source text. Why: source-text msgids keep data files readable and diffable, need no key registry, and let the extractor find every string; the cost is that an English edit invalidates translations (fuzzy on merge). After §44 and before the first real translation, the owner can switch to explicit keys; the extractor already records a location key per entry.
- As built (T06, T13): `StringRules.ENFORCE` is on (L-1/2/3/6/9 are errors; `ExtractStrings --check` and `test_catalog_up_to_date` gate). EventBus.gd documents which payloads are English source (room_entered, boss_started, dialogue_requested) and which are display-ready (hint_requested, interact_prompt_changed). Placeholders may be mixed case (`{Name}`); `%i/%u/%v` are protected by the lints but GDScript's `%` does not support `%i`/`%u`, so authors should not use them.

## D-163: Locale is a setting ('' = auto); en_XA is a generated, dev-only pseudo-locale; no bundled fonts; RTL documented only (FLAG)
- FLAG (rank letters, dev and playtest-facilitator UI are not translated).
- Decided: Settings.locale ('' = follow the OS) with a --locale CLI override that is never saved; en_XA is a generated pseudo-locale (accented and ~35% longer) that only dev builds list; no fonts are bundled (the chain uses the default font plus SystemFont fallbacks); RTL is documented only (layout_direction LOCALE is set on menu roots but not tested). FLAG: style rank letters, dev pages and the playtest-facilitator UI stay untranslated by design, and CJK/RTL are not supported in M9 (known issue). After §44, choosing the first real language decides the bundled font and whether RTL gets a pass.
- As built (T13): the font chain is a FontVariation over the engine face with the locale's SystemFont fallbacks (no res:// fonts ship); `min_font_size` is an additive lift (0 in en and en_XA). FLAG for the M8 owner (D-114/D-120): the memory marks ◆/◇ are not in the default font, so they became • (remembered) and ◊ (waiting); filled vs hollow is kept. The pending memory hint became '— rest at an Anchor' to fit en_XA at 150 %.

## D-164: Line timing reads the displayed (translated) text times LocaleInfo.reading_scale (FLAG)
- FLAG vs D-135 (budgets stay on English source).
- Decided: a sequence line's hold time is computed from the displayed (translated) text length times LocaleInfo.reading_scale; nominal_seconds() stays on the English source so the D-135 pacing budgets and validator checks keep working unchanged, and English timing is byte-identical. FLAG vs D-135 (budgets are measured on English): translated lines may run longer than the budget allows. After §44, the pacing budgets are re-measured, and a per-locale budget is added if real translations exceed them.
- As built (T13): SeqLine.displayed_seconds; dialogue and memory auto-advance read the displayed length the same way; English timing is byte-identical.

## D-165: Demo = the Undercity, as a feature tag (FLAG)
- FLAG (scope; content not stripped; CTA copy is a placeholder to be approved by the owner).
- Content is gated, not stripped. The demo has an isolated user dir and recording off by default. It is not the §44 build (D-068 stays open). Isolation: desktop demos get their own user dir (config/use_custom_user_dir.demo); on Web the custom user dir is ignored (user:// is the origin's IndexedDB /userfs), so a demo on Web (and any --demo/force_demo session) redirects saves, settings, platform data and playtests under user://demo/ (T05 R05.8, DM-8).
- As built (T05, T14): `data/release/demo.tres` lists the ten Undercity-earnable achievements (DemoRules DM-4). `top_marks` is not listed: Silver medals need the training rig, which opens at the Act I close, so a demo never earns it (deviation from the plan's list). Settings._ready loads the default path first; BuildInfo reloads a redirected demo's own settings once Settings is ready (a fallback, K-M9-D2).

## D-166: export_presets.cfg is checked in (8 presets; reverses K-34) (FLAG)
- FLAG (release settings).
- No credentials. Windows and Linux unsigned, macOS ad-hoc. import_etc2_astc=true for the macOS universal build. Web nothreads, no PWA. build.py (stdlib) makes deterministic zips, a manifest, --check and --smoke. §37.9 dependency: the Godot 4.3.stable export templates are needed for build.py builds and --smoke only; --check needs no Godot; rcedit is not used (application/modify_resources=false); the game runtime gains no dependency (recorded in CLAUDE.md, T14 R14.12).
- As built (T05, T14): placeholder bundle ids `dev.redline.game` / `dev.redline.demo`; macOS short_version/version follow the numeric config/version (EX-7), bumped with it to 0.9.0 in T14. The universal macOS zip has its own 60 MB budget (53.4 MB measured).

## D-167: Validator rule modules and cross lints; one dev 'Endgame & build' hub; --tour=endgame with a user:// sandbox
- Cross lints: network ban, raw directory scans, EventBus→Playtest coverage, menu-id parity, SCAN_DIRS coverage. New top-level folders (like D-133 for cinematics/ and story/): platform/ (platform services and backends), challenges/ (run director helpers, clocks, records, ghosts), accessibility/ (assists, haptics, palettes), input/ (rebinding and glyph data; it sits beside §31's player/controller, which keeps the per-frame input sources), l10n/ (Loc and tooling), release/ (build info, demo gate, probe) are added to ContentValidator.SCAN_DIRS; locale/ (PO/POT files only) is added to IGNORED_DIRS. Each keeps one area's scripts together so its validator module and tests own one folder.
- As built (T14): CrossRules X-1..X-10 run last; ALLOWED_RAW_SCANS also lists AtomicJson (user:// tree removal) and NgPlusDevActions (user:// save folder), plus the validator, l10n and capture tool folders. The endgame tour sandbox is `devtools/capture/TourSandbox.gd` (user://capture_tour) on top of T01's user://tour_sandbox platform store.

## D-168: M9 menus register in MenuHost.IDS and are instantiated at runtime; the title layout is fixed; labs move under 'Labs & dev starts…' (FLAG)
- FLAG vs §36 (onboarding is M10): the title shows a one-time 'Comfort & accessibility' link to the existing Settings Quick page, not a guided setup; it is never focused first and disappears after the first title action.
- M9 menus are built from ui/menus/<Name>.gd when the file exists, so Main.tscn is not edited. On the title, the labs and the Relay start (debug builds) move into a 'Labs & dev starts…' sub-page so the title fits 270 px.
- As built (T01, T05): the first-run row is retired by the first title action; a redirected demo saves that to its own settings file (`BuildInfo.is_live_settings_path`).

## D-169: The Relay 'training rig' terminal is a placeholder challenge entry point until Bramm exists (FLAG)
- FLAG vs §13 (Bramm, Trainer: movement/mastery/practice is the hub's challenge giver) and vs §44 (new hub content before the playtest).
- M9 adds one lore-free ChallengeTerminal ('Training rig') to the Relay floor and a title 'Challenges' row, because Bramm is not in Act I content and the brief asks for a Relay entry. It has no dialogue, no NPC and no lore. It stays hidden until the rig opens (act1_complete, or ng_cycle >= 1 in NG+) and then draws dark until a challenge unlocks; the title 'Challenges' row follows the same rule (T04 R04.27, T08 R08.12). Reason: br_collector unlocks before the first Relay visit (CollectorBay → EscapeTunnel → Relay is the only way in), so an unlock-only rule would light the rig mid-story next to Mara and Vell. When Bramm is written (a later act, after §44), the Trainer takes over the entry and the terminal is removed; the Relay tour frame diff is expected.
- As built (T08): the terminal sits at x 740 with the `challenges` spawn at x 700; the Relay tour frames change only after act1_complete (R14.14).

## Presentation overhaul: art, audio, VFX and UI (D-170..D-180)

The user asked for a presentation pass in the Hollow Knight mood, inside the Art Bible frame: "redo the whole thing, add life, add effects, add more animations". A later request added: "Use pika for the assets and add levels and power effect and all you need and upgrades and everything". Pika is not connected and the generator accounts are at 0 credits, so this phase adds no generation calls. Levels (Ironworks, more Act I rooms) and upgrade gameplay are later phases and are not started (TODO). Report: `OVERHAUL_REPORT.md`. D-170..D-172 appeared only as superseded M9 draft numbers (note above D-140), so these numbers are free. No heading used them before this section.

## D-170: Final assets may come from AI generators and from code rigs and painters (amends Art Bible §11) (FLAG)
- FLAG vs Art Bible §11 ("AI-generated imagery for ideation and reference only").
- The user chose AI generators for final assets. The account quota ran out after 9,790.2 credits: 2 images, 6 music tracks, 15 ambience rows and the SFX/UI/footstep takes. The rest of the current final set is code-drawn: pixel rigs for characters, VFX, UI and tiles, plus painters for the environments. That is own work with no AI output.
- **Rights caveat:** every generator row in `assets/SOURCES.csv` has `rights` = "ElevenLabs output, check plan terms". The free plan's commercial terms must be checked before any public build. Pika was requested but is not connected, so no Pika output exists.
- Sources are in `art/source/`, the reproducible scripts in `tools/assetgen/`, and provenance is recorded per file. `assetgen.py --check` proves no drift and full provenance.
- As built (T01..T09): 192 SOURCES rows, 9,790.2 credits in total (music 7,200, ambience 1,580, SFX 551, images 369.2, UI 60, footsteps 30, sprite sheets/tiles 0). 95 rows are own work, 75 are generator output and 22 are failed calls (not charged). An AI or Pika asset replaces a code asset under the same file name, size and SpriteSheetSpec ids with no code change (`OVERHAUL_REPORT.md` §8).

## D-171: Music ships as full tracks per district and intensity with a two-deck crossfader; the 5 synth stems stay as the fallback and as Relay growth (amends Art Bible §10) (FLAG)
- FLAG vs Art Bible §10 ("five synced stems per district").
- Generated music cannot produce sample-locked stems. `MusicSet` / `MusicLibrary` (`data/audio/music/music_library.tres`) hold string paths per state slot (title, hub, explore, flow, boss, memory, aftermath) per music district, plus a default set. A missing file falls through to the next set and then to the stems.
- Transitions have their own fade times: boss 0.6 s, flow 1.0 s, flow→explore 3.0 s, aftermath 2.5 s, memory 1.2 s, default 2.0 s. The crossfade is equal-power. Explore tracks resume and flow/boss tracks restart. AFTERMATH plays the explore track at 0.6 gain. MEMORY, SILENT, Relay explore and the Deep Rig keep the stems.
- Relay growth keeps only the arrhythmic synth layers (lead, pad) over `mus_relay` until a listening pass.
- As built (T08): `MusicDirector` track mode. Headless runs create no players.

## D-172: Parallax planes repeat every 480 px with A/B variants; new motion scales for near, backwall, fog and foreground; the district grade applies to background planes only (amends Art Bible §8; F8/F11) (FLAG)
- FLAG vs Art Bible §8 (960 px period, sky/far/mid only).
- The source resolution limits clean pixels to about 480 px, so a plane alternates A, B, A… (`PlaneSpec.alt_path`).
- Motion ladder (x/y): sky 0/0, far 0.12/0.03, fog A 0.2/0.05, mid 0.3/0.07, near 0.55/0.2, fog B 0.6/0.3, backwall 0.85/0.85, foreground 1.2. Foreground silhouettes are allowed only in the top 40 px and below the floor line, and only where `RoomPresentation.foreground` allows them.
- `BackdropSet.grade` (`district_grades.json` `bg_modulate`) tints only the backdrop layer, never the world, characters or HUD.
- As built (T02, T03): 14 `BackdropSet`s in `data/presentation/backdrops/`. The procedural skyline is kept as the fallback when a plane texture is missing.

## D-173: Atmosphere textures (fog, shafts, lamp glows, vignette) may use up to 4 quantised alpha levels under assets/vfx/atmos/ (Art Bible §4/§9 and the ArtValidator hard-alpha rule) (FLAG)
- FLAG vs Art Bible §4/§9 and the ArtValidator alpha 0/255 rule.
- Soft light cannot be drawn with hard alpha at 480×270 without heavy dither. Everything outside `assets/vfx/atmos/` keeps hard alpha 0/255.
- As built (T01): `ArtValidator.ATMOS_DIR` / `ATMOS_MAX_ALPHA_LEVELS = 4` (besides 0/255), with a test. The ArtValidator `NAME_RULE` was relaxed to `^[a-z0-9]+(_[a-z0-9]+)*\.png$`, so single-word subjects (`vignette.png`) pass.

## D-174: Ambient motion setting (Full / Reduced / Off) for ambient life, particles, fog drift, cloth and parallax bob (F7; a §24 accessibility addition) (FLAG)
- FLAG (§24 addition, a new setting row and new strings).
- `Settings.ambient_motion` is read through `vfx/Motion.gd`, with count scales in `accessibility_config.tres`. It never affects telegraphs, hit feedback or gameplay VFX. Those follow flash reduction.
- Background dim also dims every new plane, fog band and glow.
- As built (T01, T03): overhaul tour frames `ov_v_still_*` and `ov_v_dim_*`.

## D-175: Colour moves off reserved hues (F3–F6, F10)
- Collector cargo `#b8e0d0` and Krail baton tip `#cfe4f2`.
- `EnemyData.color` moves to the sprite mid-tones: Needle `#c9c2b4`, Enforcer `#5a2a30`, Scout Drone `#7a6034`.
- Relay windows move to lamp core `#e0a060` (plus `#b8804a`).
- Visual only: death sparks follow `EnemyData.color`. No gameplay number changed (`tests/fixtures/enemy_data_fields.json` pins every other field).

## D-176: Lowlight green neon (close to the healing green) is NOT recoloured in this phase (F2 deferred) (FLAG)
- FLAG for the lead.
- Recolouring it to rose `#ff7ab0` needs `lowlight_style.py` / `lowlight.py` changes and regenerated room scenes, which is roomgen drift. That is a room-data change and needs the lead's approval. The green `NeonSign`s stay as they are (visible in `ov_b_ll_roof`). KNOWN_ISSUES K-OV-6.

## D-177: Per-room presentation is data keyed by room scene path, not Room exports; visual-only dressing nodes are created at runtime and never collide
- Per-room presentation (backdrop kind, ambience bed, reverb, footstep surface, music district, foreground allowed) is data keyed by room scene path: `data/presentation/rooms.tres` (`PresentationIndex`, with district defaults). It is not a Room export.
- Room `.tscn` bytes and `roomgen --check` stay unchanged. A new district adds rows, not code (`CONTENT_PIPELINE.md`, "Art & audio assets").
- As built (T01, T03): `FogBand`, `LightShaft`, `LampGlow`, `AmbientLife`, `AmbientParticles`, `SwayCable`, `ClothStrip` and `Vignette` (`world/ambient/`) have no collision and are invisible to EncounterDirector and RouteBot. Each uses its own RandomNumberGenerator.

## D-178: New animation hooks and a mask-tint overlay for reserved-red parts (F9)
- **Rook:** turn, land, land_hard, idle_fidget, death, interact, rest, and per-weapon shots mapped from the attack ids.
- **Enemies:** guard_break and dormant.
- **Bosses:** press/volley/dive/sweep families, phase2, rotors_cut and stagger.
- **Maps** for the Sweeper, the Collector Eye and the NPCs (idle / talk / signature).
- SpriteActor fallbacks keep partial art working.
- `*_mask.png` sheets (Rook, Krail) draw a Palette-tinted overlay, so the colour-blind and high-contrast modes retint the visor and Core seam. The baked red stays as the fallback under the mask.

## D-179: SFX: AudioManager chooses override_stream (SfxSynth always synthesises); new ids, 16 voices with priority stealing, an Ambience bus under the SFX volume, footsteps per surface; the synth stays the fallback
- This corrects the phase-A note: `test_feedback` requires `SfxSynth.render()` to return a WAV, so AudioManager picks the override and the synth renders the fallback.
- No new EventBus signal.
- `shoot_pistol` keeps the synth (its take is on hold), as do the memory ids.
- As built (T08).

## D-180: Web and demo builds may leave out music and ambience beds (synth or silence fallback); the full web budget raise is proposed with measured numbers (FLAG)
- FLAG (release budget).
- As built (T09): the web presets leave out `mus_relay`, `mus_lowlight_explore`, `mus_flow` and `mus_boss`, whose states play the synth stems. The web demo also leaves out the Lowlight/Relay-only beds and art.
- Measured web gz payload: 13.55 MB full and 12.56 MB demo, against the 12 MiB (12.58 MB) budget. The demo fits. The full web build is over budget and `build.py` WARNs.
- **Proposal for the lead:** raise the full-web budget to about 20 MB, or keep dropping tracks. The budget is not raised here.
- `build.py --check` (EX-4) proves every excluded asset is only named as a string path behind a `ResourceLoader.exists` guard.
