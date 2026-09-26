# REDLINE Changelog

## 0.8.0-m8: Narrative Integration (systems + Act I)

Bible §36 M8: "cinematics, memory scenes, NPC arcs, endings and world-state changes." Scope (D-105, FLAG): the narrative systems are built fully and integrated into Act I; Acts II–V and the finale are not built, so the endings are a complete framework reachable only through the dev Ending theatre. Report: `M8_NARRATIVE_REPORT.md`. Decisions D-105..D-139.

### Sequences (cinematics)
- **One sequence system** (D-106): `SequenceData` step lists in `data/sequences/`, run by the new **`Cinematics` autoload** (`cinematics/`, `ui/cinematic/CinematicOverlay.gd`). Steps: line (speaker labels, narration), wait, fade, letterbox, camera, actor move/face/flash, Rook pose, shake, sfx, music, flag, mark, title card, credits.
- A skip and INSTANT run every remaining `finish()`; an abort (room left, Save & Quit, test teardown) only restores, reverts actor moves and flashes, and the scene replays.
- **Act I scenes:** `uc_opening` (Wake, New Game), `uc_collector_intro` and `ll_krail_intro` (first attempt locks and plays in full; retries are 0.8 s non-locking overlays that keep control, D-108), `relay_arrival` (first arrival from the Undercity), `act1_close` (after Krail, before the card; sets `act1_complete` under the fade). Three non-locking radio barks: `bark_market_patrol`, `bark_bell_lift`, `bark_tunnel_orr`.
- **`CinematicMode`** PLAY / AUTO / INSTANT, shared with memory scenes. Headless runs default to INSTANT (`--cinematics=` overrides), so every route and boss test is unchanged; an INSTANT boss intro keeps the M7 timer and leaves the camera alone (D-107).
- **`SkipGate`**: a tap advances a line, a skip is a hold of `cinematic_skip` (0.8 s first view, 0.4 s repeat), or two taps under "Skip scenes: Press twice", or PauseMenu **Skip scene**; 0.25 s grace; presses carried in from before the scene are ignored (D-108).
- New input action `cinematic_skip` (Space / Enter / K / Z, pad A); `ui_accept` / `ui_cancel` gain pad A / B, so **every menu now works from a controller** (D-111, a behaviour change: menu buttons press on pad A and menus close on pad B).
- `Player.cinematic_lock` gates `PlayerCombat` and `ScannerBeam`; `SequenceTrigger` (`play_when`, `autoplay`, `require_spawn`, `once`) never starts while enemies are active; `BossArena.intro_sequence`.

### Settings and accessibility
- New **"Subtitles & scenes…"** sub-page with six settings (D-110): subtitle size (7 / 9 / 11 px), subtitle background (outline / 0.6 / 0.92; DialogueBox outline / 0.92 / 1.0), speaker labels, subtitle speed (×1 / ×1.5 / ×2), skip scenes (Hold / Press twice), memories at Anchors. Defaults render exactly as M7.
- `SubtitleStyle` is shared by the overlay, the memory player and DialogueBox; the skip prompt and title cards follow the size setting. `--subtitle-size=N` sets the size for one session without saving (captures).
- The HUD holds hints, the banner and the fragment card while it is hidden by a scene.
- Text auto-advance was cut and moves to M9 (TODO).

### Memory scenes
- Memory Fragments become **playable vignettes** (`MemorySceneData`, `data/memories/`): a panning tableau, 3–6 player-paced beats, one hidden detail, memory-blue treatment with neutral edge static (D-115). Played by `MemoryScenePlayer` (own pause panel: Resume / Skip memory / Subtitle size, D-136).
- They surface **at Anchors, never on pickup**, one per rest (D-112); the fragment card now says "Rest at an Anchor to remember." A skipped memory counts as remembered.
- **Journal gallery**: a timeline strip (slots 100..600, D-114), replays and "Remember now". `MusicDirector` gets a MEMORY state.
- Act I set: the five fragment vignettes plus the surfaced **"Count the Last One"** on the first rest (D-113, FLAG). `collectible_taken` EventBus signal.

