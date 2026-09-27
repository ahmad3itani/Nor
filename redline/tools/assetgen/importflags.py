"""Godot .import flags the asset tools own (loop points of ambience beds and music).

A processed loop is the cut loop region itself, so it loops from sample 0:
[params] loop=true, loop_offset=0. Godot keeps [params] when it re-imports,
so the flag lives in the committed .import file (no .loop marker files).

    python3 importflags.py --check   report oggs whose .import lacks the flag
    python3 importflags.py --write   set the flag on every loop ogg that has a .import
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assetgen_paths import AUDIO  # noqa: E402


def loop_oggs(audio_dir=AUDIO):
    """Every ogg that must loop: all music, and ambience beds whose json says loop."""
    out = sorted(glob.glob(os.path.join(audio_dir, "music", "*.ogg")))
    for js in sorted(glob.glob(os.path.join(audio_dir, "ambience", "*.json"))):
        meta = json.load(open(js))
        if meta.get("loop"):
            out += [os.path.join(os.path.dirname(js), f["file"]) for f in meta.get("files", [])]
    return out


def has_loop(ogg):
    imp = ogg + ".import"
    if not os.path.exists(imp):
        return False
    t = open(imp).read()
    return re.search(r"^loop=true$", t, re.M) is not None and re.search(r"^loop_offset=0(\.0)?$", t, re.M) is not None


def set_loop(ogg):
    """Set loop=true, loop_offset=0 in the ogg's .import [params]; False when there is no .import yet
    (run `godot --headless --import`, then `importflags.py --write`)."""
    imp = ogg + ".import"
    if not os.path.exists(imp):
        return False
    t = open(imp).read()
    t = re.sub(r"^loop=.*$", "loop=true", t, flags=re.M)
    t = re.sub(r"^loop_offset=.*$", "loop_offset=0", t, flags=re.M)
    if "loop=true" not in t:
        t = t.replace("[params]\n", "[params]\n\nloop=true\nloop_offset=0\n", 1)
    open(imp, "w").write(t)
    return True


def main(argv):
    bad = []
    for ogg in loop_oggs():
        if "--write" in argv:
            set_loop(ogg)
        if not has_loop(ogg):
            bad.append(os.path.relpath(ogg, os.path.dirname(AUDIO)))
    for b in bad:
        print("NO LOOP FLAG", b)
    print("import loop flags:", "OK" if not bad else "%d missing" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
