# REDLINE presentation overhaul report

**Scope.** The user asked for a presentation pass: "redo the whole thing, add life, add effects, add cool things, add more animations, look at Hollow Knight". The frame was pixel art inside the Art Bible, in a Hollow Knight mood, with assets from AI generators. A later message added: "Use pika for the assets and add levels and power effect and all you need and upgrades and everything".

This phase changes presentation only: art, animation, VFX, atmosphere, UI and audio. Gameplay numbers, collisions, room geometry, RouteBot routes, the economy and save keys are unchanged. Every placeholder system is kept as the fallback. Decisions: D-170..D-180 (`DECISIONS.md`). Open issues: K-OV-1..K-OV-12 (`KNOWN_ISSUES.md`). Next steps: `TODO.md`, "Presentation overhaul".

**What did not happen:**
- **Pika** is not connected to this environment, so no Pika asset exists.
- **The generator accounts ran out.** ElevenLabs hit its free-plan quota, and its daily image limit blocked all but 2 images. Higgsfield has 0 credits. The user then chose to continue with code-drawn pixel art, so this phase made **0 generation calls**.
- **Levels and upgrades were not built.** New levels (the Ironworks district, more Act I rooms) and upgrade gameplay are later phases, not started (`redline/CLAUDE.md` and bible §44 forbid new districts before the playtest unless the user asks for one specifically). This phase leaves the hooks those phases need: `PowerFlourish` on circuit, weapon and ability grants, `CoreAura` in Flow, and a data path for a new district (`CONTENT_PIPELINE.md`, "How a new district plugs in").

**What is code-drawn and what is AI:**
- **AI generator output:** the audio (6 music tracks, ambience beds, SFX/UI/footstep takes) and exactly two images, `title_sky` and `uc_far`.
- **Code-drawn** (Python pixel rigs and painters in `tools/assetgen/`, own work): everything else you see. That covers Rook, the enemies, the bosses, the NPCs, the portraits, the VFX, the UI kit, the tiles and every other backdrop plane.
- **Reviewed so far:** nobody has listened to the audio (§7). The art has been reviewed only through composites and these capture frames.

## 1. What changed, per area

| Area | Before (M9, b578c35) | After | Tasks |
|---|---|---|---|
| Backdrops | a screen-space gradient sky, two procedural skylines, rain | 14 `BackdropSet`s. Each has painted 480 px A/B planes (sky, far, mid, near, backwall, foreground), two fog bands, light shafts, lamp/neon glows, a vignette, a background-only district grade, ambient particles (mote, spore, ash, drip) and ambient life (moths, rats, gulls, eels, drips, steam, a train), plus swaying cables, banners and cloth. The layered title backdrop shows Rook on the ledge. The skyline is the fallback. | T02, T03 |
| Tiles | flat `GrayboxBlock` fills | district tilesets drawn by `GrayboxBlock` (Undercity, Lowlight, Relay, Deep Rig). Collision is unchanged. | T02, T03 |
| Rook | `PlayerPlaceholderVisual` rectangles | a 48×48 sheet, 37 anims and 197 frames. Every state and attack is mapped, with new hooks (turn, land, hard land, idle fidget, death, interact, rest, per-weapon shots), the visor and seam mask tint, and live-frame afterimages | T04 |
| Enemies, bosses, NPCs | coloured bodies with `Look*` modules | sheets for 7 enemies, the Collector Drone, Warden Krail, the Sweeper, the Collector Eye and 5 NPCs. They add hit reactions, death corpses, boss attack families and phase poses, NPC idle/talk/signature animations and per-line dialogue portraits | T05, T07 |
| Combat juice | `HitSpark`/`DustBurst`/`SlashArc` particles | sprite hit sparks and slash smears built from the real hitboxes, death bursts, dust and splash, muzzle flashes, projectile heads, shockwaves, electric arcs, heal and anchor-rest blooms, the perfect-dodge flourish, Pulse motes, the Core aura in Flow, and **power flourishes** on circuit, weapon and ability grants | T06 |
| UI | plain panels and bars | a UI kit: HUD ampoule pips (break/refill), the Core frame and flow fill, the boss bar with phase ticks, 9-slice menu and dialogue frames, the ember cursor, nameplates, map icons, style-rank glyphs, and the title logo with the ember crack | T07 |
| SFX | SfxSynth renders only | assets through `override_stream`, with the synth as the fallback. Randomized takes, new ids, 16 voices with priority stealing and footsteps per surface. UI sounds go on the UI bus. | T08 |
| Ambience | none | beds per room on an Ambience bus, plus a drip emitter. Rooms without a bed are silent. | T08 |
| Music | 5 synth stems faded by state | full tracks per district and state on two crossfading decks. Stems play for MEMORY, SILENT, Relay explore, the Deep Rig and any left-out file (D-171). | T08 |
| Accessibility | M9 settings | `ambient_motion` Full/Reduced/Off (D-174). Background dim covers every new plane. Flash reduction scales VFX highlights. High contrast drops the vignette. Colour-blind palettes retint the masks. | T01, T03, T06 |
| Tools | none | `tools/assetgen/` (`assetgen.py --check`), `PerfProbe -- --budget`, `--tour=overhaul` | T01, T09, T10 |

