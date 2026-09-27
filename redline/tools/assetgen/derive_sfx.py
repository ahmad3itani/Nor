#!/usr/bin/env python3
"""Zero-credit derived SFX: sound design on already-generated ElevenLabs raws.

The ElevenLabs account hit its 10,000-credit quota mid-run, so a few P1 ids that
never generated are built here from raws we already own (pitch, reverse, filter,
layering). Each is logged in SOURCES.csv as tool=derive_sfx.py, credits 0.

    python3 tools/assetgen/derive_sfx.py            # build all
    python3 tools/assetgen/derive_sfx.py ui_back    # build one
"""
import csv, json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import process_sfx as P  # noqa: E402
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = P.ROOT
SR = P.SR


def raw(i):
    return P.decode(os.path.join(P.RAW, i + ".mp3")).astype(np.float32)


def pitch(x, semis):
    """Tape-style varispeed (pitch and time together), like a slowed/sped reel."""
    r = 2 ** (semis / 12.0)
    n = int(len(x) / r)
    return np.interp(np.arange(n) * r, np.arange(len(x)), x).astype(np.float32)


def lpf(x, fc):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(2, fc, "lowpass", fs=SR, output="sos"), x).astype(np.float32)


def wobble(x, depth=0.004, rate=0.7):
    t = np.arange(len(x)) / SR
    idx = np.arange(len(x)) + depth * SR * np.sin(2 * np.pi * rate * t)
    return np.interp(np.clip(idx, 0, len(x) - 1), np.arange(len(x)), x).astype(np.float32)


def mix(parts, total):
    out = np.zeros(int(total * SR), np.float32)
    for sig, at, gain_db in parts:
        s = int(at * SR)
        e = min(len(out), s + len(sig))
        out[s:e] += sig[: e - s] * 10 ** (gain_db / 20)
    return out


def trimmed(x, tail=-60):
    return P.trim(x, tail)


RECIPES = {
    # menu back: the confirm click a minor third lower and a touch darker
    "ui_back": dict(src=["ui_confirm"], build=lambda: lpf(pitch(trimmed(raw("ui_confirm")), -3), 5000),
                    note="ui_confirm varispeed -3 st + LPF 5 kHz"),
    # 3.5 s machine collapse: overload whine -> sparks/crunch -> body slam -> settling hiss
    "boss_defeat": dict(src=["burnout", "enemy_die", "boss_slam", "wall_break"], build=lambda: mix([
        (pitch(trimmed(raw("burnout")), -2), 0.0, -2),
        (pitch(trimmed(raw("enemy_die")), -4), 0.55, 0),
        (trimmed(raw("boss_slam")), 1.35, 0),
        (lpf(trimmed(raw("wall_break")), 3000), 1.45, -6),
    ], 4.2), note="layered: burnout -2 st, enemy_die -4 st @0.55 s, boss_slam @1.35 s, wall_break LPF @1.45 s"),
    # memory entry: the anchor bell reversed (a reversed swell), muffled, with tape wobble
    "memory_open": dict(src=["anchor"], build=lambda: wobble(lpf(trimmed(raw("anchor"))[::-1].copy(), 1800), 0.005, 0.5),
                        note="anchor reversed + LPF 1.8 kHz + tape wobble 0.5 Hz"),
    # concrete footsteps: the soft wet-concrete landing thud, shortened, three pitch takes
    "footstep_concrete": dict(src=["land_soft"], takes=[0.0, -1.5, 1.2], note="land_soft thud cut to 0.14 s, varispeed 0/-1.5/+1.2 st"),
}


def build(iid):
    man = P.load_manifest()
    item = man[iid]
    pp = P.PRESETS[item["post_process"]]
    cat = P.CAT_DIR[item["category"]]
    odir = os.path.join(P.OUT, cat)
    os.makedirs(odir, exist_ok=True)
    R = RECIPES[iid]
    if "takes" in R:
        base = trimmed(P.hpf_fast(raw(R["src"][0]), pp["hpf"]))
        sigs = [P.fade_out(pitch(base, s)[: int(0.14 * SR)].copy(), 0.03) for s in R["takes"]]
    else:
        sigs = [R["build"]()]
    names, res = [], []
    for k, y in enumerate(sigs):
        y = P.hpf_fast(y, pp["hpf"])
        y = P.trim(y, pp["tail"])
        cap = item["duration_s"] * 1.5
        if len(y) / SR > cap:
            y = P.fade_out(y[: int(cap * SR)].copy(), 0.15)
        else:
            y = P.fade_out(y, pp["fade"])
        y, lufs, tp = P.loudnorm(y, pp["lufs"])
        name = f"{iid}.ogg" if len(sigs) == 1 else f"{iid}_{k + 1}.ogg"
        P.encode_ogg(y, os.path.join(odir, name), pp["q"])
        names.append(name)
        res.append(dict(file=name, dur=round(len(y) / SR, 3), lufs=lufs, tp=tp,
                        bytes=os.path.getsize(os.path.join(odir, name))))
    if len(names) > 1:
        P.write_randomizer(os.path.join(odir, f"{iid}.tres"), names, cat)
    meta = dict(id=iid, category=item["category"], preset=item["post_process"], derived=True,
                raw=[f"raw/{s}.mp3" for s in R["src"]], takes_found=len(names), wanted=item["variations"],
                target_lufs=pp["lufs"], duration_s=item["duration_s"], loop=False, files=res, note=R["note"])
    json.dump(meta, open(os.path.join(odir, f"{iid}.json"), "w"), indent=1)
    rows = list(csv.reader(open(os.path.join(ASSETS, "SOURCES.csv"))))
    if not any(r and r[0] == iid and "derive_sfx" in r[2] for r in rows):
        rel = "assets/audio/" + cat
        outs = ";".join(f"{rel}/{n}" for n in names) + (f";{rel}/{iid}.tres" if len(names) > 1 else "") + f";{rel}/{iid}.json"
        with open(os.path.join(ASSETS, "SOURCES.csv"), "a", newline="") as f:
            csv.writer(f).writerow([iid, "sfx" if item["category"] == "stinger" else item["category"],
                                    "tools/assetgen/derive_sfx.py (local DSP)", "none (derived)",
                                    "n/a: built from " + ",".join(f"raw/{s}.mp3" for s in R["src"]), 0, "", outs,
                                    "DERIVED, 0 credits (ElevenLabs quota exhausted): " + R["note"] +
                                    "; inherits ElevenLabs output terms of its sources",
                                    "ElevenLabs output, check plan terms"])
    print(iid, " ".join(f"{r['file']} {r['dur']}s {r['lufs']}LU tp{r['tp']}" for r in res))


if __name__ == "__main__":
    for i in (sys.argv[1:] or RECIPES):
        build(i)