### NPC arcs
- **`NpcArc`** (spine + reactions, sticky, flags only) and **`ArcTracker`**, a `QuestTracker` sibling (D-117). Pick order: story rules > pending beat > stage idle > fallback.
- Act I arcs for **Mara, Vell, Nix, Orr and Iko** (`data/arcs/`), reacting to the bosses, Dead Air, the chart, memories and each other; threads seed later acts. Arc dialogue is economy-neutral (D-122).
- **One Act I choice:** Orr's on-air beat after the Act I close (`DialogueChoice`, `orr_air_named` / `orr_air_ghost`, D-118). The choice box shows an `[E]` / `[A]` footer; D-pad Up (pad interact) only moves the cursor.
- A pending-beat tick over NPCs and the radio board (`UiTheme.TEXT`, D-120); the journal gains a People page.
- `mara_after_boss` is one-shot and plays after her intro; Iko gets a Relay introduction on the Orr path (D-121).

### World state
- The Relay changes with progress: gallery door lamp, Orr's repeater pips, the lit train, Iko's stall, a door watch after the close, Vell's sign, arc props (Mara's bench lamp, Nix's tower sheet, Iko's Spire crates, Orr's on-air lamp) and Mara's post at the alley door after the close (D-123).
- The **radio board** (`relay_board`, a bodiless "Listen" NPC with a new-chatter cue) and Orr's post-Act-I radio line (`orr_radio` rule 0 needs `act1_complete` and `met_orr_radio`).
- Undercity and Lowlight rooms react: Wake's Collector mark, Broken Lift's crew radio, Collector Bay's stranded cargo, Flooded Alley's chalk eye and posters or tags, Market Run's radios and late lamps, the Stack's windows, the Cell Four marks, the Smuggler den's eye, Bell Tower and Warden Tower banners and cargo (`DISTRICTS.md` "World state").
- Three map notes as `MapMarker.NOTE` with `shown_when` (D-124). Hub music layers are data (`data/audio/hub_music.tres`, D-125).

### Endings and the Act I card
- `EndingData`, pure `EndingResolver`, `EndingDirector` (D-126); four endings (Sever, Crown, Release, hidden Redline) with placeholder sequences and a credits roll (`CreditsData`, `SeqCredits`). `FutureFlagSet` (`data/story/future_flags.tres`) makes them unreachable by construction until their acts exist (D-127); the dev theatre plays them in a `FlagSandbox` (D-128).
- `ActData` / `ActLibrary` (`data/story/act1.tres`): the end card reads **"ACT I COMPLETE — RUN"** with up to three "where things stand" lines (D-131). `SliceEndMenu` stays the card, so the §44 kit flow is unchanged.

### Save
- All M8 state is flags (bool/int); no `GameState` key, no schema bump (D-116). A pre-M8 save with `slice_end_seen` gains `act1_complete` on load. `Game.set_flag` ignores numerically equal writes. Pinned by `test_m8_adds_no_game_state_keys` and `test_v3_fixture_loads_with_m8_defaults`.

### Validation and tools
- `ContentValidator`: the **resource content protocol** (`content_flags()` / `content_check()`), `check_resource()` as the test API, producer/consumer multimaps, `count:` conditions (D-119), the visual-only switch lint, NOTE markers away from secrets, sequence rules (budgets, actors, no Rook moves, only `SeqFlag` sets flags), memory/arc/ending/act/credits rules, `validate_story()` cross-area rules, the **Act I knowledge lint** (D-132), `SCAN_DIRS` + `cinematics/`, `story/` (D-133), and a **"## Story"** report section.
- `DataDir.list` / `list_scenes`: export-safe (`.remap`) data scans for every M8 runtime scan (K-M8-22).
- roomgen: `switch(parent=)`, `npc(name=)`, `mapmarker(shown_when=)`, `sequence_trigger(...)`; new fixtures `scaffold_m8_*`.
- **Dev console "Story…"**: sequence, memory and Ending theatres, story state presets (`data/dev/story_presets.tres`), arcs, boss intro replays, the `SequenceInspector` and DebugOverlay ACT/SEQ lines. `StoryTestKit` for tests.
- **`CaptureTour --tour=story`** (51 shots: Act I scenes, the card, memories, the Relay per preset, arcs, before/after rooms, the choice box, a size-2 line, endings, the theatre page, the inspector, subtitle settings). Every other tour forces INSTANT.
- Placeholder sfx `radio_static`, `memory_open`, `memory_beat`, `memory_tear`, `memory_detail`.

### Playtest
- Recorder: `seq_start` / `seq_end` (first, locked, step, skipped), `memory_start` / `memory_end`, `arc`, `choice`, `ending_start` / `ending`, and new `slice_complete` fields. Scene time is `cinematic_s`, never idle time.
- Report: a **Story** section (first-view skip rates with a > 50% warning, memories, arc beats, the Orr split, endings, standing lines) and a "Median min minus cinematic_s" column in the Undercity timeline.