## 2. How the frames were made

- **Before** frames: every capture tour at the M9 gate tree `b578c35` (T01, before any file changed), xvfb + opengl3 (llvmpipe) at 1440×810.
- **After** frames: the same tours on this tree, plus the new `--tour=overhaul`. Every tour exits 0: movement 7, combat 5, slice 34, undercity 17, ui 13, story 51, endgame 51 and overhaul 37 shots.
- **`--tour=overhaul`** (`devtools/capture/OverhaulTour.gd`) runs in a TourSandbox with INSTANT cinematics. It exits 1 on a missing shot. It shoots:
  - one frame per backdrop kind (title plus 13 room kinds);
  - a light hit with sparks and a smear, and a death burst;
  - the Collector and Krail right after their phase-2 switch;
  - the HUD at 100 % and 150 %, a dialogue with its portrait, and the pause menu;
  - the Flooded Alley, Wake and the hit frame again under each accessibility variant (`ov_v_<flash|contrast|protan|dim|still>_*`).
- `test_capture_overhaul` checks that the list covers every kind in `data/presentation/rooms.tres`.
- `Docs/media/overhaul/` keeps a curated set of 20 pairs (40 PNGs, full 1440×810). Every other frame can be re-made with the commands in §9.

## 3. Before / after

| Room / screen | Before | After |
|---|---|---|
| Title | ![](media/overhaul/title_before.png) | ![](media/overhaul/title_after.png) |
| Wake (uc_ward) | ![](media/overhaul/wake_before.png) | ![](media/overhaul/wake_after.png) |
| First Pursuit (uc_pursuit) | ![](media/overhaul/first_pursuit_before.png) | ![](media/overhaul/first_pursuit_after.png) |
| Maintenance Shaft (uc_shaft) | ![](media/overhaul/maintenance_shaft_before.png) | ![](media/overhaul/maintenance_shaft_after.png) |
| Escape Tunnel (uc_tunnel) | ![](media/overhaul/escape_tunnel_before.png) | ![](media/overhaul/escape_tunnel_after.png) |
| Collector Bay (uc_boss_bay) | ![](media/overhaul/collector_bay_before.png) | ![](media/overhaul/collector_bay_after.png) |
| Collector fight | ![](media/overhaul/collector_fight_before.png) | ![](media/overhaul/collector_fight_after.png) |
| Flooded Alley (ll_street) | ![](media/overhaul/flooded_alley_before.png) | ![](media/overhaul/flooded_alley_after.png) |
| Smuggler Route (ll_canal) | ![](media/overhaul/smuggler_route_before.png) | ![](media/overhaul/smuggler_route_after.png) |
| Apartment Stack (ll_interior) | ![](media/overhaul/apartment_stack_before.png) | ![](media/overhaul/apartment_stack_after.png) |
| Neon Roofs (ll_roof) | ![](media/overhaul/neon_roofs_before.png) | ![](media/overhaul/neon_roofs_after.png) |
| Bell Tower (ll_tower) | ![](media/overhaul/bell_tower_before.png) | ![](media/overhaul/bell_tower_after.png) |
| Warden Krail fight | ![](media/overhaul/krail_fight_before.png) | ![](media/overhaul/krail_fight_after.png) |
| The Relay (relay_hub) | ![](media/overhaul/relay_before.png) | ![](media/overhaul/relay_after.png) |
| Deep Rig stratum (null_rig) | ![](media/overhaul/deep_rig_before.png) | ![](media/overhaul/deep_rig_after.png) |
| Pulse Pit (pulse_pit) | ![](media/overhaul/pulse_pit_before.png) | ![](media/overhaul/pulse_pit_after.png) |
| Dialogue | ![](media/overhaul/dialogue_before.png) | ![](media/overhaul/dialogue_after.png) |
| HUD at 150 % | ![](media/overhaul/hud_150_before.png) | ![](media/overhaul/hud_150_after.png) |
| Movement Lab dodge (Rook + afterimages) | ![](media/overhaul/movement_dodge_before.png) | ![](media/overhaul/movement_dodge_after.png) |
| Combat Lab needle telegraph | ![](media/overhaul/combat_needle_before.png) | ![](media/overhaul/combat_needle_after.png) |

