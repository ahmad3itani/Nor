# REDLINE TODO

## Now: humans
- [ ] The M4 playtest (`PLAYTEST_KIT.md`) is still the gate before M7 batch 2 (Ironworks and later, bible §44). Export playtest builds as **release** so the dev console is off (D-059).
- [ ] **Decide which build the playtest uses (D-068):** the Act I campaign (New Game from the Undercity, about 20–37 min before the Relay) or the old slice (Relay start, debug builds only, K-58).
- [ ] Confirm or overrule the M7 flags: D-061 (M7 before §44), D-062 (Undercity opening, unarmed start), D-063 (pre-Anchor entry respawn), D-068, D-072 (scanners respect i-frames), D-073 (one chase system), D-074 (Rainline G3 slide-jump), D-075 (Smuggler Route order), D-076 (Iko moves to the Relay), D-079 (Collector = first mini-boss), D-082 (shards/secrets/fragments), D-083 (pacing), D-085 (Challenge FZ3), D-087/D-090 (no schema bump), D-093 (air swings hang only on hit), D-101 (the Undercity combines after its boss), D-102 (the Undercity is linear).
- [ ] Try the M6 editor tools in Godot: drop `GapChallenge`, `ClimbSteps`, `Doorway` and `JumpArcPreview` into a room and check the baking, rebuilds and warnings (K-40).
- [ ] Confirm or overrule D-053 (M6 before §44) and D-056 (Python generator as a dev dependency).

## Presentation overhaul: humans
- [ ] **Listen to every audio asset** (K-OV-1): SFX takes, ambience beds and the six music tracks, the loop points (K-OV-2), `amb_relay_hub` for speech, and Relay growth over `mus_relay` (D-171).
- [ ] Check the free ElevenLabs plan's commercial terms for every "check plan terms" row in `assets/SOURCES.csv` before any public build (D-170, K-OV-9).
- [ ] Confirm or overrule the overhaul flags: D-170 (AI and code art as final), D-171 (full tracks, stems as fallback), D-172 (480 px planes, background-only grade), D-173 (4 alpha levels for atmosphere), D-174 (ambient motion setting), D-176 (Lowlight green neon left as is), D-180 (web budget: raise to about 20 MB or drop more tracks).
- [ ] Look at the before/after pairs in `OVERHAUL_REPORT.md` §3 and at `--tour=overhaul`. Judge the code-painted depth (K-OV-8) and Krail's readability (K-OV-7).
- [ ] Approve or refuse the F2 recolour of Lowlight's green neon to rose `#ff7ab0`: a roomgen change (D-176).

## Presentation overhaul follow-ups
- [ ] **AI regeneration queue**, when credits or a connected generator (Pika was asked for, not connected) exist. Every item keeps its file name, size and spec ids, so no code changes (`OVERHAUL_REPORT.md` §8):
  - [ ] Environments: the 41 env items in `tools/assetgen/env_queue.json` (about 8.9k credits; `env_process.py <id>` makes each plane from its raw download and `paint_env.py` then leaves it alone).
  - [ ] `title_logo` first (about 380 credits), then the menu and dialogue frames as a filigree probe (K-OV-5).
  - [ ] Audio: the staged nodes in `tools/assetgen/redo_gen_plan.json` and `sfx_nodes.txt`. About 260 credits for the remaining P1 SFX and missing takes, about 370 for P2/P3, and about 900 per 60 s of music: regenerate `mus_boss` and `mus_flow` at 90–120 s, then make `mus_memory`, `mus_boss_krail`, `mus_lowlight_flow` and the 8 missing beds (K-OV-3). Redo `shoot_pistol` (K-OV-4).
- [ ] Web: decide D-180. If the budget stays, stream or drop more tracks for the full web build (K-OV-10).
- [ ] Move the six older capture tours into the TourSandbox (K-M9-T4) now that the before frames exist.
- [ ] **Later phases the user asked for, not started** (each needs its own plan; bible §44 and redline/CLAUDE.md say no new districts before the playtest unless the user asks):
  - [ ] **Power effects and upgrades:** this phase added the presentation hooks only (`PowerFlourish` on circuit, weapon and ability grants; `CoreAura` in Flow; `JuiceDirector`). New upgrade gameplay (what an upgrade does, where it is bought) is a design change for DECISIONS.
  - [ ] **The Ironworks district** (M7 batch 2): the presentation side plugs in as data (`CONTENT_PIPELINE.md`, "How a new district plugs in"). The district still needs its thesis in `DISTRICTS.md`, rooms, enemies and a boss.
  - [ ] **More Act I rooms:** each one needs a roomgen script, a route test and a `rooms.tres` row. Its backdrop kind is reused or added to `OverhaulTour.KIND_ROOMS`.

