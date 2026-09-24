# REDLINE Playtest Kit (M4)

This is how to run the bible §44 vertical-slice test with real people and turn their sessions into a decision. Bible §36 M4 says: "Playtest and measure deaths, completion time, confusion, favorite mechanics, control complaints and performance. **Change design before scaling.**"

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

## 4. Running a session (≈ 30–45 min)
**Before**, read this aloud:
> "This is an early build with placeholder art and sound. We're testing the game, not you. There are no wrong answers. Please say what you're thinking if you're comfortable doing that. The game saves a log of this run to a file on this computer, recording things like where you went, where you died, and how smoothly it ran. It doesn't record your name, your voice or anything outside the game. If something confuses you, feels unfair or feels great, pause the game and choose 'Report a moment'. It takes two seconds."

**During:**
- **Don't coach.** If they're stuck for over 3 minutes, give the smallest possible hint, and write down where and when it happened.
- Watch their face and hands, not the screen. Note swearing, sighs, leaning in, and repeated button mashing.
- Cap the session at 45 minutes. If they haven't reached the boss by then, that is data.
- Use the note sheet below.

**After:**
1. The **in-game survey** appears on the slice-complete card. If they stopped early, open it from the pause menu under *Playtest survey*. It has 13 button-only questions and takes about 2 minutes.
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
- the **§44 scorecard**;
- completion time and deaths (by room and by cause);
- confusion signals (room time, re-entries, idle spans, hints, "got lost", reported moments and their notes);
- favourite mechanics;
- controls;
- **real frame times per room**;
- the variant comparison.

## 8. Decide (bible §44: "If these fail, fix the core instead of producing more content")

| Result | Do this |
|---|---|
| **§44 PASS** (≥ 6 of 10 criteria, each met by ≥ 60% of testers) | Fix the top items from the moments, heatmaps and deaths, then move on to M5 (world framework) |
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
| Build system unclear | Circuit descriptions, loadout onboarding at the first Anchor |
| Boss unfair | `enemies/warden_krail.tres`: telegraphs, phase-2 scale, attempts and death causes in the Warden Tower |
| No wish to continue | This is the big one: look at everything above together |

Record every change and its reason in `DECISIONS.md`, as the bible requires.

## 9. Facilitator note sheet (copy once per tester)
```
Tester ID:            Date:           Device: keyboard / controller
Genre experience:     none / some / lots
Session file:         session_…json   Variant (from report):
Time to first death:        Boss reached? y/n   Slice finished? y/n
Hints I had to give (when / where / what):
Stuck moments (room, what they tried):
Visible delight (when / what):
Visible frustration (when / what):
Control complaints (their words):
Interview answers 1-5:
```