The source frames, in the same order: `u01_title`, `uc_Wake_start`, `uc_FirstPursuit_from_lift`, `uc_MaintenanceShaft_from_medical`, `uc_EscapeTunnel_from_bay`, `uc_CollectorBay_from_lift`, `uc_collector_fight`, `s_FloodedAlley_from_relay`, `s_SmugglerRoute_smuggler_den`, `s_ApartmentStack_stack_mid`, `s_NeonRoofs_from_stack`, `s_BellTower_bell_top`, `s_boss_fight`, `s_Relay_start`, `eg_c_09_stratum_setpiece`, `eg_c_07_pulse_pit_hud`, `u02_dialogue`, `eg_s_09_hud_150`, `04_dodge_afterimages` and `c03_needle_telegraph`. The labs stay graybox by design (no presentation row), so only the characters change there.

**Expected diffs.** Every frame of every older tour changes, because the backdrops, sprites, HUD and fonts on frames all moved. No tour lost a shot. Timing-based shots, such as a boss mid-fight at a fixed frame count, show the same moment with the new animation, so poses differ.

## 4. Performance and web size (T09)

Headless CPU, the PerfProbe fight script, mean ms over 600 frames (`PerfProbe -- --budget`). The windowed ratio is xvfb at 1920×1080 on llvmpipe, 300 frames, this tree against b578c35. Software GL numbers mean nothing alone, so only the ratio counts.

| Room (kind) | Before | After | p95 after | Windowed ratio |
|---|---|---|---|---|
| Wake (uc_ward) | 0.75 | 1.07 | 2.06 | 1.00× |
| Collector Bay (uc_boss_bay) | 0.81 | 1.32 | 2.52 | 1.04× |
| First Pursuit (uc_pursuit) | 0.81 | 1.46 | 2.70 | |
| Escape Tunnel (uc_tunnel) | 0.86 | 1.42 | 2.59 | |
| Maintenance Shaft (uc_shaft) | 0.89 | 1.46 | 2.61 | |
| Flooded Alley (ll_street) | 1.13 | 1.50 | 2.93 | 1.06× |
| Smuggler Route (ll_canal) | 1.05 | 1.58 | 2.82 | |
| Neon Roofs (ll_roof) | 1.11 | 1.61 | 2.71 | 1.10× |
| Apartment Stack (ll_interior) | 1.13 | 1.58 | 2.76 | 1.06× |
| Bell Tower (ll_tower) | 1.23 | 1.72 | 3.13 | 1.06× |
| Relay (relay_hub) | 0.65 | 1.21 | 2.33 | 1.04× |
| Null Floor (null_rig) | 0.71 | 1.25 | 2.30 | 1.04× |
| Pulse Pit (pulse_pit) | 0.88 | 1.15 | 2.19 | 1.07× |
| Combat Lab (graybox) | 0.88 | 1.50 | 2.89 | 0.99× |

