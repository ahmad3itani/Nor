#!/usr/bin/env python3
"""assetgen: one entry point for every asset tool (presentation overhaul, T01).

    python3 -B tools/assetgen/assetgen.py --check
    python3 -B tools/assetgen/assetgen.py --check --quick   (skip the rebuild-drift step)

--check runs, and exits 1 on any problem:
 1. palettes.py --check: no decorative palette colour near a reserved gameplay colour.
 2. Rebuild drift: build_chars, fx_vfx, fx_ui, tiles_null and env_process (for every raw
    image in art/source/raw) rebuild into a temp dir; every file they write must be
    byte-identical to the committed one (assets/ and art/source/). Their own validators
    run on the rebuilt output.
 3. build_chars.py --check and env_process.py --check on the committed files.
 4. Audio: process_sfx.py --check and process_music_amb.py --check. The raw MP3s are not
    in the repo, so these are metadata checks (the per-file loudness / loop / seam numbers
    each json records, against the SOUND_DIRECTION targets); OGG bytes are not rebuilt
    (the Ogg muxer picks random stream serials).
 5. importflags.py: every music track and ambience bed loops from 0 in its .import.
 6. Provenance: every PNG/OGG under assets/ is named by an out_files entry in
    assets/SOURCES.csv (";"-separated res-relative paths); every entry exists and holds
    no "+" or "out/"; every row has a rights value.
 7. Reserved colours: no colour in a PNG outside ui/ and vfx/ (tint masks) lies within
    RGB distance 48 of a reserved gameplay colour, except the sanctioned baked Redline
    red of the characters that carry a tint mask (SANCTIONED).

No step needs the network or a generator (0 credits). New builders add a line to BUILDERS.
"""
from __future__ import annotations

import csv
import filecmp
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from assetgen_paths import REDLINE, REPO_ASSETS, SOURCE  # noqa: E402

PY = sys.executable
SOURCES_CSV = os.path.join(REPO_ASSETS, "SOURCES.csv")
# (script, args): rebuilt into ASSETGEN_OUT, compared with the repo
BUILDERS = [
    ("build_chars.py", []),
    ("fx_vfx.py", []),
    ("fx_ui.py", []),
    ("tiles_null.py", []),
]
# validators on the committed files: (script, args)
CHECKS = [
    ("palettes.py", ["--check"]),
    ("build_chars.py", ["--check"]),
    ("env_process.py", ["--check"]),
    ("process_music_amb.py", ["--check"]),
    ("importflags.py", ["--check"]),
]
# process_sfx --check prints WARN lines for delivered takes it would flag; it is
# informational (the phase-A review accepted them) and never fails the gate.
INFO_CHECKS = [("process_sfx.py", ["--check"])]
# file (relative to assets/) -> baked colours allowed near a reserved colour, and why
SANCTIONED = {
    "rook/rook_sheet.png": {"#e8283c"},
    "bosses/warden_krail_sheet.png": {"#e8283c"},
    "portraits/portrait_rook.png": {"#e8283c"},
    "portraits/portrait_krail.png": {"#e8283c"},
}
SANCTIONED_WHY = "the baked Redline red (visor / Core seam); rook and krail carry a _mask.png so code can re-tint it"
TINT_MASK_DIRS = ("ui/", "vfx/")


