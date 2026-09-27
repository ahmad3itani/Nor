#!/usr/bin/env python3
"""Build tools/sfx_plan.json: the generation plan for owner=sfx items.

Calibration showed eleven_text_to_sound_v2 renders ONE event per short clip (the
"several takes separated by silence" sheet prompt gave 1 take in 3/3 tests) and costs
~10 credits per generated second. So variations are made by re-running the same node
(one generation per run, generations_count 1), each run a short single-event clip.
Footsteps keep the 3 s sheet (the model renders a walking sequence -> several steps).
"""
import json, os
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402
ROOT = DATA
SHEET_TAIL = ("Several separate takes one after another, each clearly separated by half a second "
              "of total silence, slight natural variation between takes, no music, no voice.")
SINGLE = "Single isolated one-shot sound effect, one event only, close-mic, dry, clean, on total digital silence with no background hiss or room tone, no music, no voice, no speech."
man = json.load(open(os.path.join(ROOT, "sound_manifest.json")))
plan = []
for i in man:
    if i["owner"] != "sfx":
        continue
    p = i["prompt"]
    runs = 1
    dur = i["gen_duration_s"]
    if i["gen_mode"] == "sheet":
        if i["category"] == "footstep":
            p = p.replace(SHEET_TAIL, "A short sequence of separate footsteps with small gaps, steady pace, no music, no voice.")
            dur = 3.0
            runs = 1
        else:
            p = p.replace(SHEET_TAIL, SINGLE)
            dur = round(min(2.0, max(0.8, i["duration_s"] * 2.0)), 1)
            runs = i["variations"]
    plan.append(dict(id=i["id"], priority=i["priority"], prompt=p, duration=dur, loop=bool(i["loop"]),
                     prompt_influence=i["prompt_influence"], runs=runs,
                     est=round(10 * dur * runs)))
json.dump(plan, open(os.path.join(DATA, "sfx_plan.json"), "w"), indent=1)
print(len(plan), "items; est credits", sum(p["est"] for p in plan))
for pr in (1, 2, 3):
    print(pr, sum(p["est"] for p in plan if p["priority"] == pr))