- Every room is within its budget: mean ≤ max(before × 1.15, 4 ms) and p95 ≤ 8 ms. Every ambient-life, particle and VFX cap held at every sample.
- At most 2 translucent full-screen layers are drawn in any room.
- GPU cost on real hardware is unmeasured (K-OV-11).

| Size | Before (b578c35) | After |
|---|---|---|
| Tracked `redline/` (git ls-files, bytes) | 8,209,300 | about 20.9 MB before the frames in `Docs/media/overhaul/` (about +2.6 MB with them); assets 9.0 MB, `art/source` 3.3 MB, `tools/assetgen` 0.9 MB |
| Web full gz payload (wasm + pck + js) | 9.6 MB zip | 13.55 MB with a partial audio set (4 music tracks left out). **Over the 12 MiB budget** (D-180 proposes about 20 MB) |
| Web demo gz payload | – | 12.56 MB (within 12 MiB; the Lowlight/Relay-only beds and art are left out too) |
| Desktop zips | 31.7 MB win / 53.4 MB macOS (measured before phase B) | not re-measured in T10; desktop presets ship the full audio set; budgets 40 MB / 60 MB (build.py) |

## 5. Asset provenance summary

`assets/SOURCES.csv` has 192 rows, and every PNG and OGG under `assets/` is listed in an `out_files` cell (`assetgen.py --check` step 6).

| Kind | Rows | Credits | Source |
|---|---|---|---|
| music (6 tracks + the T01 re-encode row) | 7 | 7,200 | ElevenLabs `eleven_music_v2` |
| ambience beds and drips | 15 | 1,580 | ElevenLabs `eleven_text_to_sound_v2` |
| SFX, UI, footsteps | 67 | 641 | ElevenLabs `eleven_text_to_sound_v2` (and 0-credit derived takes) |
| images | 77 | 369.2 | 2 `gpt-image-2` images (`title_sky`, `uc_far`); every other image row is code-drawn (T02 painters, UI/props) or a failed call |
| sprite sheets, tiles | 26 | 0 | code pixel rigs |
| **total** | **192** | **9,790.2** | of the 60,000 budget; the account quota (10,000) is exhausted |

- `rights`: 95 rows are "own work (code), no AI output", 75 are "ElevenLabs output, check plan terms" and 22 are failed calls ("n/a").
- **Rights caveat (D-170, K-OV-9):** every generator row comes from a **free** ElevenLabs plan. Its commercial terms must be checked before any public build. No asset from Pika or Higgsfield exists.
- The phase-A CSV fix (the `burnout`, `enemy_die` and `boss_slam` rows pointing at `boss_defeat.ogg`) is applied: each row lists its own OGG.

## 6. Weak or missing, still open (phase-A notes §3)

**Environments:**
- 41 of 44 planned generator env items were never generated.
- They are now code-painted, so every kind has planes, but the depth is an approximation (K-OV-8).
- The queue is ready: `tools/assetgen/env_queue.json`, about 8.9k credits.

**Art:**
- `title_logo` is a plain wordmark (K-OV-5).
- The portraits are simple busts.
- The katar and small gun stamps read small.
- Krail is dark on slate even with the baked cold rim (K-OV-7).
- Rook's coat hem is at the 18 px low end.
- The dialogue cable flourish and the style-rank glyphs are modest.
- The heal crosses are small.
- `uc_far` is slightly busy for a far plane.
- `title_sky` is very dark.
- Lowlight's green neon is unchanged (F2, D-176, K-OV-6).
- Fixed in this phase: dust `run_puff` frame 2 (T06), the shockwave ground wave, now a 2-tone crest (T06), and Krail's rim light (T05).