def run(script, args, env=None, quiet=True):
    p = subprocess.run([PY, "-B", os.path.join(HERE, script)] + args, cwd=REDLINE, env=env,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def walk(root):
    for dp, dns, fs in os.walk(root):
        dns[:] = [d for d in dns if not d.startswith((".", "_preview"))]
        for f in fs:
            yield os.path.join(dp, f)


def drift(problems):
    """Rebuild every image builder into a temp dir and compare byte for byte."""
    with tempfile.TemporaryDirectory(prefix="assetgen_") as tmp:
        env = dict(os.environ, ASSETGEN_OUT=tmp, ASSETGEN_PREVIEW=os.path.join(tmp, "_preview"))
        steps = list(BUILDERS)
        raws = sorted(f[:-4] for f in os.listdir(os.path.join(SOURCE, "raw")) if f.endswith(".png")) \
            if os.path.isdir(os.path.join(SOURCE, "raw")) else []
        if raws:
            steps.append(("env_process.py", raws))
        for script, args in steps:
            code, out = run(script, args, env)
            print(f"  rebuild {script} {' '.join(args)}: exit {code}")
            if code != 0:
                problems.append(f"{script} rebuild failed:\n{out[-2000:]}")
        n = 0
        for p in walk(tmp):
            rel = os.path.relpath(p, tmp)
            if rel.startswith("_preview"):
                continue
            repo = os.path.join(SOURCE, os.path.relpath(p, os.path.join(tmp, "_source"))) if rel.startswith("_source") \
                else os.path.join(REPO_ASSETS, rel)
            n += 1
            if not os.path.exists(repo):
                problems.append(f"drift: a builder writes {os.path.relpath(repo, REDLINE)}, which is not committed")
            elif not filecmp.cmp(p, repo, shallow=False):
                problems.append(f"drift: {os.path.relpath(repo, REDLINE)} differs from what its builder makes")
        print(f"  rebuilt {n} files")


def provenance(problems):
    rows = list(csv.DictReader(open(SOURCES_CSV)))
    need = {"id", "kind", "tool", "model", "credits", "raw_file", "out_files", "rights"}
    if not rows or not need <= set(rows[0].keys()):
        problems.append(f"SOURCES.csv header must hold {sorted(need)}")
        return
    named = set()
    for r in rows:
        if not r["rights"].strip():
            problems.append(f"SOURCES.csv row {r['id']}: empty rights")
        for f in filter(None, (x.strip() for x in r["out_files"].split(";"))):
            if "+" in f or f.startswith("out/") or f.startswith("/") or f.startswith("res://"):
                problems.append(f"SOURCES.csv row {r['id']}: out_files entry '{f}' is not a plain res-relative path")
                continue
            if not os.path.exists(os.path.join(REDLINE, f)):
                problems.append(f"SOURCES.csv row {r['id']}: {f} does not exist")
            named.add(os.path.normpath(f))
    for p in walk(REPO_ASSETS):
        rel = os.path.relpath(p, REDLINE)
        if os.path.basename(p).startswith(".") or p.endswith((".import", ".tres", ".json")) \
                or os.path.basename(p) in ("README.md", "SOURCES.csv"):
            continue
        if os.path.normpath(rel) not in named:
            problems.append(f"provenance: {rel} has no SOURCES.csv row (out_files)")
    print(f"  {len(rows)} SOURCES.csv rows, {len(named)} files named")


def reserved(problems):
    import numpy as np
    from PIL import Image
    pal = json.load(open(os.path.join(HERE, "palettes.json")))
    res = {k: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for k, h in pal["reserved"].items()}
    lim = pal.get("min_reserved_distance", 48)
    n = 0
    for p in walk(REPO_ASSETS):
        if not p.endswith(".png"):
            continue
        rel = os.path.relpath(p, REPO_ASSETS).replace(os.sep, "/")
        name = os.path.basename(p)
        if rel.startswith(TINT_MASK_DIRS) or name.endswith(("_mask.png", "_fill.png")):
            continue
        n += 1
        a = np.asarray(Image.open(p).convert("RGBA"))
        cols = {tuple(c) for c in a[a[..., 3] > 0][:, :3].tolist()}
        allowed = SANCTIONED.get(rel, set())
        for c in cols:
            hexc = "#%02x%02x%02x" % c
            if hexc in allowed:
                continue
            for k, r in res.items():
                if math.dist(c, r) < lim:
                    problems.append(f"reserved: {rel} uses {hexc}, {math.dist(c, r):.0f} from {k} {pal['reserved'][k]}")
    print(f"  {n} decorative PNGs checked ({len(SANCTIONED)} sanctioned: {SANCTIONED_WHY})")


def main(argv):
    if "--check" not in argv:
        print(__doc__)
        return 0
    problems: list[str] = []
    print("1-3. builders")
    if "--quick" not in argv:
        drift(problems)
    for script, args in CHECKS:
        code, out = run(script, args)
        print(f"  {script} {' '.join(args)}: exit {code}")
        if code != 0:
            problems.append(f"{script} {' '.join(args)} failed:\n{out[-3000:]}")
    for script, args in INFO_CHECKS:
        code, out = run(script, args)
        warns = [l for l in out.splitlines() if l.startswith("WARN")]
        print(f"  {script} {' '.join(args)}: exit {code}, {len(warns)} informational warnings")
        for w in warns:
            print("    " + w)
        if code != 0:
            problems.append(f"{script} crashed:\n{out[-2000:]}")
    print("6. provenance")
    provenance(problems)
    print("7. reserved colours")
    reserved(problems)
    for p in problems:
        print("PROBLEM", p)
    print("assetgen --check:", "OK" if not problems else f"{len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