## M9 (endgame / accessibility): humans
- [ ] Confirm or overrule the M9 flags: D-140 (Act I scope, before §44), D-141 (no storefront adapter built; Steam stays a documented slot), D-142 (one profile, global settings), D-144, D-146 (incl. style_s / style_redline without reachability evidence, K-M9-S1), D-148 (challenge set, no weapon mastery), D-149 (neutral tags, medal ladder), D-150 (rig ghosts, medal ratios), D-153 (NG+ after Act I, no player restore of the archive), D-154 (the Deep Rig after Act I, 'Deep Rig' name, pars), D-155, D-156, D-157 (rumble on by default, settings global), D-158 (ui_* fixed), D-160, D-161, D-162 (source-text msgids), D-163 (memory mark stand-ins •/◊ vs D-114/D-120), D-164, D-165 (Undercity demo, CTA copy), D-166 (release settings, bundle ids), D-168, D-169 (the training rig until Bramm).
- [ ] Approve or replace the demo CTA copy and the bundle ids before any public build (D-165, D-166).
- [ ] Manual checks the headless gate cannot do: a Web build (stem render stall K-M9-W1, sample audio sliders, IndexedDB saves), Windows and macOS exports (unsigned: SmartScreen / Gatekeeper), real pads for rumble and PlayStation/Nintendo names.
- [ ] Look at the endgame tour frames (`M9_ENDGAME_REPORT.md`) and the pseudo-locale layout.

## M9 follow-ups
- [ ] **Advanced Circuit builds challenge** (kit-based, 9 capacity) after §44 shows which builds players use (D-140).
- [ ] **Weapon mastery challenges** with Act II weapons after §44 data (D-148).
- [ ] Player-facing 'Restore cleared save (cycle N)…' title row, if §44 players ask (D-153, R09.15).
- [ ] Retune medals, Deep Rig pars and remix values in data after §44 (D-150, D-154).
- [ ] A Krail rig ghost once a bot (or a human run) beats him; a Security Station ghost (D-150).
- [ ] Strip non-demo content from the demo pck (a demo-aware map index + `exclude_filter`, K-M9-5).
- [ ] Web: render music stems one layer per frame on nothreads builds if the stall is confirmed (K-M9-W1).
- [ ] `MusicDirector.gd:119` compares a display string (`district_name`); compare ids (L-8, K-M9-L2).
- [ ] Settings should load its redirected `_path` itself instead of BuildInfo's post-boot reload (K-M9-D2).
- [ ] `TitleMenu.open_menu`/`close_menu` should call `_apply_look()`: after UI size or high contrast changes on the title's quick page, the title keeps its old theme (K-M9-U1).
- [ ] `test_group_notice_silent_on_load` should load `tests/fixtures/save_v3_slice.json` + act1_complete instead of a hand-made save (T04 review).
- [ ] Crouch/slide hold-toggle and a dark-on-light high-contrast variant (D-157, D-161) after §44 / final art.
- [ ] Record style-rank reachability evidence for style_s / style_redline (`AchievementRules.STYLE_EVIDENCE`, PL-6 warning), then list them in `data/release/demo.tres` again (DM-4, K-M9-S1).
- [ ] Move fast reset, ghost-mode cycling and the unlock/group-open notices out of `autoload/Challenges.gd` into `challenges/` helpers (D-147, §37.4).
- [x] Suites clean their own `user://test_*` temp dirs, and `test_zz_user_dir_clean` fails on leftovers (M9 audit repair).
- [ ] Move the older capture tours into `TourSandbox` after re-taking the pixel baseline (K-M9-T4).