### Tests
- 607 automated tests (192 new, 7 of them from the audit repair), 0 failed. New files: `test_m8_foundation_engine`, `test_m8_foundation_ui`, `test_sequences`, `test_act1_sequences`, `test_memory_scenes`, `test_npc_arcs`, `test_world_state`, `test_endings`, `test_story_telemetry`, `test_story_tools`.

### Audit repair
- **Knowledge lint coverage (D-132).** It now reads every map-marker label (map notes included), arc journal notes (the journal People page), NPC names and speaker labels, as D-132 claimed.
- **An aborted Act I close puts its flags back (D-106).** A Save & Quit after the close set `act1_complete` (under its fade) used to keep it, and the arc stages it enters, while the close and card replayed.
- **Triggers retry** when another play owns Cinematics (a bark, a refused close) instead of waiting for Rook to walk out and back in.
- **A locking scene owns Rook fully:** pits, chase catches, spikes and burnout do no damage under the lock (K-M8-25), and the pause menu hides Map while locked.
- **The interact prompt comes back** after a scene, dialogue or menu without stepping off and on again.
- **Memories:** the Anchor saves again after its rest memories (their flags survive a quit); an aborted playback emits `memory_playback_aborted`, so the music leaves MEMORY and the Anchor drops its follow-up (K-M8-30).
- **Scene timing is data:** `data/cinematics/cinematic_config.tres` (`CinematicConfig`) holds the skip gate times, letterbox, typing rate, line auto-time formula, choice arm delay and trigger retry (D-108; values unchanged).
- **Exit hygiene:** `ValidateContent` and the test run exit with no leaked resources again (static story caches cleared at exit; `StoryPresets` no longer casts to its own class; no reference cycle in the arc test helper; BossArena drops coroutine locals before its timers).
- **Content:** Orr's Relay arrival cites the open door only if the player heard him promise it, and no longer repeats the radio's "friendly. Mostly."; his `orr_report` crates line agrees with the M8 opening ("meant to carry you out in"); Vell's Relay sign keys on Krail's defeat (a world fact), not her arc stage (D-123); future flags for the M9 postgame read "M9 postgame", not "Act 9".
- **Docs:** README and `project.godot` describe M8; D-134 flags three canon seeds in hidden details and radio text; D-135's heading gives the built ~73 s; the §42 sentence in the M8 report is corrected; line-number references to `orr.tres` became dialogue ids; the CONTENT_PIPELINE line-time formula includes its 2–7 s clamp.

## 0.7.0-m7: District Production, batch 1 (Act I: Undercity + Lowlight)

Bible §36 M7, batch 1 (D-061). Report: `M7_DISTRICT_REPORT.md`. District sheet: `DISTRICTS.md`. Decisions D-061..D-104.

