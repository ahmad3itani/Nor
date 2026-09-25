# REDLINE Playtest Kit (M4, updated for M7)

This is how to run the bible §44 vertical-slice test with real people and turn their sessions into a decision. Bible §36 M4 says: "Playtest and measure deaths, completion time, confusion, favorite mechanics, control complaints and performance. **Change design before scaling.**"

> **Since M7 (batch 1), New Game is the Act I campaign.** It starts unarmed in Undercity/Wake and plays about 20–37 min (estimated, K-45) through the Undercity and the Collector Drone before the Relay, then Lowlight to Warden Krail. The old slice (full kit, Relay start) is the **"Slice (Relay start)"** title entry, which exists in **debug builds only**. Which build the §44 round uses is an open decision (D-068, K-58).

The game records and summarises most of this by itself. What it can't do is find the testers and watch them play. That part is yours.

---

## 1. Who and how many
- **5–8 external testers.** They must not have worked on REDLINE. Around five people surface most usability problems. §44 asks whether *most* testers report each criterion, so fewer than five gives you anecdotes, not a verdict. The report warns you when that's the case.
- Aim for a mix: a couple of genre fans (Hollow Knight, Katana ZERO, Celeste players), a couple of lighter action players, and at least two on a **controller**.
- Use at least one machine that isn't a development PC. Frame times are recorded on real hardware, and that data is exactly what's missing so far (K-2).

## 2. Build the game for testers
- **Easiest:** testers run it from the Godot 4.3 editor (open `redline/project.godot`, press F5). That's fine for in-person sessions.
- **Exported build:** in the Godot editor, go to *Project → Export*, add a preset (Windows Desktop, Linux or macOS), install the 4.3 export templates when prompted, and export. `export_presets.cfg` is gitignored on purpose because it can hold signing credentials.
- Check that the title screen shows **"Playtest recording ON"** with the save folder.

## 3. Settings before each session
In Settings on the title screen:

| Setting | Value | Why |
|---|---|---|
| Playtest recording | **On** | Writes the session file |
| Playtest variant | **Auto** (rotates) | Or pin arms so they alternate across testers, for a balanced split |
| Core mode | Normal | What §44 judges |
| Drop Scrap on death | On | The standard rules from bible §7 |
| Debug overlay | Off | Testers should see the real game |

**The experiment:** Auto alternates between `baseline` and `strong_slide_jump` (D-036). The tester isn't told which arm they got. It's recorded in the session file.

## 4. Running a session (campaign ≈ 60–90 min; Relay-start slice ≈ 30–45 min)
**Before**, read this aloud:
> "This is an early build with placeholder art and sound. We're testing the game, not you. There are no wrong answers. Please say what you're thinking if you're comfortable doing that. The game saves a log of this run to a file on this computer, recording things like where you went, where you died, and how smoothly it ran. It doesn't record your name, your voice or anything outside the game. If something confuses you, feels unfair or feels great, pause the game and choose 'Report a moment'. It takes two seconds."

**During:**
- **Don't coach.** If they're stuck for over 3 minutes, give the smallest possible hint, and write down where and when it happened.
- Watch their face and hands, not the screen. Note swearing, sighs, leaning in, and repeated button mashing.
- Cap a campaign session at **75 minutes** (a Relay-start session at 45). If they haven't reached Krail by then, that is data. Write down the minute they reach the Relay either way.
- Keep the §42 timeline on the note sheet (§9): the analyzer measures most of it, but your minute marks catch what the events can't (for example, when they *understood* the Core).
- Use the note sheet below.

**After:**
1. The **in-game survey** appears on the slice-complete card. If they stopped early, open it from the pause menu under *Playtest survey*. It has 14 button-only questions and takes about 2 minutes.
2. Ask the five interview questions (§6), and write down their exact words.
3. Collect the session file (§5).

## 5. Collect the files
Each run writes `session_<date>_<n>.json`. The title screen shows the exact folder. By default:

| OS | Folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\REDLINE\playtests` |
| Linux | `~/.local/share/godot/app_userdata/REDLINE/playtests` |
| macOS | `~/Library/Application Support/Godot/app_userdata/REDLINE/playtests` |

Copy all `session_*.json` files into one folder. Rename them if you like (for example, `session_T03_ana.json`), but keep the `session_` prefix. The files contain no personal data. Delete the folder to erase them.

## 6. Interview (5 questions, 5 minutes)
1. "Describe the game to a friend in one sentence."
2. "What was the best moment? And the most frustrating one?"
3. "What does the red Core bar do? What happens when it empties?"
4. "What are Circuits for? Which ones would you pick next time?"
5. "If this came out tomorrow, what would make you buy it, and what would stop you?"

## 7. Build the report
```bash
cd redline
godot --headless res://devtools/PlaytestReport.tscn -- --in=/abs/path/to/sessions --out=/abs/path/to/report
```
This writes `REPORT.md` plus `heatmaps/<Room>.png`. The report contains:
- the **§44 scorecard** (ten scored questions; the Collector question is extra and unscored, D-079);
- completion time and deaths (by room and by cause). Since M7 there are three time lines:
  - **Completion time, whole run**: New Game to the end card, now including the Undercity;
  - **Lowlight time, Relay arrival → slice_complete**: compare *this* one, not the whole run, with the old 15–25 min slice target;
  - session length;
- **separate boss lines**: Warden Krail (attempts per tester who reached him, clears) and the Collector Drone (the same for it);
- the **Undercity timeline** (below);
- the **district set pieces**: shutter pass margins per shutter (median and closest), chase catches per completed run and by checkpoint, Collector eye locks by room and eye, scanner trips by kind (live / calibration), room and beam, Grid clamp drops, and breakers struck by room and circuit;
- confusion signals (room time, re-entries, idle spans, hints, "got lost", reported moments and their notes);
- favourite mechanics;
- controls;
- **real frame times per room**;
- the variant comparison.

**The Undercity timeline** gives the median minute of each §42 beat: Pulse Blade granted, first dodge, Maintenance Shaft entered (a proxy for the first composition, about 2–3 min early), first secret, first NPC (the Radio), First Pursuit entered, first Flow hint, Core HUD shown, first Anchor rest, rest at `uc_lift`, Collector fight started, Collector defeated, Relay reached. Which sessions count:
- **Counted:** sessions of kind `new` (the New Game button) whose first room is Wake. These give the medians.
- **Separate table:** `continue` sessions that start in an Undercity room, measured from the cumulative play-time stamp.
- **Excluded (and counted at the bottom):** `new_relay` debug sessions ("Slice (Relay start)") and anything else.

Compare the medians with §42 and D-083: move/jump/interact and the blade in 0–5 min; dodge, the first composition and the first secret in 5–15; the first NPC, the safe Core introduction, the first Anchor and the first mini-boss in 15–30; the Relay in 30–60. If the median Relay arrival is under about 25 min, the Undercity is too short (D-083).

**Expected close call:** Power Block's S4b is meant to be passed low under the closing panel, and the report shows it as a small margin (about 0.2 s). Read that row as expected (K-52).

## 8. Decide (bible §44: "If these fail, fix the core instead of producing more content")

| Result | Do this |
|---|---|
| **§44 PASS** (≥ 6 of 10 criteria, each met by ≥ 60% of testers) | Fix the top items from the moments, heatmaps and deaths, then move on to M7 batch 2 (Ironworks) |
| **NOT YET** | Don't add content. For each failing criterion, change the core using the levers below, then run another round of testing |

| Failing criterion | First places to look (all data, `data/…`) |
|---|---|
| Movement not satisfying | `movement/default_movement.tres` (the F3 panel lives there), camera config, the slide-jump arm result |
| Reactor not understood | `reactor/*.tres` drain and refill, the Flow Zone hint text, HUD critical feedback |
| No wish to replay stylishly | `style/*.tres` rank thresholds and rewards; style peaks per room in the report |
| Combat not readable | Enemy `startup` (telegraphs), `hitstop`, "Unfair hit" moments and death causes |
| No memorable enemy | The enemy roster and roles; the survey's enemy choices |
| Not curious about Veyra/Rook | Lore fragments, dialogue (`data/npcs`, `data/lore`) |
| Secrets not noticed | Secret placement (the heatmaps show where players never went) |
| Chart Lowlight never completes (or completes by accident) | `data/world/world_map.tres` `district_thresholds` (M7 D8b: lowlight 0.5 of standable 0.630, undercity 0.4 of standable 0.618; keep each within [0.6, 0.85] × standable, which `test_thresholds_match_standable_coverage` prints) |
| Build system unclear | Circuit descriptions, loadout onboarding at the first Anchor |
| Boss unfair | `enemies/warden_krail.tres`: telegraphs, phase-2 scale, attempts and death causes in the Warden Tower; the Grid Clamp (`data/level/clamp_krail.tres`) and its breakers |
| Collector Drone unfair (unscored `collector_fair`, the Collector line) | `enemies/collector_drone.tres` (HP first, K-56), its `collector_*` attacks in `data/combat/`, deaths in Collector Bay |
| Undercity too short or too long (timeline) | Room depth in Medical Ruin and First Pursuit (D-083); the eye's `data/props/collector_eye.tres` if First Pursuit stalls |
| Too many chase catches / close shutter calls | `data/world/chase/rainline.tres` (speed, leads), `data/level/shutter_*.tres` (open times) |
| No wish to continue | This is the big one: look at everything above together |

Record every change and its reason in `DECISIONS.md`, as the bible requires.

## 9. Facilitator note sheet (copy once per tester)
```
Tester ID:            Date:           Device: keyboard / controller
Genre experience:     none / some / lots
Session file:         session_…json   Variant (from report):
Build: campaign (New Game) / Relay start (debug)
Time to first death:        Relay reached (min):    Krail reached? y/n   Act I finished? y/n
§42 minute marks (campaign):
  Blade pickup:      First dodge:        First composition (Shaft Floor 2):
  First secret:      Core hint (Broken Lift):              First rest (uc_lift):
  Collector start:   Collector win:      Relay arrival:
Shutter moments (which shutter, made it / went low / missed):
Chase catches (which checkpoint, their reaction):
Hints I had to give (when / where / what):
Stuck moments (room, what they tried):
Visible delight (when / what):
Visible frustration (when / what):
Control complaints (their words):
Interview answers 1-5:
```
