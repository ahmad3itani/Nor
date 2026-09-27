#!/usr/bin/env python3
"""Write tools/assetgen/_preview/sfx_report.md from the processed-output json files + SOURCES.csv."""
import csv, glob, json, os
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402
ROOT = DATA
man = {i["id"]: i for i in json.load(open(os.path.join(ROOT, "sound_manifest.json")))}
cred = {}
for r in csv.DictReader(open(os.path.join(ASSETS, "SOURCES.csv"))):
    if "text_to_sound" in r["model"] or "derive_sfx" in r["tool"]:
        i = r["id"].replace("_try_quota", "")
        cred[i] = cred.get(i, 0) + float(r["credits"] or 0)
metas = {}
for j in glob.glob(os.path.join(AUDIO, "*", "*.json")):
    d = json.load(open(j))
    if isinstance(d, dict) and d.get("id") in man and man[d["id"]]["owner"] == "sfx":
        metas[d["id"]] = (os.path.basename(os.path.dirname(j)), d)
Q = json.load(open(os.path.join(DATA, "sfx_quality.json")))
rows, skipped = [], []
for i, it in man.items():
    if it["owner"] != "sfx":
        continue
    if i not in metas:
        skipped.append(i)
        continue
    cat, d = metas[i]
    files = ", ".join(f"out/{cat}/{f['file']}" for f in d["files"]) + (f" (+ {i}.tres randomizer)" if len(d["files"]) > 1 else "")
    size = sum(f["bytes"] for f in d["files"])
    durs = "/".join(f"{f['dur']:.2f}" for f in d["files"])
    lufs = "/".join(f"{f['lufs']}" for f in d["files"])
    q, note = Q.get(i, ["usable", ""])
    var = f"{len(d['files'])}/{it['variations']}"
    rows.append(f"| {i} | P{it['priority']} | {files} | {size/1024:.1f} KB | {durs} s | {var} | {lufs} | {cred.get(i,0):g} | {q}{' (derived)' if d.get('derived') else ''} | {note} |")
spent = sum(v for k, v in cred.items() if k in man and man[k]["owner"] == "sfx")
out = [
    "# SFX / UI / footstep report (owner \"sfx\")",
    "",
    f"Produced **{len(rows)}** of {len(rows)+len(skipped)} sfx-owned manifest items. ElevenLabs credits spent by this role: **{spent:g}** (share 9,000).",
    "",
    "## Stop reason: account quota exhausted",
    "The ElevenLabs account has a hard **10,000-credit quota** (free plan). Mid-run, generations started failing with",
    "`This request exceeds your quota of 10000. You have 0 credits remaining`. Music (7,200) + ambience (1,580) + images (369)",
    "+ SFX used the whole account quota, so the overhaul's 60,000 budget is not reachable on this plan.",
    "Failed generations were not charged; they are logged in SOURCES.csv as `*_try_quota` rows with credits 0.",
    "",
    "## Pipeline notes",
    "- Measured price: `eleven_text_to_sound_v2` = **10 credits per generated second** (0.8 s = 8, 3 s = 30), not 25/s as budgeted.",
    "- The \"several takes separated by silence\" sheet prompt does NOT work: 3/3 calibration sheets rendered one event. Variations are",
    "  therefore made by re-running the same flow node (one generation per run); footsteps keep a 3 s walking-sequence sheet",
    "  (footstep_metal sliced to 8 steps, best 3 kept). Plan: `tools/sfx_plan.json` (built by `tools/sfx_plan.py`).",
    "- Durations were set through `creative_add_flow_node` model_parameters (`duration_seconds`, `prompt_influence`, `loop`); all nodes live",
    "  on flow `HhZChwEY3696TXlgBGHv` (node ids in `tools/sfx_nodes.txt`), so a later top-up is just `creative_run_flow_nodes` on those ids.",
    "- Processing: `python3 tools/assetgen/process_sfx.py --all` (presets sfx_std / sfx_sheet_slice / stinger_std / ui_std / ui_sheet_slice /",
    "  footstep_sheet: decode, mono, HPF, noise-floor-aware trim, fade, cap at 1.5x duration_s, loudness to target with a <=3 dB limiter",
    "  and -1 dBTP ceiling, OGG Vorbis; multi-take ids also get an `AudioStreamRandomizer` .tres pointing at `res://assets/audio/<cat>/`).",
    "  `--check` passes with 0 warnings; clips below target are INFO \"peak-limited\" (short transients measured padded to 0.5 s; the",
    "  direction's rule is to accept lower loudness rather than limit >3 dB, `mix_db` in the bank does the hierarchy).",
    "- Downloads: phase-A scripts, not in the repo (no networking in tools). Zero-credit derived fallbacks: `tools/derive_sfx.py`.",
    "- Waveform contact sheet for review: `tools/_review/sfx_waveforms.png`.",
    "",
    "## Produced",
    "| id | pri | file(s) | size | duration | takes/wanted | LUFS-I | credits | quality | note |",
    "|---|---|---|---|---|---|---|---|---|---|",
    *rows,
    "",
    "## Skipped (not generated: quota exhausted). SfxSynth placeholder stays the fallback for existing ids.",
    "| id | pri | would cost (credits, at 10/s) |",
    "|---|---|---|",
]
plan = {p["id"]: p for p in json.load(open(os.path.join(DATA, "sfx_plan.json")))}
for i in skipped:
    out.append(f"| {i} | P{man[i]['priority']} | {plan[i]['est']} |")
out += ["",
        "Missing variation takes (1 take shipped where the manifest wants 2-3; `pitch_jitter` + Randomizer random_pitch cover it for now):",
        ", ".join(i for i, (c, d) in sorted(metas.items()) if len(d["files"]) < man[i]["variations"]) + ".",
        "",
        "## To finish (needs credits: ~260 for remaining P1 + second takes, ~370 for P2/P3)",
        "1. Top up / upgrade the ElevenLabs plan.",
        "2. `creative_run_flow_nodes` (generations_count 1) on the node ids in `tools/sfx_nodes.txt` for the skipped ids and the missing takes",
        "   (<= 6 per call; the account's concurrency limit is ~5 and larger calls get 429 for the extra nodes, uncharged).",
        "3. Download with `(the phase-A download scripts, not in the repo: no networking in tools)`, then `python3 tools/assetgen/process_sfx.py --all && python3 tools/assetgen/process_sfx.py --check`.",
        "4. Replace the derived items (ui_back, boss_defeat, memory_open, footstep_concrete) with real generations if they don't hold up in game."]
redo = os.path.join(ROOT, "tools", "sfx_redo.md")
if os.path.exists(redo):
    out.append(open(redo).read())
open(os.path.join(PREVIEW, "sfx_report.md"), "w").write("\n".join(out) + "\n")
print(len(rows), "produced;", len(skipped), "skipped; credits", spent)