### New Game
- **New Game starts unarmed in Undercity/Wake** (`data/world/onboarding.tres`, `OnboardingConfig`, D-062). The title subtitle is data ("Act I — Undercity to Lowlight"); the end card is reworded for Act I.
- Before the first Anchor rest, death and Continue return to the last room entry (`GameState.last_entry_room/last_entry_id`, D-063), or to an `EntryCheckpoint` (D-088). No save schema bump (D-087, D-090).
- The Core HUD stays hidden until the first Flow Zone (`core_hud_hidden`, D-081).
- Debug builds keep a "Slice (Relay start)" title entry (session kind `new_relay`, D-068).
- Weapons are pickups: `PulseBladeRack.tscn` (Medical Ruin) and `ServicePistolDrop.tscn` (the Collector's reward), via `WeaponPickup`.

### 00 Undercity (new district, 7 rooms, `world/rooms/undercity/`)
- **Wake:** movement, jump and interact lessons; the ward shutter with a lever on each side; a solid sill reached only by a held jump (D-098).
- **Medical Ruin:** the Pulse Blade rack, the dormant practice Needle (`needle_dormant`, 0 Scrap), three live Needles, the extraction pit, the `sb_uc_med_shelf` stash.
- **Maintenance Shaft:** three climbs, the first composition (Needle + Scout Drone on Floor 2, `max_attackers` 2, D-089), the first secret `uc_shaft_closet` with `mf_undercity_01`, and the crew pocket with the `uc_note_crew` note.
- **First Pursuit:** the slide lesson, the **Collector eye** chase (`CeilingTracker`, D-069), pair 2, the `uc_pursuit_cache` secret, Orr's radio (the first NPC), the `pursuit_mid` EntryCheckpoint, and a HatchLive switch that turns the red hatch ring off after the boss.
- **Broken Lift:** the lift shaft, **FZ1** at half drain with a floor of 1 (the safe Core introduction, D-070/D-085), a ledge Needle (`needle_ledge`, D-097), the car-roof stash, and **`uc_lift`, the first Anchor**.
- **Collector Bay:** the **Collector Drone** arena (D-064); the right exit needs the pistol (`got_service_pistol`, D-100); the Service Pistol drops at (252, 0); the vent secret `uc_collector_vent` (40 Scrap).
- **Escape Tunnel:** the Watcher pistol lesson (shot diagonally), the pistol-only panel `uc_tunnel_panel`, **FZ3** at full drain with a Needle and a Hopper, Orr's second radio call, the Dash-only shard `cs_uc_tunnel_dash`, and the gallery door up to the Relay.
- Theme `data/districts/undercity.tres`; palette `tools/roomgen/undercity_style.py` (Art Bible §3).

### 01 Lowlight completed (4 new rooms)
- **Power Block**, the Grid thesis room (D-071): four floors introducing, reinforcing and combining breaker → timed shutter, the Transformer Core landmark, the Meter Room secret, the `power_block` Anchor and the reroute lever (`lowlight_power_rerouted`).
- **Security Station:** scanner lanes (calibration, then live), the cell block and the Cell Four secret (`mf_lowlight_04`), the Monitor Corridor, and the roof breaker that darkens the searchlight.
- **Rainline Chase:** the elevated line with the **Sweeper** chase (`ChaseDirector 'rainline'`, D-073), the G3 slide-jump over the LowRoad catch (D-074), the `rc_signal_box` secret and the `rainline_platform` Anchor.
- **Smuggler Route:** the optional canal loop (D-075): the Pump Room shutter, the floodway, the Dash shrine `cs_smuggler_dash` (D-094), the den with the `smuggler_den` Anchor, **Iko**, the heavy-wall loft cache and the lever that unbolts the hatch to the Apartment Stack.
- Existing rooms: the Relay gains the gallery door to the Undercity and Iko (after `met_iko`); Neon Roofs leads to Power Block and gains the RainlineLive lamp; the Apartment Stack gains the hatch (needs `shortcut_smuggler_route`, with a HatchGate, hint, map marker and neon); Bell Tower is entered from the Rainline; Warden Tower gains the **Grid Clamp** with two high breakers and `reward_position` (208, 0).
- Bell Tower and Warden Tower moved on the world map (D-080).

### Mechanics
- `CeilingTracker` + `TrackerConfig` (the Collector eye; lock builds only while Rook stands still).
- `CollectorDroneBehavior` (card deck, lanes, poise lock), `BossBot` for boss timing tests; `BossArena.reward_position` (D-077).
- `Breaker`, `PowerShutter` + `ShutterTiming`, `GridClamp` + `ClampTiming` (the Grid).
- `ScannerBeam` + `ScannerData` (nine presets in `data/level/`, D-072).
- `ChaseDirector`, `Pursuer`, `PursuerData` (`derail_x`, `runout_speed`), `ChaseCheckpoint`.
- `FlowZone.drain_scale` / `drain_floor`; `NpcProfile.figure` / `verb` (bodiless radios and terminals, D-065); `NPC.present_when` with map pins that follow it.
- `EntryCheckpoint`, `WeaponPickup`, `FlagDeclaration` (world-skeleton stand-in, none left), `HintTrigger.skip_when` (D-096).
- **Changed:** air swings hang only when they connect (`AttackData.air_velocity_on_hit`, D-093). Breaker placement lint uses every grounded swing (D-095). `Room` places the player at its spawn before adding it (D-091).
- Player/enemy scaffolding: pit override, nonlethal damage, shove, exported enemy facing, `debug_draw`; `Enemy` boss flag, `min_telegraph`, ranged poise scale, `lock_aim`.
- Enemy data: `collector_drone`, `needle_dormant`, `needle_ledge`; attacks `collector_*`, `grid_clamp_attack`.

### Story, quests and economy
- NPC profiles: `orr_radio`, `uc_terminal_intake`, `uc_note_crew`, `iko`; Orr and Mara gain their Undercity intros (D-086). Lore: `mf_undercity_01` "It Won't Come Out", `mf_lowlight_04` "Cell Four".
- Quest **The Way Up** (`way_up`, 30 Scrap).
- **Iko's shop:** Bootleg Injector 260, Hot Wire 150, Live Current 120, Slipstream 130. `Game.injector_bonus` counts `injector_upgrades_bootleg`. Hot Wire, Live Current and Slipstream join the catalog (15 Circuits).
- Core Shards 3 → 5 (capacity 9), Memory Fragments 3 → 5, secrets 10 → 22 (D-082).
- `EconomyAudit` reports a per-district breakdown. Final audit: one-time 1,772, sinks 2,230, coverage 79%, re-clear 332 of 334 (`ECONOMY.md`).
- Chart thresholds per district: Lowlight 0.50, Undercity 0.40 (D-080).

### Playtest
- Recorder: first dodge, key flags, `pt` on every event, boss id on `boss_start`, tracker locks, scanner trips (live / calibration), breakers, clamp drops, shutter passes, chase catches.
- Report: separate Krail and Collector lines, "Lowlight time, Relay arrival → slice_complete", the **Undercity timeline** (campaign runs only), and the district set-piece tables.
- Survey: the Collector Drone, the Collector eye and the Rainline Sweeper join "Which enemy do you remember most?"; a new unscored "The Collector Drone felt fair." (still ten scored §44 questions).

### Tools and tests
- Room generators per room: `tools/roomgen/uc_*.py`, `ll_*.py`, with `undercity_style.py` / `lowlight_style.py`; fixture generators `fixtures_*.py`; new helpers (`weapon_pickup`, `respawn_point`, `declare_flags`, `scanner`, `breaker`, `shutter`, `clamp`, `chase`, `tracker`, `flow(drain_scale, drain_floor)`, `enemy(data=)`, `hint(skip_when=)`).
- RouteBot: `shoot`, `dodge` and `dodgejump_airdodge` steps.
- `CaptureTour --tour=undercity` (every Undercity spawn plus a Collector fight shot).
- `test_door_contracts` (D-092), shared route-test harnesses `test_undercity_routes` and `test_lowlight_m7_routes` (each room's route and extra tests, the full Undercity walk from New Game, the full Lowlight chain), `test_onboarding` (v3 save fixture), `test_tracker`, `test_boss_collector`, `test_power_shutter`, `test_boss_grid_clamp`, `test_security`, `test_chase`, `test_props_m7`, `test_scaffold`.
- Tests: 415 (226 new).

### Audit fixes
- **Boss exits open on the reward, not the win (D-100).** Collector Bay's way out needs `got_service_pistol` and Warden Tower's needs `unlocked_dash`, so nobody reaches the pistol lesson or the Relay's Dash end card without the reward. `BossArena` also seals `ExitGate` on a re-armed fight and reports its reward's flag to the validator.
- **Hints queue (D-103).** `CombatHud` holds a hint at least 2 s before the next one shows. Security Station folds its calibration note into the first beam's hint, and the Maintenance Shaft's air-attack hint moved under the Scout.
- **Broken tubes are a distinct secret cue (D-104).** `NeonSign.broken` (askew, half lit, stuttering). The ambient tubes that copied the cue became 3-stroke tubes, the Collector Bay vent gained a cue, and the pump wheel and tram lost their sodium accents. The Collector Bay vent alcove no longer drops Rook out of the sealed arena.
- **Flagged:** the Undercity's §41 order (D-101) and its lack of loops (D-102).
- Small fixes: a scanner-only breaker circuit (Security Station roof) lights its breaker lamp for the offline window; the dev console restarts the Collector Drone too; `OnboardingConfig.validate` checks that the start entry is a spawn in the start room; Orr's shaft call no longer promises a Core burn in FZ1; Orr's radio speaks in the Undercity cyan and the intake terminal in sea-green; doc corrections (D-094 sweeps, ECONOMY enemy count 59, KNOWN_ISSUES table, TODO, K-23, K-35).

## 0.6.0-m6: Content Pipeline

Bible §36 M6 (D-053). Report: `M6_CONTENT_PIPELINE_REPORT.md`. Guide: `CONTENT_PIPELINE.md`.

### Validation
- `ContentValidator` + `ValidateContent.tscn`. It covers:
  - broken references;
  - data `validate()`;
  - room lint;
  - quest/dialogue flag lint;
  - a collectible tracker;
  - the Art Bible checks.
- Exit code 1 on errors.

### Rooms
- `TraversalMetrics`: recorded jump arcs, re-recorded with `MovementProbe -- --write-metrics`, with a staleness test.
- Templates:
  - `GapChallenge` (with a catch well and a gate warning);
  - `ClimbSteps` (warns on step rise);
  - `Doorway`;
  - `JumpArcPreview`, an editor gizmo.
- `tools/roomgen` (Python 3) is committed, with `--check`.

### Enemies
- `EnemyBrain` and modules: MoveApproach/Hold/Hover/SlowTurn, AttackRule, GuardFrontal, and the Look extras.
- Needle, Shield, Scout Drone, Hopper, Watcher and Enforcer now run on data brains; their six scripts are removed.
- New data-only **Signal Drone** (not placed).

### Art
- `SpriteSheetSpec`, `SpriteAnim` and `SpriteActor`; enemy and Rook sprite swap-in.
- `ArtValidator`; `assets/` conventions.

### Dev tools (backquote, debug builds)
- Teleport, unlock-all profile, quick boss restart, enemy spawner, save-state inspector, hitbox view and performance graph.

### Changed
- RouteBot holds jump until landing (D-060).

### Tests
- 189 (23 new).

## 0.5.0-m5: World Framework

Bible §36 M5, built on the existing slice (D-044). Report: `M5_WORLD_FRAMEWORK_REPORT.md`. Economy: `ECONOMY.md`.

### Map (bible §20)
- `world/map/`: WorldMapData (room offsets, transit links, rules), WorldMapIndex (reads rooms), MapProgress (fog cells), MapMarker.
- Map screen (M / pad View, or the pause menu):
  - fog;
  - outlines from visits or the base map;
  - Anchors, NPC pins, bosses, gates, ability gates;
  - quest notes, pins, the dropped cache, transit lines;
  - district completion;
  - pan, zoom and pin.

### World
- **Nix, the cartographer:** base map, transit pass, Surveyor's lens.
- **Chart Lowlight** quest. Dead Air gets map notes.
- **Transit** between rested Anchors, from the Anchor menu.
- **NPC state:** talk counts, and condition rules in dialogue.
- **WorldStateSwitch:** the Relay gains a radio mast, Krail's banner and Nix's city map as you progress.
- The journal shows district completion.

### Economy
- `EconomyAudit` and `test_economy`.
- Walls and four secret spots now hold Scrap, raising first-run coverage from 35% to 59%.

### Save
- Schema v3: explored bitsets, pins and Anchors rested, with a v2 → v3 migration.

### Telemetry
- Map opens, pins and fast travel are recorded. The report shows map opens per room.

### Fixed
- Quest rewards that set flags re-entered completion and paid out twice.

### Tests
- 166 (20 new).

## 0.4.0-m4: Validation tooling (awaiting the human playtest)

Bible §36 M4 instrumentation. The playtest itself needs external testers (D-038). Report: `M4_VALIDATION_REPORT.md`. Kit: `PLAYTEST_KIT.md`.

### Recording (`autoload/Playtest.gd`, `playtest/`)
- One local JSON session per New Game or Continue. Nothing is sent anywhere; recording is disclosed on the title screen and can be turned off in Settings.
- **Records:**
  - rooms and dwell time;
  - damage and deaths with cause;
  - pits, heals and Anchors;
  - secrets, quests, dialogue, purchases and loadouts;
  - hints, boss attempts and phases, and pauses;
  - hits and kills per attack, and style peaks;
  - position samples;
  - controller vs keyboard time;
  - the real frame-time histogram per room, and hardware.
- `take_damage()` carries a damage source (D-043).
- **Experiment arms** (`PlaytestVariant`): baseline vs a stronger slide-jump (D-036), rotated per session or pinned in Settings.

### Feedback
- Pause menu **Report a moment**: a tag, an optional note, and the player's position.
- **§44 survey:** 13 button-only questions, 10 of them scored against §44 (D-041). It's offered at the end of the slice and in the pause menu.

### Analysis
- `devtools/PlaytestReport.tscn` builds `REPORT.md` plus room heatmaps. It covers:
  - the §44 scorecard;
  - completion and deaths;
  - confusion signals;
  - favourite mechanics;
  - controls;
  - performance;
  - the variant comparison.
- RouteBot slide-jumps take a lead distance. The D-036 hypothesis is measured and locked in by a test.

### Tooling and tests
- 146 tests (16 new).
- The capture tour shows the moment and survey screens.

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