## M8 (narrative integration): humans
- [ ] Confirm or overrule the M8 flags: D-105 (scope, and M8 before §44), D-108 (hold-to-skip; repeat intros never lock), D-109 (Rook's name), D-110 (six settings pulled forward from M9), D-113 (the surfaced first-rest memory), D-114 (memory timeline order), D-115 (memory blue / red on redacted shapes), D-118 (Rook's choice labels; the choice sits after the card), D-120 (pending tick), D-129 (ending thresholds and Act I links), D-130 (Redline needs The Null), D-131 (the Act I boundary and card), D-134 (arc canon), D-135 (pacing), D-136 (no pause menu over dialogue), D-137 (placeholder ending text), D-138 (gallery in the journal, not Sera), D-139 (the story needs the Undercity campaign start).
- [ ] **Rook's name decision** (D-109): covers `data/npcs/orr.tres` dialogue `orr_report` ("And Rook - don't go up that tower tired."), the on-air choice wording, the Krail / Wake PA designation "Fourteen", the pronoun in `mf_undercity_01`, and `data/playtest/playtest_config.tres` `curious_world` ("I'm curious about Veyra and Rook."). Then update `test_content_validator.gd:test_knowledge_lint_warns`, which pins the single orr.tres warning.
- [ ] Review the canon commitments before Act II writing (D-134, D-137; A3's "Later act" notes are non-binding).
- [ ] The manual first-time windowed run (the M8 gate, not automatable here): Wake → Relay → Krail → card; the opening plays; first-view intros skip only with a 0.8 s hold (a tap advances a line); a Krail/Collector retry keeps control; journal/dev replays skip with a 0.4 s hold; the close then the card; the §44 survey button. With a pad: every menu (pause incl. "Skip scene", Subtitles & scenes, the journal gallery and People, DevConsole Story pages, the vignette pause panel) works with A/B; Orr's choice on D-pad Up only moves the cursor while E confirms; the first Anchor rest shows the "[E]" cue.
- [ ] Look at the story tour (`CaptureTour --tour=story`) against the Art Bible, especially the Relay's cyan budget (K-M8-10).
- [x] **Smoke-test an exported build** (K-M8-22): automated for Linux by `python3 -B tools/build/build.py --smoke` (BuildProbe counts every DataDir scan). Windows, macOS and Web stay manual.

## M8 follow-ups
- [ ] **Act V finale** calls `EndingResolver.resolve` + `EndingDirector.play` (D-126).
- [ ] **Remove the future-flag gate at Act V**: drop the "needs a future flag" rule and each `future_flags.tres` entry as its act lands (D-127).
- [x] **M9: cross-profile endings, NG+.** NG+ built (T09, D-153); cross-profile endings deferred (D-142: one profile).
- [ ] **Raise the ending epilogue thresholds** (Release `memories_remembered` 24, planned arc stages) when later arcs exist (D-129).
- [x] **M9: text auto-advance setting** (cut from M8, D-110). Built: the Subtitles setting (T03 R03.12) with DialogueBox (T11 R11.9) and SequencePlayer/memory (T09 R09.9) consumers.
- [x] **M9: pause menu over DialogueBox and choice mode** (D-136): built in T11 (D-159). MenuHost opens PauseMenu while a box is open, PauseMenu restores the prior paused state, the boxes ignore input while a menu is open. Vignettes already have their own pause panel.
- [ ] Memory replay and translation may move to **Sera, the Relay archivist** (§13, D-138).
- [ ] Data fix: `chart_lowlight`'s reward `map_lens` overwrites Nix's shop counter (K-M8-27).
- [ ] `SliceEndTrigger`: add the `CinematicMode.theatre` guard `SequenceTrigger` has (K-M8-28).
- [ ] `CombatHud`: a hint-queue flush for capture tours (K-M8-29).
- [ ] CaptureTour `_story_act_card`: write `Game.state.flags` directly to clear `dead_air_complete` (as `test_act1_card_header_and_standing` does) and rebuild the card, so `st_act1_card_menu_no_dead_air` shows the "still deaf" line (K-M8-37).
- [ ] Human review of the three canon seeds in M8 hidden details and radio lines (`mem_first_rest` welded doors, `mf_lowlight_02` second dressing, `relay_board` "a whole city in there"), with their neutral swaps (D-134).
- [ ] Final art: the italic narration face (a `FontVariation` slant on the fallback font today), the memory tableau shapes, the ending cards (D-026).
- [ ] If first-view skips exceed 50% in §44 data, cut the opening to its two lines (D-135).

## M7 batch 1 follow-ups (Undercity + Lowlight)
- [ ] Playtest checks: the Undercity timeline against §42 (K-45); whether the Collector eye still threatens (K-54); the Collector's fight length (K-56); Rainline G3 catches (K-44); air juggling after D-093; heads bumping under Power Block's shaft lips (D-098).
- [ ] If the median Relay arrival is under ~25 min: deepen Medical Ruin and First Pursuit (D-083).
- [ ] Widen `test_tunnel_dash_shard_negative_sweep` like the Smuggler/alley sweeps (every air-dodge frame, late take-offs); lower the ledge if it leaks (K-48).
- [ ] `PowerShutter`: report low passes against the slot clock, so S4b stops reading as a close call (K-52, D-099).
- [ ] `test_pb_b3_reach` could add a Hot Wire case now that the circuit exists (D5a landed after Power Block).
- [ ] `DevActions` grant-kit sets `injector_upgrades` but not `injector_upgrades_bootleg`, so the debug kit lacks Iko's charge.
- [ ] RouteBot: a stationary diagonal aim for multi-shot volleys (K-57).
- [ ] Escape Tunnel pistol lesson: widen the diagonal hit band and sweep it in a test (K-61).
- [ ] Power Block: a respawn near the L0 entrance (K-62).
- [ ] Chase, scanner, clamp and tracker numbers still in code: move them to their data resources (K-63).
- [x] **Boss Assist** (M9): 'more pips' is built as `damage_assist` with the bosses-only scope (T11). Slower telegraphs stay deferred (D-157, §23 note).
- [ ] **`timing_assist` setting** (not built, D-073): an announced option that scales pursuer speed and shutter clocks. §23 forbids silent difficulty changes.
- [ ] **Rising-flood pursuer** (deferred): a second `PursuerData` style for a later district.
- [ ] Deferred mechanics, build them when a room needs one (D-078): PowerJunction, LaserGrid, SecurityCamera, AlarmSystem, MovingPlatform, CollapsingPlatform (also CoreConduit, RadioTerminal, the OnboardingValidator, the Shaft Sentinel mini-boss, RouteBot `await`).
- [ ] Final art: banner lettering, the chest-clamp chairs, a bracket for Orr's Escape Tunnel radio (K-53); check the Undercity sea-green against healing green (K-46) and the seepage rain (K-47).
- [ ] Sinks before enemies: the next district needs new stock before any new respawning enemy (K-49).
- [x] Iko's shop stock (D5a), the Undercity intros and The Way Up (D4), the economy audit (D5b), the full Undercity and Lowlight walks (D6), final chart thresholds (D8b).

## M6 follow-ups
- [ ] More modules as enemies need them (patrol, dive, group spacing, retreat: bible §32).
- [ ] An enemy journal (bible §16) fed by EnemyData and kill counters.
- [ ] Room metadata editor dock and camera zones (bible §34, not yet needed).

## M4 playtest (humans, now covers M5 too)
- [ ] Run the playtest (`PLAYTEST_KIT.md`). Also watch whether testers open the map, where, and whether pins and transit get used.
- [ ] Confirm or overrule D-044 (M5 before §44), D-047 (transit gating), D-049 (economy targets) and D-051 (View button).

## M5 follow-ups
- [ ] Cache the map drawing into a texture once there are many districts (K-35).
- [ ] Travel from the map screen, if D-047 says so.
- [x] Room-authoring tooling committed in M6 (`tools/roomgen`, templates).
- [ ] Saved Circuit loadout presets (bible §11), once there are more Circuits.

## M4 playtest (humans)
- [ ] Recruit 5–8 external testers (2+ on a controller, 1+ non-dev machine) and run sessions as described in `PLAYTEST_KIT.md`.
- [ ] Collect the `session_*.json` files and note sheets, then run `devtools/PlaytestReport.tscn`.
- [ ] Confirm or overrule D-038 to D-041 (especially D-039 recording default and D-041 §44 thresholds).
- [ ] Send the report and notes back. Next: data-driven changes per failing §44 line, then a second round.
- [ ] Pick the slide-jump arm from the variant comparison and moments (D-036/D-042).

## M4 follow-ups (after the first round)
- [ ] Switch recording default off for any public/demo build (D-039).
- [ ] Add the next experiment arm only after D-036 is decided (D-042).
- [ ] If testers quit early, record a lighter "exit survey" on quit to title.

## M3 gate, the §44 vertical-slice test (humans; run it with the M4 kit)
- [ ] External playtesters play the build chosen in D-068 (New Game is now the Undercity campaign; the old Relay-start slice is the debug-only "Slice (Relay start)" entry) → end card. Use the checklist in `M3_VERTICAL_SLICE_REPORT.md` §6 and record the end-card time and deaths.
- [ ] Confirm or overrule the flagged decisions D-026 (placeholder art/audio), D-027, D-028 (6 of 10 rooms), D-033 (no map) and D-036 (slide-jump strength) in `DECISIONS.md`.
- [ ] Decide who produces the production art and audio, and whether §44 runs on placeholders (D-026).
- [x] ~~If the slice runs short of ~15 min, pick the next rooms: Power Block and Rainline Chase (D-028).~~ Built in M7 batch 1, with Security Station and the Smuggler Route.
- [ ] The M1 and M2 gates below are still open. The slice exercises both labs' systems, so one playtest can cover all three.
- [ ] Do **not** start M4+ until the slice passes §44.

## M3 follow-ups (only if the playtest asks for them)
- [ ] Slide-jump strength (`slide_jump_bonus` / `slide_jump_height_ratio`, D-036).
- [x] ~~More Lowlight rooms (D-028)~~: Lowlight is complete since M7 batch 1.
- [ ] More Circuits toward the 60–80 target.
- [ ] Saved loadout presets (bible §11) once there are enough Circuits to need them.
- [ ] Map and fast travel (M5 scope, D-033), and Nix, if playtesters get lost.
- [ ] Parry and executions (bible §8): not started.
- [ ] Rebinding UI (bible §24). Settings now save, but there's no remapping yet.
- [ ] A pixel font for world labels and hints.

## M2 gate (humans), covering M1 too
- [ ] Playtest the Combat Lab with keyboard **and** a controller. Use the checklist in `M2_COMBAT_REPORT.md`.
- [ ] Confirm or overrule the flagged decisions D-016, D-018 and D-022 in `DECISIONS.md`.
- [ ] Judge core pressure (F11 modes) and the style rank's legibility.
- [x] ~~Do not start M3 until both labs pass the playtest.~~ M3 was started on request, before the M1/M2 playtest.

## M2 follow-ups (only if the playtest asks for them)
- [ ] A combat tuning panel: extend the F3 panel to the active weapon's `AttackData`.
- [ ] Enemy body blocking or a "shove" (D-024).
- [ ] Pool projectiles and particles if profiling on real hardware shows spikes. The 11 ms max happens on respawn.
- [ ] Parry (bible §8, midgame) and executions. Healing injectors and an elite (Enforcer) arrived in M3.
- [x] Use `score_multiplier` once challenge scoring exists (M9): closed by `pit_endurance` (T10 R10.3).

## M1 gate (humans)
- [ ] Playtest the Movement Lab with keyboard **and** a controller (Xbox or PlayStation layout). Use the checklist in `M1_MOVEMENT_REPORT.md`.
- [ ] Confirm or overrule the flagged decisions D-001, D-005 and D-009 in `DECISIONS.md`.
- [ ] Verify a stable 60 FPS on real hardware, at 60 Hz and at 120/144 Hz monitor refresh rates.
- [ ] Pick a default tuning preset, or ask for a blend of presets, after the playtest.
- [ ] Decide whether to move `redline/` to its own repository (D-001).

## M1 polish candidates (only if the playtest asks for them)
- [x] Physics interpolation experiment (Godot 4.3's 2D interpolation), or 120 Hz physics ticks. Toggles are on F7 and F8. **A human still needs to judge them on a 120/144 Hz display.**
- [ ] Let slides gain or lose speed on slopes.
- [ ] Footstep sounds for running (left out so far to avoid noise before the playtest).
- [ ] An optional brake or steer during a slide. It's fully committed right now.
- [x] An in-game tuning panel (F3).
- [x] Placeholder SFX for jump, land, slide, dodge and dash (synthesized from data).
- [x] Dust VFX for jump, land, slide and dash.
- [ ] Hard-landing roll when holding a direction (needs a design call).
- [ ] World-label font: a pixel font instead of the default font at 8 px.

## Framework (pulled forward only when needed)
- [ ] Rebinding UI. Persist remaps through `Settings` (bible §24).
- [x] Controller glyph switching (`InputGlyphs`, M3). Hot-plug handling is untested.
- [x] A settings menu that calls `Settings.save_settings()` (M3).
- [ ] `AccessibilityConfig` resource once a menu exists.

## Do NOT start until the slice passes §44
- M7 batch 2+ (Ironworks and later districts) and Acts II–V. Bible §44: "If these fail, fix the core instead of producing more content." M5, M6, M7 batch 1 and M8 were built on request before the playtest (D-044, D-053, D-061, D-105).
