# REDLINE Content Pipeline (M6, extended in M7, M8, M9 and the presentation overhaul)

How to add rooms, enemies and art without touching engine code, and how to prove they work. Every command below runs from `redline/`.

## The gate: validate everything
```bash
godot --headless res://devtools/content/ValidateContent.tscn    # exit 1 on errors; add -- --out=/abs/report.md to save the report
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn     # full suite (it runs the validator too)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=economy   # after any enemy, drop or price change
python3 -B tools/roomgen/lowlight.py --check                    # the pre-M7 rooms
for f in tools/roomgen/uc_*.py tools/roomgen/ll_*.py tools/roomgen/fixtures_*.py tools/roomgen/null_{static_lane,breaker_run,floor}.py tools/roomgen/ch_*.py tools/roomgen/remix_act1.py; do python3 -B "$f" --check || echo "DRIFT: $f"; done
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --check   # M9: the string catalog is current (a gate since StringRules.ENFORCE)
godot --headless --fixed-fps 60 res://devtools/GhostBake.tscn -- --challenge=all --check   # M9: rig ghosts match their challenges
python3 -B tools/build/build.py --check                         # M9: export presets and the tools' no-network rule
python3 -B tools/assetgen/assetgen.py --check                   # overhaul: asset rebuild drift, provenance, loop flags, reserved colours
```
All of these must pass before a content change lands. `--check` exits 1 when a scene no longer matches its script. Use `python3 -B` so no `__pycache__` is written into the repo.