**Audio:**
- `shoot_pistol` is held and uses the synth.
- `player_hurt` is too bright and too close to `hit`.
- `perfect_dodge` is an interim take.
- `hit` is a single thin take.
- `enemy_telegraph` is a whine.
- `boss_roar` is flat, and `quest_complete` is not a motif.
- The derived stand-ins are `ui_back`, `boss_defeat`, `memory_open` and `footstep_concrete`.
- The loops are short (`mus_boss` 42.9 s, `mus_flow` 48.75 s) and jump in RMS at the loop point (K-OV-2, K-OV-3).
- Never generated: 22 SFX ids, 8 ambience items and 5 music items. The synth, stems or silence stand in for them (K-OV-4).

## 7. Review status (honest)

| What | Status |
|---|---|
| Listening pass on any audio | **Not done.** Only metrics were checked: LUFS, true peak, LRA, mono fold-down and seam rank (K-OV-1) |
| `amb_relay_hub` speech check, Relay growth over `mus_relay` | not done |
| Visual review of the art | composites in phase A, the capture frames above, and the T02 value-ladder / character-contrast gates. No human art review |
| Colour-blind check of the new art | the palettes retint the masks (`ov_v_protan_*`). No review with a filter or a colour-blind person (K-46) |
| Real hardware (GPU, high refresh, subpixel shimmer) | not done (K-OV-11) |
| Web build in a browser | not done (K-M9-W1 still stands) |
| §44 playtest | still pending. Every presentation choice is provisional until players see it |

## 8. How to swap an AI (or hand-made) asset in

The code never names a generator. It names files, sizes and spec ids. To replace any asset:

1. **Keep the file name, the pixel size and the ids.** For a sheet that means the same cell size, origin and `SpriteAnim` names/frame counts in the `.tres` (or an updated `.tres` with the same anim names). For a plane, the same width (480) and height. A B variant is optional. For a UI atlas, the same regions in the `.json`. For audio, the same id: an OGG, or a `.tres` randomizer.
2. **Environments:** put the raw download in `art/source/raw/<manifest id>.png`, then run `python3 -B tools/assetgen/env_process.py <id>`. It downscales, quantizes to the district palette, applies hard alpha and cross-fades the seams, and writes the contract file name. `paint_env.py` then leaves that file alone (`PAINTED()` skips it). **Characters, VFX, UI:** clean the frames to hard alpha (≤ 64 colours, reserved colours only in the `*_mask.png`) and write them over the sheet. **Audio:** trim, normalize (SFX -18, ambience -26, music -20 LUFS), make loops seamless, export OGG, then run `importflags.py --write` for loops.
3. **Add a row to `assets/SOURCES.csv`:** id, kind, tool, model, prompt, credits, raw file, `out_files` (`;`-separated) and `rights` ("ElevenLabs output, check plan terms" or the new source's terms). Remove the old file from the code-drawn row's `out_files`. If a builder would still write the file, drop that item from its script so the rebuild step does not overwrite it.
4. **Check:** `godot --headless --import`, then `python3 -B tools/assetgen/assetgen.py --check`, then `godot --headless res://devtools/content/ValidateContent.tscn`, then the full test suite and `--tour=overhaul` to look at it.

No `.gd` file changes.

## 9. Commands

These are suggested for `redline/CLAUDE.md`'s command list. They are **not** applied there, because that file belongs to the lead:
```bash
python3 -B tools/assetgen/assetgen.py --check                                   # overhaul: asset rebuild drift, provenance, loop flags, reserved colours
godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn -- --budget      # overhaul: per backdrop kind CPU budget + ambient/VFX caps (exit 1 over budget)
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir --tour=overhaul [--only=b,c,u,v]   # exits 1 on a missing shot
```
Also suggested: add `overhaul` to the CaptureTour line's tour list. Add a Conventions line: "Presentation: art/audio live in `assets/` with provenance in `assets/SOURCES.csv`; per-room presentation is `data/presentation/rooms.tres`; keep every placeholder as the fallback; presentation nodes use their own RandomNumberGenerator."