The validator checks:
- **References:** every literal `res://` path in scenes, data, scripts and `project.godot` must exist.
- **Data:** every resource in `data/` passes its own `validate()`. Dialogue gifts, shop items and quest rewards must exist in the catalog; menus opened by dialogue must exist; map notes must point at map rooms.
- **Rooms:**
  - a theme and names;
  - a world-map entry;
  - exactly one default spawn, and unique spawn ids;
  - a spawn for every Anchor;
  - exits that land on real entries;
  - hint actions that exist in the input map;
  - globally unique `persist_id`s;
  - enemies with data;
  - the **content protocol** (M7): any node may define `func content_errors(room: Node) -> PackedStringArray` (placement rules, e.g. a Breaker in grounded reach, a shutter column too far above the floor, a chase checkpoint off a block top) and `func content_flags() -> Dictionary` (flags and conditions it produces or reads, e.g. a lever's flag, a shutter's latch, a hint's `skip_when`). The validator runs it for every node, independent of the node's type.
- the **resource content protocol** (M8): any resource in `data/` may define `func content_flags() -> Dictionary` (flags it sets and reads, conditions it checks) and `func content_check() -> PackedStringArray` (checks that read other files; no room argument). Sequences, sequence steps, memory scenes, arcs, endings, acts, hub music layers and `MapMarker` notes use it. Producers and consumers are kept as multimaps (`ContentValidator.producers` / `consumers`), so a second producer is visible. Tests lint an in-memory resource with `ContentValidator.check_resource(res)`.
- **World-state switches are visual only** (M8, D-123): a solid block, enemy, pickup or interactable under a `WorldStateSwitch` is an error ("SolidCrate under a WorldStateSwitch (visual only)").
- **Story** (M8): see "Story content" below.
- **Quests and dialogue:** every flag that data requires must be set somewhere. Flags that are set but never read produce warnings.
- **Art:** the Art Bible checks (below).
- **Collectible tracker:** a table per room.

## Rooms
**Metrics come from the real player.** `data/level/traversal_default.tres` stores the recorded arcs of the run-jump, slide-jump, dodge-jump and dash-jump.

| Technique | Peak (px) | Reach (px, centre) | Widest gap with 6 px margin |
|---|---|---|---|
| Run-jump | 56 | 103 | 103 |
| Slide-jump | 45 | 118 | 118 |
| Dodge-jump | 56 | 149 | 149 |
| Dash-jump | 56 | 237 | 237 |

After changing movement tuning, run `godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn -- --write-metrics`. `test_room_templates` fails until you do.

**Templates** (`world/templates/`, `@tool` scenes you drop into a room):

| Template | What it builds | Guarantees |
|---|---|---|
| `GapChallenge` | Near and far ledges sized for a technique (+ margin, optional rise), with an optional catch well | The route bot clears it with that technique. The editor warns when a weaker technique also clears it ("not a gate"). |
| `ClimbSteps` | Zig-zag one-way steps | Warns when `step_rise` exceeds the real jump peak minus safety (48 px steps are the norm) |
| `Doorway` | An edge exit plus its entry spawn (36 px inside, facing in) | Doorways line up on the world map; you never spawn inside an exit |
| `JumpArcPreview` | An editor-only drawing of where each technique lands | Uses the recorded arcs, not formulas |

In the editor, templates bake their nodes into the scene. If a script writes a template without its children, it builds them at runtime, and the map, validator, heatmaps and economy audit expand it too.

**Scripted rooms:** `tools/roomgen/` (Python 3, standard library only). `lowlight.py` writes the pre-M7 rooms (Relay, Flooded Alley … Warden Tower). Since M7 **every new room has its own generator**: `uc_<room>.py` for the Undercity and `ll_<room>.py` for new Lowlight rooms. Each imports `RoomGen` and `finish` from `roomgen.py` and its district's palette module (`undercity_style.py`, `lowlight_style.py`), writes one room and calls `finish()`. Test fixtures have generators too (`fixtures_*.py`, writing `tests/fixtures/*.tscn`); `fixtures_scaffold.py --check` first runs a Python self-test of the helpers' emitted text.

```bash
python3 -B tools/roomgen/uc_wake.py --check    # does the scene still match its script?
python3 -B tools/roomgen/uc_wake.py            # regenerate (byte-identical when nothing changed)
```

**Exits across districts:** `exit(x, y, w, h, target, entry, flag)` takes a bare room name for Lowlight (`"BellTower"`) and a folder-qualified one for anything else (`"undercity/Wake"`).

**Helpers added in M7** (property names are what the node scripts export):

| Helper | Builds |
|---|---|
| `weapon_pickup(scene, weapon_id, flag, x, y)` | A `WeaponPickup` scene (`PulseBladeRack`, `ServicePistolDrop`) |
| `respawn_point(spawn_id, x, y, w, h)` | An `EntryCheckpoint`, a mid-room respawn before the first Anchor (also add `spawn(spawn_id, …)`) |
| `declare_flags(*flags)` | A `FlagDeclaration`: stub rooms only, stands in for a flag a later room will produce |
| `tracker(name, rail, y, wake_x, lost_x, config, visible_when)` | The Collector eye (`CeilingTracker`) |
| `breaker(bid, circuit, x, y)` / `shutter(sid, x, y, w, h, circuit, timing, latch_flag)` | The Grid: a player-only breaker and a latching `PowerShutter` (timing from `data/level/shutter_*.tres`) |
| `clamp(cid, x, top_y, width, raised_bottom, timing, circuits, hint_id, hint)` | A boss `GridClamp` |
| `scanner(sid, x, data, top_y, bottom_y, circuit, offline_open, offline_warn, phase)` | A `ScannerBeam` (`data/level/scanner_<data>.tres`); the node is named `Scanner_<sid>`, which the playtest recorder relies on |
| `chase(cid, data, path, speed_scale, start_area, end_area, checkpoints)` | A `ChaseDirector` with `ChaseCheckpoint`s (`data/world/chase/<data>.tres`) |
| `flow(…, drain_scale, drain_floor)` · `enemy(…, ai, data)` · `npc(…, present_when)` · `hint(…, skip_when)` | Per-zone drain, enemy data variants and dormant enemies, NPCs that appear by condition, hints that stay silent by condition |

**Helpers added in M8:**

| Helper | Builds |
|---|---|
| `switch(name, condition, parent="Props")` | A visual-only `WorldStateSwitch` (children added with `parent=` the returned path). Name it; never rely on numbered `Neon#`/`Decor#` names, which shift when a room is regenerated |
| `npc(profile, x, y, …, present_when, name=)` | An NPC post: `NPC_<id>` is the primary node, a second post is `NPC_<id>_<post>` with an exclusive `present_when` |
| `mapmarker(x, y, label, resolved_when, kind, shown_when=)` | A map pin; `kind = 2` (NOTE) with `shown_when` is a rumour or arc note |
| `sequence_trigger(name, seq_id, x, y, w, h, play_when, autoplay, require_spawn, once)` | A `SequenceTrigger` for `data/sequences/<seq_id>.tres`, always named. Append new nodes at the end of a room script, so existing numbered names don't move |

**Decor:** a `decor()` or `neon()` origin is its **bottom-centre**, so `y` is the prop's bottom edge. Props placed by their top draw inside ceilings (several M7 specs did, D-098). Decor draws no text.

The `.tscn` files are what the game loads. If you edit a room in Godot, `--check` will report it as drifted; after that, mirror the change in the script or stop regenerating that room.

**Checklist for a new room:**
1. Build it (editor + templates, or its own roomgen script).
2. Add an offset in `data/world/world_map.tres`. `test_world_map` checks the doorways line up.
3. Add a `RouteBot` route: `tests/unit/test_slice_routes.gd` for the pre-M7 rooms, `test_undercity_routes.gd` / `test_lowlight_m7_routes.gd` for M7 rooms (your functions go below the frozen harness; use `_campaign(blade, pistol, core_shown)`, `_enter`, `_pacify`, `_assert_exit`). The route stops at the exit and asserts its contract.
4. If the room has doors other rooms rely on, add its row to `tests/unit/test_door_contracts.gd` (exit rect, target, own entry position and facing, `requires_flag`, asserted exactly).
5. Run the gate above. Run `--filter=economy` if it has enemies or Scrap.
6. Check the room in game with the dev console (teleport), and in `CaptureTour`.

**Building a whole district (the M7 world-skeleton flow, D-084):**
1. Write the district's four lines and §41 row in `DISTRICTS.md` and its palette in `ART_BIBLE.md` §3.
2. Land a **skeleton** first: a stub scene per room with final bounds, doors and spawns (no `requires_flag` yet), the world-map entries, the door plumbing in existing rooms, the `test_door_contracts` rows and a placeholder test per room. Where a flag's real producer is in a later room, the stub calls `declare_flags(...)`; the validator warns "stub flag declaration" instead of erroring on a consumed flag with no producer.
3. Replace one stub at a time. Each room change removes its own `FlagDeclaration` when it adds the real producer, sets its row's `requires_flag`, and passes the full gate with no expected failures.
4. Finish with the full walks and `test_no_stub_declarations_left`, then set the district's chart threshold from measured standable coverage (`test_thresholds_match_standable_coverage`).

**Rules learned in M7:**
- Never put a literal `res://` path to a file that doesn't exist yet into a scanned script, scene or resource; the reference scan fails. Use a format string guarded by `ResourceLoader.exists`, or land it with the file.
- A **Dash-only** target must sit *below* its take-off (64 px worked), and its negative test must sweep every air-dodge frame and late (coyote) take-offs. A gap at one height can't separate a dash-jump from a dodge-jump plus a late air dodge (D-094, K-48).
- A Needle on a ledge above a walkway needs `needle_ledge.tres` (aggro 160) or it lunges off (D-097).

**RouteBot pitfalls** (K-57):
- A `runjump` right after a `jump` landing can fire on the spot: the landing leaves a small backward drift, and the keep-speed check reads it as already at the edge. Put a short `run` step (or a `wait`) first.
- `["shoot", n, "diag"]` holds `move_x` toward the facing, so a multi-shot diagonal volley walks forward and drifts off the line. Use single diagonal shots, each after a `run` that sets the facing.
- A `jump` target must be *on* the platform, not in a gap before it: the steer stops a few px short (Collector Bay's catwalks needed 210/360, not 190/330).
- An interact needs Rook's 12 px body to overlap the use area; stop inside it, not beside it.
- New M7 steps: `["shoot", n, aim]`, `["dodge", x]`, `["dodgejump_airdodge", edge, x, delay_frames]`.

## Story content (M8)
Everything below is data. All story state is flags, bool or int only (D-116); nothing adds a `GameState` key. Run the full gate after any story change; `ValidateContent` lints every rule named here.

**Flag names** (one namespace): `seen_seq_<id>`, `<boss>_intro_seen`, `act1_complete`, `ending_seen_<id>`, `mem_seen_<scene>`, `mem_detail_<scene>`, `memories_remembered` (int), `arc_<npc>_<stage>`, `arc_<npc>_stage` (int), `arcbeat_<npc>_<stage>`, `bond_<npc>_<fact>`, `thread_<npc>_<name>`, `orr_air_named` / `orr_air_ghost`. Bookkeeping prefixes (`seen_seq_`, `mem_seen_`, `mem_detail_`, `ending_seen_`, …) are never reported as unread.

**Conditions** (`Game.check_condition`): `flag:x`, `ability:x`, `collected:x`, `atleast:flag:n`, `count:<metric>:<n>` (metrics `fragments`, `shards`, `circuits`, `secrets`) and `!` in front of any of them. There is no AND/OR: AND is a list or a nested switch, OR is per caller (D-119).

### A scripted sequence
1. Create `data/sequences/<id>.tres` (`SequenceData`): `id`, `room` (needed for actor lookups), `steps`, `seen_flag` (defaults to `seen_seq_<id>`), `lock_input`, `repeat_locks_input`, `hide_hud`, `letterbox`, `budget_seconds`, `repeat_budget_seconds`, `theatre_only`. Steps live in `cinematics/steps/`: `SeqLine` (speaker from `data/sequences/speakers.tres`, "" = narration), `SeqWait`, `SeqFade`, `SeqLetterbox`, `SeqCamera`, `SeqActorMove`/`Face`/`Flash`, `SeqRookPose`, `SeqShake`, `SeqSfx`, `SeqMusic`, `SeqFlag`, `SeqMark`, `SeqTitleCard`, `SeqCredits`.
2. Play it from a room with `sequence_trigger(...)` (`play_when` conditions, `autoplay`, `require_spawn`, `once`), a `BossArena.intro_sequence`, or an `ActData.close_sequence`. A player-reachable sequence that nothing plays is a warning.
3. Rules the linter enforces:
   - the first view fits `budget_seconds` and the repeat view `repeat_budget_seconds`; a line costs 1.0 s + 0.065 s per character, clamped to 2–7 s, at subtitle speed Normal (`CinematicConfig.line_seconds`; every scene timing lives in `data/cinematics/cinematic_config.tres`);
   - only `SeqFlag` sets flags, and `only_when` never reads a flag a later step sets;
   - actors are `@` ids (`@boss`, `@arena` need a BossArena room) or `Interactables/NPC_<id>` where `<id>` is an NPC profile; **never Rook** (Act I sequences never move him, D-109);
   - a non-locking sequence (barks, repeat boss intros) cannot use camera, pose, letterbox or fade;
   - a `CROUCH` pose needs a later `STAND`; `hold_for_input` is for theatre-only sequences.
4. Every step implements `run()` and `finish()`: a skip or INSTANT calls the remaining `finish()`s, so `finish()` must leave the same end state as a full play. An abort calls no `finish()` and only restores (D-106).
5. Test it in AUTO (`StoryTestKit` / `CinematicMode.set_mode(AUTO)`), check skip parity, and look at it in the dev console's sequence theatre and `CaptureTour --tour=story`.

### A memory scene
1. A fragment's vignette: `data/memories/<fragment_id>.tres` (`MemorySceneData`, `source = FRAGMENT`, `fragment` = the `data/lore` resource, same id). A memory not tied to a pickup: `source = SURFACED` with a `title` and an `unlock_condition`.
2. Fill `timeline_slot` (spaced by 100; 0 = undated), `tableau_width`, `start_view_x`, `shapes` (`MemoryShape`, tone 0..2; `redacted` shapes are the only Core red, D-115), 3–6 `beats` (`MemoryBeat`: UPPERCASE speaker ≤ 16 chars, short text, `view_x`, `burn`, `min_seconds` 0.2–2.0) and optionally one hidden detail (`detail_text`, `detail_x`, `detail_from_beat`, 0-based). The validator rejects a detail the start view or a beat's auto-pan already reveals, or one out of reach.
3. Vignettes play at Anchors (at most `MemoryConfig.max_per_rest` per rest) and from the journal gallery, never on pickup (D-112). Every player-facing string of the player and gallery lives in `data/memories/memory_config.tres`.

### An NPC arc stage or reaction
1. Arcs live in `data/arcs/arc_<npc>.tres` (`NpcArc`): an ordered `stages` spine and unordered `reactions`, each an `NpcArcStage` (`id`, `enter_all`, `enter_any`, `min_stage` for reactions, `set_flags`, `beat_rules`, `idle_rules`, `journal_note`, `optional`).
2. Beats play once: each beat sets its `arcbeat_<npc>_<stage>` flag and the beat rules end with an unconditional rule. Idles set nothing and offer no choice. Reactions carry no idles or journal note. Arc dialogue gives nothing (no `give_*`, D-122).
3. Pick order for the NPC: story rules > pending beat > stage idle > fallback (D-117). A pending beat shows the neutral tick over the NPC (D-120); a bodiless NPC opts in with `NpcProfile.cue_new_lines`.
4. Arcs set no world flags. The world reacts through switches keyed on `arc_<npc>_<stage>` or thread flags.
5. A choice is a `DialogueChoice` list on a beat's dialogue: choice flags must be disjoint, and automation always picks choice 0.

### A world-state switch, an NPC post or a map note
- **Switch:** `switch("Name", "condition")` in the room script, then its visual children (decor, neon) with `parent=`. Visual only: no collision, rewards, enemies or interactables under it (linted). Pair exclusive states as `!flag:x` / `flag:x`. Add the row to `DISTRICTS.md` "World state".
- **NPC post:** a second `npc(profile, …, name="NPC_<id>_<post>")` with a `present_when` exclusive to the primary's. Sequences may target only the primary `NPC_<id>`. The map pin follows the present post.
- **Map note:** `mapmarker(x, y, "Who: what", resolved_when, kind=2, shown_when="…")`. Only in rooms the map knows, never within 96 px of a secret (§20), and the one note mechanism for rumours and arcs (D-124). Keep the label short; the knowledge lint reads it.

### An ending, an act or a future flag
- **Ending:** `data/endings/<id>.tres` (`EndingData`: `id`, `title`, `tagline`, `priority`, `hidden`, `choice_condition`, `requires`, `requires_memories`, `requires_arcs`, `sequence`). The sequence is `theatre_only`, ends with `SeqCredits` as its last blocking step and sets `ending_seen_<id>`. `EndingResolver` is pure; `EndingDirector` plays it (the dev Ending theatre runs in a `FlagSandbox`, D-128).
- **Act:** `data/story/act<n>.tres` (`ActData`: `act`, `name`, `complete_flag`, `close_sequence`, `standing` lines, `max_standing`). The Act I card shows the fallback line plus at most `max_standing - 1` passing lines (D-131).
- **Future flag:** declare it in `data/story/future_flags.tres` (`FutureFlag`: `flag`, `act`, `note`). A future flag counts as produced; only `data/endings` may read it, and a real producer is an error until the entry is removed when its act lands (D-127).

### The knowledge lint (D-132)
`data/story/knowledge_lint.tres` lists terms Act I text must not use (Project REDLINE, Architect, The Null, neural, harvest, Redline disaster, conscious, "Pulse is", "stores memor", "made of memor", research, Rook). `ValidateContent` warns on any hit in text a player can see in Act I: dialogue and choices, fragments, memory text, sequence lines (theatre-only sequences exempt), standing lines, map-marker labels (notes included), arc journal notes, NPC names and speaker labels, and the gallery strings. `data/endings` is exempt, so review ending text by hand (D-137). Today the one expected warning is `data/npcs/orr.tres` "Rook" (D-109).

### Tools
- **Dev console "Story…"** pages: Sequence theatre (view full / repeat / auto), Memory theatre, Story state (the presets), Arcs (force the next spine stage), Ending theatre, Replay boss intro (full), the sequence inspector toggle and a toggle that lists the `test_*` fixture sequences. Everything goes through `DevActions` (`preview_sequence`, `play_sequence`, `play_ending`, `satisfy_ending`, `force_arc_stage`, `replay_act1_close`, …).
- **Story presets** (`data/dev/story_presets.tres`, `StoryPresets.apply(id)`): fresh, collector_down, relay_met, repeaters_2, dead_air_done, grid_rerouted, charted, krail_down, act1_complete. Each holds its full cumulative flag list.
- **`StoryTestKit`** (tests): sandbox, presets, the Act I max state, AUTO/INSTANT plays, skip and the restore contract.
- **`SequenceInspector`** and the DebugOverlay ACT/SEQ lines show the running step, skip reasons and the hold bar.
- **Placeholder sfx** added for M8: `radio_static`, `memory_open`, `memory_beat`, `memory_tear`, `memory_detail` (every placeholder sfx stays under 1.0 s, `test_feedback`).

## Endgame content (M9)
Every M9 area is data plus a validator rule module in `devtools/content/rules/` (PL achievements/stats, CH challenges, NU the Deep Rig, RM remix, SE settings, AC accessibility, L strings, DM the demo, EX export presets, X cross-area). Rule findings are prefixed with their id (`[CH-7] ...`); tests match on it.

### Adding an achievement
1. `data/achievements/<id>.tres` (`AchievementData`): `id` = file name, `title` (≤ 32), `description` (≤ 90), `category`, a unique `sort`, `act`, `conditions` (the `Game.check_condition` grammar; every entry must hold) and/or `stat_id` + `stat_target` from `data/platform/stats.tres`.
2. Rules (PL-5..PL-10, PL-15): unique ids/sorts/api names; counters ≤ the grind cap 25 (D-146); completion targets equal the live SliceStats totals; no future flags; **never a Settings property** (D-144, an assist player earns everything); a `reveal_when` spoiler guard for any row naming a boss, NPC, quest or set piece.
3. If the Undercity can earn it, list it in `data/release/demo.tres` `achievements` (DM-4 warns when an earnable one is missing and errors on an unearnable one).
4. Run `ExtractStrings --write` (new text), `ValidateContent`, `--filter=achievements`.

### Adding a challenge (and when to bump its revision)
1. `data/challenges/<prefix>_<id>.tres` (`ChallengeData`; prefixes `br_` rematch, `tt_` time trial, `mo_` movement-only, `nh_` no-hit, `pit_`, `null_`), a kit in `data/challenges/kits/` (or `use_profile_loadout`), `unlock_when`, `reveal_when`, `medal_thresholds` (D-150 ratios from the rig ghost) and `dev_bot` / `dev_route` if a bot can finish it.
2. Bake the rig ghost: `godot --headless --fixed-fps 60 res://devtools/GhostBake.tscn -- --challenge=<id>`; it prints the medal suggestion. `--check` must stay clean.
3. **Any change that makes old times incomparable** (the room, the kit, the rules, the start or end) bumps `revision`: old records archive, and the ghost must be re-baked.
4. ChallengeRules CH-1..CH-15 check rooms, entries, exits, kits vs capacity, medal order and floors, ghost headers and waves. Runs are sandboxed: they go through `Challenges`, and code must **never write `Game.state` in a run** (it is the sandbox; the profile is `Game.held_profile`).

### Remix a room (NG+)
Remix ops are data (`data/remix/<room>.tres`, `RoomRemix` + `RemixOp` SET/SWAP/ADD/HAZARD), generated by `tools/roomgen/remix_act1.py` (`--check` for drift) and applied by `RemixLibrary` before the room's `_ready` when `ng_remix` holds. Rules RM-1..RM-8: ops resolve node names, remix enemies have `scrap_drop = 0` (a SET/SWAP keeps the base drop, ADD pays nothing, R09.11), boss HP within +10 %, telegraph floors hold. Run `--filter=economy` (`EconomyAudit.compute(true)`, `ECONOMY.md`) and the NG+ suites: `--filter=ng_plus`, `--filter=ngplus` and `--filter=room_remix` (the filter is a substring of `file::method`).

### Deep Rig and challenge rooms
Challenge-only rooms live in `world/rooms/challenge/` (off the map, no Scrap, no secrets, `DISTRICTS.md` theses), one generator each (`tools/roomgen/null_<room>.py`, `ch_<room>.py`). Every RoomExit is off in a run; stages advance on a `ChallengeGoal`. NU-1..NU-6 lint them. Player text says "Deep Rig", never "The Null" (knowledge lint, D-154). Route tests: `test_null_routes.gd`, `test_pulse_pit.gd`.

### Adding a setting
One `SettingDef` row in a page of `data/settings/pages/` (key, section, kind, choices/steps, default, label, description) plus the property with a clamped setter in `autoload/Settings.gd`; the menu builds itself. SE-1..SE-6 check the catalog against the properties, clamps and wording (no shaming words, §24). An accessibility option never gates content or achievements; if it makes runs faster it becomes a neutral tag (D-149). New rebindable actions go into `data/input/rebind_catalog.tres`.

### Text and localization
Player text is English source in data and code; it is translated **at the edge**: `Loc.t`, `Loc.f` (named `{placeholders}`) and `Loc.tn` where it is drawn (D-162). A Resource or Node script with player text declares `const LOC_FIELDS` (field → max chars) and `LOC_EXEMPT`. After changing player text run `godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write`, then `-- --check` before committing (StringRules L-1..L-9 are errors). Logic never compares display strings. Check layouts in `en_XA` (dev console → Endgame & build → Locale). Details: `LOCALIZATION.md`.

### Builds and the demo
The demo is `data/release/demo.tres` (allowed room dirs, end mode, disabled features, the end card text, the achievement list); a room outside it gets a `DemoBarrier` at every border exit. DM-1..DM-8 lint it. Builds come from the checked-in `export_presets.cfg` through `tools/build/build.py` (`--check`, `--smoke`, `PLAYTEST_KIT.md` §2); a new data folder read at runtime must go through `DataDir` (X-5) and, for new file types, the presets' `include_filter`.

## Enemies
Enemies are data (bible §32, "composable modules"). An `EnemyData` holds a `brain` (`EnemyBrain`) assembled from modules in `enemies/modules/`:

| Slot | Modules |
|---|---|
| Movement (one) | `MoveApproach` (keep/retreat distance), `MoveHold`, `MoveHover`, `MoveSlowTurn` |
| Attack rules (ordered, first match wins) | `AttackRule`: range band, height difference, line of sight, on floor, target in front, face on start |
| Guard (optional) | `GuardFrontal` |
| Looks (any number) | `LookSpringLegs`, `LookEye`, `LookRotor`, `LookShieldPlate` |

**A new enemy** is:
1. An `EnemyData` (`.tres`) with its attacks.
2. A brain (`data/enemies/brains/<id>.tres`).
3. A copy of a variant scene with its `data` swapped.

**Example:** the Signal Drone (`data/enemies/signal_drone.tres`) was made that way and is tested. Write code only for a genuinely new module; keep it stateless and store per-enemy state with `ModularBehavior.mem()` and `remember()`. Bosses can keep bespoke scripts (Warden Krail).

## Art
The rules are in `Docs/ART_BIBLE.md`. Mechanically:
1. Export to `assets/<district or character>/<subject>_<action>[_variant].png`: horizontal strips, fixed cell, crisp alpha.
2. Create a `SpriteSheetSpec` (`.tres`): `texture_path`, `cell_size`, `origin` (the feet, bottom-centre) and `SpriteAnim`s. The animation names are the ones the visuals ask for:
   - **Enemies:** `idle`, `move`, `windup`, `attack`, `hurt`, `death`.
   - **Rook:** the state ids (`idle`, `run`, `slide`, `crouch`, `dodge`, `dash`, `hurt`, `heal`), plus `jump_rise` and `jump_fall`, plus attack ids or `attack`.
   
   Missing animations fall back (for example `windup` → `attack` → `idle`).
3. Point `EnemyData.sprite`, or the player visual's `sprite`, at the spec. The placeholder is replaced; telegraphs, health bars, afterimages and blinks stay.
4. Validate. `ArtValidator` checks:
   - snake_case names;
   - alpha only 0 or 255 (atmosphere textures under `assets/vfx/atmos/` may use up to 4 more levels, D-173);
   - sheet size is a multiple of the cell;
   - animations fit inside the sheet;
   - palette size (a warning above 64 colours);
   - reserved gameplay colours outside `ui/` and `vfx/`;
   - the project's nearest filtering.

## Art & audio assets (presentation overhaul)
Everything the game draws or plays from a file lives under `assets/`. Everything that made it lives in `art/source/` (raw sources, never imported) and `tools/assetgen/` (scripts). Rules: `ART_BIBLE.md` §4, §8–§11. Report and swap guide: `OVERHAUL_REPORT.md`.

### Commands (from `redline/`, no network, no generator calls)
```bash
python3 -B tools/assetgen/assetgen.py --check          # everything below, exit 1 on any problem (--quick skips the rebuild)
python3 -B tools/assetgen/build_chars.py [--check]     # character sheets: Rook, enemies, bosses, NPCs, portraits, weapons (pixel rigs)
python3 -B tools/assetgen/fx_vfx.py                    # VFX grey-mask sheets + .json sidecars
python3 -B tools/assetgen/fx_ui.py                     # UI kit (X.png + X_fill.png + regions .json), title logo
python3 -B tools/assetgen/tiles_null.py                # Deep Rig tiles
python3 -B tools/assetgen/paint_env.py [<id>…] [--check] [--review /abs/dir]   # code-painted planes, tilesets, fg sets, critters
python3 -B tools/assetgen/env_process.py <id> | --all | --check   # process a raw generator image in art/source/raw/ into its plane
python3 -B tools/assetgen/process_sfx.py --check       # SFX / UI / footstep loudness metadata (-18 LUFS)
python3 -B tools/assetgen/process_music_amb.py --check # music (-20) and ambience (-26) loops, seam metrics
python3 -B tools/assetgen/importflags.py --check|--write   # loop=true, loop_offset=0 in every loop's .import
godot --headless --import                              # after adding files: Godot writes the .import (then run importflags --write)
godot --headless res://devtools/content/ValidateContent.tscn   # ArtValidator on every PNG
godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn -- --budget   # per backdrop kind CPU budget and ambient/VFX caps
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir --tour=overhaul   # review frames
```
The import loop: write the file → `godot --headless --import` → `importflags.py --write` (loops only) → commit the file and its `.import` → `assetgen.py --check` + `ValidateContent`.

### Provenance
Every PNG and OGG under `assets/` is named in an `out_files` cell of `assets/SOURCES.csv` (`;`-separated, res-relative). Columns: `id,kind,tool,model,prompt,credits,raw_file,out_files,notes,rights`. `rights` is "own work (code), no AI output", "ElevenLabs output, check plan terms" (D-170) or "n/a (failed call…)". A new generator asset adds a row with its credits and prompt, and keeps the raw source in `art/source/` (compressed PNG, or the final trimmed OGG only).

### The data the runtime reads
| Data | Class | What it holds |
|---|---|---|
| `assets/**/<id>_sheet.tres` | `SpriteSheetSpec` | cell, origin, `SpriteAnim`s (per-anim origin), `metadata/mask_path` for tint masks. Point `EnemyData.sprite`, `NpcProfile.sprite` or the player visual's `sprite` at it |
| `data/vfx/vfx_library.tres` | `VfxLibrary` | VFX id → spec path, `palette_key` or colour, additive, live cap. `VfxOneShot.spawn(parent, id, row, pos, opts)` plays one |
| `data/presentation/backdrops/<kind>.tres` | `BackdropSet` of `PlaneSpec`s | planes back to front (texture, B variant, motion, anchor), fog, shafts, grade, vignette, glows, particles, life |
| `data/presentation/rooms.tres` | `PresentationIndex` → `RoomPresentation` | per room scene path (and per district default): backdrop kind, ambience bed, reverb, footstep surface, music district, foreground allowed |
| `data/districts/<d>.tres` | `DistrictTheme` (Presentation group) | `backdrop_kind_default`, tileset + layout json, dust colour |
| `data/audio/placeholder_sfx.tres` | `SfxDefinition`s | synth parameters (the fallback) + `override_stream`, priority, mix |
| `data/audio/music/music_library.tres` | `MusicLibrary` of `MusicSet`s | per music district: title/hub/explore/flow/boss/memory/aftermath track paths, `boss_by_room`, hub `extras` |
| `data/audio/ambience/beds.tres` | `AmbienceBank` | bed id → OGG path (or "" = silence) and mix dB; the drip emitter |

Paths to optional assets are Strings guarded by `ResourceLoader.exists` (web and demo builds leave some out, D-180), never preloads. A missing asset falls back: plane → procedural skyline, sheet → placeholder drawing, SFX → SfxSynth, track → synth stems, bed → silence.

### How a new district plugs in (the Ironworks hook)
It needs no new code. Add five pieces of data, plus one id in each of the const id lists named below (the validators reject unknown ids):
1. **Theme:** `data/districts/ironworks.tres` with a palette (Art Bible §3), `backdrop_kind_default`, a tileset (paint it or process a generated one) and `dust_color`.
2. **Backdrop set:** add the kind id to `PresentationIndex.BACKDROP_KINDS`, then write `data/presentation/backdrops/<kind>.tres`. Its planes come from a `paint_env.py` item or an `env_process.py` recipe, and each plane needs a `SOURCES.csv` row.
3. **Presentation rows:** a `districts["Ironworks"]` default in `rooms.tres`, plus a row for any room that differs. `OverhaulTour.KIND_ROOMS` gets one room per new kind (`test_capture_overhaul` fails until it does).
4. **Music set:** a `MusicSet` with `district = &"ironworks"` in `music_library.tres`, and the id added to `PresentationIndex.MUSIC_DISTRICTS`. Any empty slot falls back to the default set, then to the stems.
5. **Beds:** a bed id in `PresentationIndex.BED_IDS` with a path in `beds.tres`. Leave the path empty for silence until the asset exists.

Then run `assetgen.py --check`, `ValidateContent`, `PerfProbe -- --budget` (add the kind's heaviest room to `BUDGET_ROOMS`) and `--tour=overhaul`.

## Dev console (debug builds, backquote key)
- Teleport to any room entry.
- Story pages (M8, see above).
- Spawn any enemy.
- Quick boss restart.
- Unlock-all profile.
- Save-state inspector (save now, copy JSON).
- Hitbox view.
- Performance graph.
- **Endgame & build…** (M9): Achievements, Challenges, The Null, NG+, Accessibility, Locale and Demo & build pages, and "Endgame state: Act I complete".

The logic lives in `devtools/DevActions.gd`, which scripts and tests can call too.
