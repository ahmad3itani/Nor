#!/usr/bin/env python3
"""REDLINE SFX / UI / footstep post-processor (SOUND_DIRECTION.md section 4).

Reproducible from raw downloads:
    python3 tools/assetgen/process_sfx.py <id> [<id> ...]      # process from raw/<id>.*
    python3 tools/assetgen/process_sfx.py --all                 # every sfx-owner item with a raw file
    python3 tools/assetgen/process_sfx.py --check               # QA every processed output

Presets implemented: sfx_std, sfx_sheet_slice, stinger_std, ui_std, ui_sheet_slice,
footstep_sheet, plus loop handling (loop=true -> seamless equal-power crossfade).
Outputs: assets/audio/<category>/<id>.ogg, or <id>_1..N.ogg + <id>.tres (AudioStreamRandomizer).
Writes assets/audio/<category>/<id>.json with measurements (used by --check and the report).
"""
import glob, json, os, re, subprocess, sys, tempfile
import numpy as np
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
RAW = RAW
OUT = AUDIO
SR = 44100


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


FF = ffmpeg()

PRESETS = {
    # hpf, target LUFS, head thr dB, tail thr dB, fade out s, ogg q
    "sfx_std": dict(hpf=35, lufs=-18, tail=-60, fade=0.03, q=5),
    "sfx_sheet_slice": dict(hpf=35, lufs=-18, tail=-60, fade=0.03, q=5),
    "stinger_std": dict(hpf=35, lufs=-18, tail=-70, fade=0.15, q=5),
    "ui_std": dict(hpf=150, lufs=-20, tail=-60, fade=0.03, q=5),
    "ui_sheet_slice": dict(hpf=150, lufs=-20, tail=-60, fade=0.02, q=5),
    "footstep_sheet": dict(hpf=60, lufs=-22, tail=-60, fade=0.02, q=4, maxlen=0.25),
}
CAT_DIR = {"sfx": "sfx", "stinger": "sfx", "ui": "ui", "footstep": "footsteps"}


def load_manifest():
    with open(os.path.join(DATA, "sound_manifest.json")) as f:
        return {i["id"]: i for i in json.load(f)}


def decode(path):
    """Decode any file to mono float32 @44.1k (L+R -3 dB)."""
    cmd = [FF, "-v", "error", "-i", path, "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    st = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)
    return (st[:, 0] + st[:, 1]) * 0.7071


def hpf(x, fc):
    # 2nd-order Butterworth high-pass (biquad), applied twice for 24 dB/oct
    w0 = 2 * np.pi * fc / SR
    a = np.sin(w0) / (2 * 0.7071)
    c = np.cos(w0)
    b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b = np.array([b0, b1, b2]) / a0
    aa = np.array([1, a1 / a0, a2 / a0])
    for _ in range(2):
        y = np.zeros_like(x)
        x1 = x2 = y1 = y2 = 0.0
        # vectorised enough for short clips
        for n in range(len(x)):
            xn = x[n]
            yn = b[0] * xn + b[1] * x1 + b[2] * x2 - aa[1] * y1 - aa[2] * y2
            y[n] = yn
            x2, x1, y2, y1 = x1, xn, y1, yn
        x = y
    return x


def hpf_fast(x, fc):
    try:
        from scipy.signal import butter, sosfilt
        return sosfilt(butter(4, fc, "highpass", fs=SR, output="sos"), x).astype(np.float32)
    except Exception:
        return hpf(x.astype(np.float64), fc).astype(np.float32)


def db(v):
    return 20 * np.log10(max(v, 1e-12))


def env_db(x, win=0.01):
    n = max(1, int(SR * win))
    pad = (-len(x)) % n
    xx = np.concatenate([x, np.zeros(pad)]).reshape(-1, n)
    return 20 * np.log10(np.sqrt((xx ** 2).mean(1)) + 1e-12), n


def split_takes(x, thr=-45.0, min_sil=0.12, min_take=0.03):
    """Silence-based slicing relative to clip peak (silencedetect -45 dB, d=0.12).
    The threshold is raised to noise floor + 10 dB when the clip carries hiss."""
    e, n = env_db(x)
    e = e - e.max()
    thr = max(thr, float(np.percentile(e, 10)) + 10.0)
    loud = e > thr
    takes, start, sil = [], None, 0
    minsil = int(min_sil / (n / SR))
    for i, l in enumerate(loud):
        if l:
            if start is None:
                start = i
            sil = 0
        elif start is not None:
            sil += 1
            if sil >= minsil:
                takes.append((start, i - sil + 1))
                start, sil = None, 0
    if start is not None:
        takes.append((start, len(loud) - sil))
    out = []
    for a, b in takes:
        s, t = a * n, min(len(x), b * n + int(0.08 * SR))  # keep a bit of tail
        if (t - s) / SR >= min_take:
            out.append((s, t))
    return out


def noise_floor_db(x):
    """Relative (to peak) level of the quietest 10 % of 10 ms windows."""
    e, _ = env_db(x, 0.01)
    return float(np.percentile(e, 10) - e.max())


def trim(x, tail_db, head_db=-50.0):
    pk = np.abs(x).max() + 1e-12
    nf = noise_floor_db(x)
    # a generated bed of hiss would otherwise keep the tail forever: stay 8 dB above it
    tail_db = max(tail_db, nf + 8.0)
    head_db = max(head_db, nf + 10.0)
    a = np.abs(x) / pk
    idx = np.where(a > 10 ** (head_db / 20))[0]
    if len(idx) == 0:
        return x
    s = idx[0]
    idx2 = np.where(a > 10 ** (tail_db / 20))[0]
    t = idx2[-1] + 1
    cut_mid = s > 0 and a[max(0, s - 1)] > 10 ** (-60 / 20)
    y = x[s:t].copy()
    if cut_mid:
        f = int(0.002 * SR)
        y[:f] *= np.linspace(0, 1, f)
    return y


def fade_out(y, sec):
    f = min(len(y), int(sec * SR))
    if f > 1:
        y[-f:] *= np.cos(np.linspace(0, np.pi / 2, f)) ** 2
    return y


def write_wav(path, y, ch=1):
    import wave
    y16 = np.clip(y, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y16 * 32767).astype("<i2").tobytes())


def measure(y):
    """Integrated LUFS (padded to 0.5 s) and true peak via ffmpeg ebur128."""
    pad = max(0, int(0.5 * SR) - len(y))
    z = np.concatenate([y, np.zeros(pad, dtype=np.float32)])
    # write at a safe scale (float input may exceed 1.0; the 16-bit wav would clip) and compensate
    pk = float(np.abs(z).max()) + 1e-12
    k = 0.5 / pk
    z = z * k
    comp = -20 * np.log10(k)
    # ebur128 needs >=400 ms blocks; also repeat very short signals is NOT done (honest measure)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        p = f.name
    write_wav(p, z)
    r = subprocess.run([FF, "-hide_banner", "-nostats", "-i", p, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    os.unlink(p)
    lufs = tp = None
    for line in r.splitlines()[::-1]:
        line = line.strip()
        if line.startswith("I:") and lufs is None:
            lufs = float(line.split()[1])
        if line.startswith("Peak:") and tp is None:
            tp = float(line.split()[1])
    if lufs is not None:
        lufs = round(lufs + comp, 1) if lufs > -70 else lufs
    if tp is not None:
        tp = round(tp + comp, 1)
    return lufs, tp


def loudnorm(y, target, ceiling=-1.0):
    lufs, tp = measure(y)
    if lufs is None or lufs < -70:
        return y, lufs, tp
    gain = target - lufs
    # peak ceiling (default -1 dBTP; -1.5 where the OGG overshoots); if the limiter
    # would need > 3 dB, accept lower loudness
    over = (tp + gain) - ceiling
    if over > 0:
        if over <= 3.0:
            y = soft_limit(y * 10 ** (gain / 20), 10 ** ((ceiling - 0.3) / 20))
        else:
            gain -= over - 3.0
            y = soft_limit(y * 10 ** (gain / 20), 10 ** ((ceiling - 0.3) / 20))
    else:
        y = y * 10 ** (gain / 20)
    lufs2, tp2 = measure(y)
    # final safety: pure gain down if true-peak still above ceiling
    if tp2 is not None and tp2 > ceiling:
        y = y * 10 ** ((ceiling - 0.1 - tp2) / 20)
        lufs2, tp2 = measure(y)
    return y.astype(np.float32), lufs2, tp2


def soft_limit(y, ceil):
    # simple look-ahead-free peak limiter: gain envelope from abs with 5 ms release
    a = np.abs(y)
    g = np.ones_like(y)
    over = a > ceil
    g[over] = ceil / a[over]
    rel = int(0.005 * SR)
    # smooth gain (min filter then moving average) to avoid clicks
    from numpy.lib.stride_tricks import sliding_window_view
    gp = np.concatenate([np.ones(rel), g, np.ones(rel)])
    gm = sliding_window_view(gp, 2 * rel + 1).min(axis=1)
    k = np.ones(rel) / rel
    gs = np.convolve(gm, k, mode="same")
    gs = np.minimum(gs, g)
    return (y * gs).astype(np.float32)


def make_loop(y, xfade=None):
    """Equal-power crossfade the tail into the head, drop the tail."""
    xf = int((xfade or min(1.0, len(y) / SR / 4)) * SR)
    head, tail = y[:xf], y[-xf:]
    t = np.linspace(0, np.pi / 2, xf)
    mixed = tail * np.cos(t) + head * np.sin(t)
    return np.concatenate([mixed, y[xf:-xf]]).astype(np.float32)


def encode_ogg(y, path, q):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        p = f.name
    write_wav(p, y)
    subprocess.run([FF, "-v", "error", "-y", "-i", p, "-c:a", "libvorbis", "-q:a", str(q), "-ar", str(SR), "-ac", "1", path],
                   check=True)
    os.unlink(p)


def onset_sharpness(y):
    e, n = env_db(y, 0.002)
    k = int(np.argmax(e))
    return -k  # earlier peak = sharper


def raws_for(iid):
    fs = sorted(glob.glob(os.path.join(RAW, iid + ".mp3")) + glob.glob(os.path.join(RAW, iid + "__v*.mp3")))
    return fs


# ------------------------------------------------------------------ per-id overrides
# Sound-director redo pass (see out/sfx_report.md "Redo pass"). Keys:
#   raws        list of raw paths (relative to ROOT) instead of raw/<id>*.mp3
#   extra       extra whole-file takes processed like sfx_std (e.g. the pilot slash)
#   variations  number of sheet takes to keep
#   multi       always name <id>_1.ogg and write <id>.tres even with one take
#   head        ("win"|"sample", rel_db, pre_s, fadein_s): cut to pre_s before the first
#               10 ms window (or sample) above take-peak + rel_db, then a fade-in
#   peak_start  (pre_s, fadein_s): start pre_s before the 1 ms-window peak
#   cap, cap_fade, force_cap   length cap (s) with its fade; force_cap applies it always
#   tail        tail threshold dB override
#   ceiling     limiter true-peak ceiling before encode (decoded OGG must still be <= -1.0)
#   lufs        loudness target override
#   min_take    drop takes shorter than this after trimming (if another take remains)
#   select      "consistent": keep the N takes with the closest loudness whose peak is
#               inside peak_ms (footstep sheets)
#   varispeed   list of semitone offsets: takes derived from the single chosen take
#   match_lu    attenuate louder takes so all takes sit within this many LU
#   hold        reason string: file is processed but meta ship=false (keep the synth fallback)
OVR = {
    "slash": dict(extra=["pilot/slash.wav"], variations=1, multi=True, match_lu=1.0),
    "hit": dict(raws=["raw/hit.mp3"], variations=1, multi=True, cap=0.21, cap_fade=0.06, force_cap=True),
    "player_hurt": dict(ceiling=-1.5),
    "shoot_scatter": dict(cap=0.82, cap_fade=0.04, ceiling=-1.5),
    "scrap_pickup": dict(head=("sample", -24.0, 0.005, 0.002), ceiling=-1.5),
    "perfect_dodge": dict(peak_start=(0.12, 0.003), cap=1.2, tail=-60),
    "jump": dict(head=("win", -20.0, 0.003, 0.002), min_take=0.12, match_lu=1.0),
    # director asked head-trim at peak-18 dB/20 ms, but that leaves the peak at 92 ms (> 60 ms
    # acceptance): the whoosh swells gradually. Start 45 ms before the peak instead.
    "dodge": dict(peak_start=(0.045, 0.004)),
    "purchase": dict(head=("win", -24.0, 0.003, 0.002), cap=0.6, cap_fade=0.04),
    "footstep_metal": dict(select="consistent", peak_ms=25, match_lu=2.0),
    # 3 tiny clicks, onset -49 dB: keep the SfxSynth placeholder until a regenerated take passes
    "shoot_pistol": dict(hold="weak take (3 small clicks, peak at 254 ms, -25.8 LUFS); keep SfxSynth placeholder until regenerated"),
    "ui_tick": dict(varispeed=[0.0, 1.5, -1.5], lufs=-21, match_lu=1.0),
}


def fade_in(y, sec):
    f = min(len(y), int(sec * SR))
    if f > 1:
        y[:f] *= np.sin(np.linspace(0, np.pi / 2, f)) ** 2
    return y


def head_trim(y, mode, rel_db, pre_s, fin_s):
    if mode == "sample":
        a = np.abs(y)
        idx = np.where(a > a.max() * 10 ** (rel_db / 20))[0]
        first = int(idx[0]) if len(idx) else 0
    else:
        e, n = env_db(y, 0.01)
        w = np.where(e > e.max() + rel_db)[0]
        first = int(w[0]) * n if len(w) else 0
    s = max(0, first - int(pre_s * SR))
    return fade_in(y[s:].copy(), fin_s)


def peak_ms(y):
    n1 = int(0.001 * SR)
    k = len(y) // n1
    return float(np.argmax((y[: k * n1].reshape(k, n1) ** 2).mean(1))) + 0.5


def start_before_peak(y, pre_s, fin_s):
    s = max(0, int((peak_ms(y) / 1000 - pre_s) * SR))
    return fade_in(y[s:].copy(), fin_s)


def varispeed(x, semis):
    r = 2 ** (semis / 12.0)
    n = int(len(x) / r)
    return np.interp(np.arange(n) * r, np.arange(len(x)), x).astype(np.float32)


def decode_mono(path):
    cmd = [FF, "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).copy()


def encode_verified(y, path, q, limit=-1.0):
    """Encode, decode and re-measure the OGG; trim gain until decoded true peak <= limit."""
    for _ in range(6):
        encode_ogg(y, path, q)
        d = decode_mono(path)
        # the Vorbis round trip drops ~3 ms at the end; pad back to the source length so the
        # 400 ms ebur128 block grid (and so the integrated value) matches the pre-encode measure
        d = np.concatenate([d, np.zeros(max(0, len(y) - len(d)), np.float32)])
        lufs, tp = measure(d)
        if tp is None or tp <= limit:
            break
        y = (y * 10 ** ((limit - 0.1 - tp) / 20)).astype(np.float32)
    return y, lufs, tp


def process(item, raw_path, variations_override=None):
    pp = item["post_process"]
    o = OVR.get(item["id"], {})
    P = dict(PRESETS[pp])
    if "tail" in o:
        P["tail"] = o["tail"]
    target_lufs = o.get("lufs", P["lufs"])
    ceiling = o.get("ceiling", -1.0)
    cat = CAT_DIR[item["category"]]
    odir = os.path.join(OUT, cat)
    os.makedirs(odir, exist_ok=True)
    if "raws" in o:
        raw_path = [os.path.join(ROOT, r) for r in o["raws"]]
    raw_list = raw_path if isinstance(raw_path, list) else [raw_path]
    xs = [hpf_fast(decode(r).astype(np.float32), P["hpf"]) for r in raw_list]
    x = xs[0]
    target_len = item["duration_s"]
    cap = o.get("cap", target_len * 1.5)
    if "maxlen" in P:
        cap = min(cap, P["maxlen"]) if item["gen_mode"] == "sheet" else cap
    nvar = variations_override or o.get("variations") or item["variations"]
    sheet = pp.endswith("slice") or pp == "footstep_sheet"
    if sheet:
        cands = []
        for ri, xr in enumerate(xs):
            for s, t in split_takes(xr):
                seg = trim(xr[s:t], P["tail"])
                if len(seg) < int(0.02 * SR):
                    continue
                if np.abs(seg).max() < np.abs(xr).max() * 10 ** (-12 / 20):
                    continue  # quiet fragment (tail debris), not a take
                L = len(seg) / SR
                score = -abs(np.log(max(L, 0.01) / target_len)) + 0.002 * onset_sharpness(seg)
                cands.append((score, ri, s, seg))
        takes_found = len(cands)
        if o.get("select") == "consistent":
            chosen = cands  # all steps go through the chain; the consistent N are picked below
        else:
            # best take from each raw first (diversity), then fill by score
            cands.sort(key=lambda c: -c[0])
            chosen, used = [], set()
            for c in cands:
                if c[1] not in used and len(chosen) < nvar:
                    chosen.append(c); used.add(c[1])
            for c in cands:
                if len(chosen) >= nvar:
                    break
                if not any(c is d for d in chosen):
                    chosen.append(c)
        chosen.sort(key=lambda c: (c[1], c[2]))
        segs = [c[3] for c in chosen]
        if not segs:
            segs = [trim(x, P["tail"])]
    else:
        segs = [trim(x, P["tail"])]
        takes_found = 1
    for e in o.get("extra", []):  # whole-file extra takes, sfx_std chain
        xe = hpf_fast(decode(os.path.join(ROOT, e)).astype(np.float32), P["hpf"])
        segs.append(trim(xe, P["tail"]))
        raw_list = raw_list + [os.path.join(ROOT, e)]
        takes_found += 1
    if "varispeed" in o:
        segs = [varispeed(segs[0], st) for st in o["varispeed"]]
    proc = []
    for seg in segs:
        seg = seg.copy()
        if "head" in o:
            seg = head_trim(seg, *o["head"])
        if "peak_start" in o:
            seg = start_before_peak(seg, *o["peak_start"])
        if item.get("loop"):
            seg = make_loop(seg)
        elif len(seg) / SR > cap or o.get("force_cap"):
            seg = seg[: int(cap * SR)]
            seg = fade_out(seg, o.get("cap_fade", max(P["fade"], 0.04)))
        else:
            seg = fade_out(seg, P["fade"])
        seg, lufs, tp = loudnorm(seg, target_lufs, ceiling)
        proc.append([seg, lufs])
    if o.get("min_take") and len(proc) > 1:
        keep = [p for p in proc if len(p[0]) / SR >= o["min_take"]]
        proc = keep or proc[:1]
    if o.get("select") == "consistent":
        ok = [p for p in proc if peak_ms(p[0]) <= o.get("peak_ms", 25)] or proc
        longer = [p for p in ok if len(p[0]) / SR >= o.get("min_len", 0.09)]
        ok = longer if len(longer) >= nvar else ok
        from itertools import combinations
        best = None
        tol = o.get("match_lu", 2.0)
        for comb in combinations(range(len(ok)), min(nvar, len(ok))):
            ls = [ok[k][1] for k in comb]
            # within tolerance first, then the loudest set (least attenuation), then tightest
            key = (max(0.0, max(ls) - min(ls) - tol), -sum(ls) / len(ls), max(ls) - min(ls))
            if best is None or key < best[0]:
                best = (key, comb)
        proc = [ok[k] for k in best[1]]
    if o.get("match_lu") and len(proc) > 1:
        lo = min(p[1] for p in proc)
        for p in proc:
            if p[1] - lo > o["match_lu"] * 0.8:
                p[0] = (p[0] * 10 ** ((lo + o["match_lu"] * 0.5 - p[1]) / 20)).astype(np.float32)
    multi = len(proc) > 1 or o.get("multi")
    results, names = [], []
    for k, (seg, _) in enumerate(proc):
        name = f"{item['id']}_{k + 1}.ogg" if multi else f"{item['id']}.ogg"
        seg, lufs, tp = encode_verified(seg, os.path.join(odir, name), P["q"])
        names.append(name)
        results.append(dict(file=name, dur=round(len(seg) / SR, 3), lufs=lufs, tp=tp,
                            peak_ms=peak_ms(seg), bytes=os.path.getsize(os.path.join(odir, name))))
    # remove stale variants: ONLY <id>.ogg / <id>_<n>.ogg of this exact id. A plain glob
    # "<id>_*.ogg" also matched other ids (heal -> heal_start, slash -> slash_heavy,
    # jump -> jump_slide, hit -> hit_heavy, boss_roar -> boss_roar_*), deleting them.
    stale_re = re.compile(re.escape(item["id"]) + r"(_\d+)?\.ogg")
    for old in glob.glob(os.path.join(odir, "*.ogg")):
        b = os.path.basename(old)
        if stale_re.fullmatch(b) and b not in names:
            os.unlink(old)
    tres = os.path.join(odir, f"{item['id']}.tres")
    if multi:
        write_randomizer(tres, names, cat)
    elif os.path.exists(tres):
        os.unlink(tres)
    if item.get("loop"):
        write_import_hint(os.path.join(odir, names[0]))
    meta = dict(id=item["id"], category=item["category"], preset=pp, raw=["raw/" + os.path.basename(r) for r in raw_list],
                takes_found=takes_found, wanted=item["variations"], target_lufs=target_lufs, duration_s=target_len,
                loop=bool(item.get("loop")), measured="decoded OGG", files=results)
    meta["ship"] = not o.get("hold")
    if o.get("hold"):
        meta["hold_reason"] = o["hold"]
    if o:
        meta["override"] = {k: v for k, v in o.items()}
        if "cap" in o:
            meta["cap_s"] = o["cap"]
    with open(os.path.join(odir, f"{item['id']}.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def write_randomizer(path, names, cat):
    base = f"res://assets/audio/{cat}/"
    lines = ['[gd_resource type="AudioStreamRandomizer" load_steps=%d format=3]' % (len(names) + 1), ""]
    for i, n in enumerate(names):
        lines.append(f'[ext_resource type="AudioStream" path="{base}{n}" id="{i + 1}"]')
    lines += ["", "[resource]", "playback_mode = 1", "random_pitch = 1.0", "random_volume_offset_db = 0.0",
              f"streams_count = {len(names)}"]
    for i in range(len(names)):
        lines.append(f'stream_{i}/stream = ExtResource("{i + 1}")')
        lines.append(f"stream_{i}/weight = 1.0")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def write_import_hint(ogg_path):
    """Loop flag in the committed .import (importflags.py), never a marker file."""
    import importflags
    if not importflags.set_loop(ogg_path):
        print("note: no .import yet for", os.path.basename(ogg_path), "- import, then run importflags.py --write")


def find_raw(i):
    return raws_for(i) or None


def check():
    man = load_manifest()
    bad = 0
    n = 0
    for mf in sorted(glob.glob(os.path.join(OUT, "*", "*.json"))):
        meta = json.load(open(mf))
        if meta.get("id") not in man or man[meta["id"]]["owner"] != "sfx":
            continue
        n += 1
        for r in meta["files"]:
            probs = []
            if r["lufs"] is None or r["lufs"] - meta["target_lufs"] > 1.0:
                probs.append(f"lufs {r['lufs']}")
            elif meta["target_lufs"] - r["lufs"] > 1.0:
                # SOUND_DIRECTION section 4: never limit more than 3 dB; transient clips land lower
                print("INFO", meta["id"], r["file"], f"peak-limited: {r['lufs']} LUFS (target {meta['target_lufs']}), tp {r['tp']}")
            if r["tp"] is None or r["tp"] > -1.0 + 0.05:
                probs.append(f"tp {r['tp']}")
            d = meta["duration_s"]
            hi = max(1.5 * d, meta.get("cap_s", 0)) + 0.01
            if not (0.5 * d <= r["dur"] <= hi) and not meta["loop"]:
                probs.append(f"dur {r['dur']} vs {d}")
            if probs:
                bad += 1
                print("WARN", meta["id"], r["file"], "; ".join(probs))
    print(f"checked {n} items, {bad} warnings")
    return bad


def main(argv):
    man = load_manifest()
    if "--check" in argv:
        check()
        return
    ids = [i for i, it in man.items() if it["owner"] == "sfx" and find_raw(i)] if "--all" in argv else argv
    for i in ids:
        rp = find_raw(i)
        if not rp:
            print("no raw for", i)
            continue
        m = process(man[i], rp)
        fs = ", ".join(f"{r['file']} {r['dur']}s {r['lufs']}LU tp{r['tp']}" for r in m["files"])
        print(f"{i}: takes {m['takes_found']}/{m['wanted']} -> {fs}")


if __name__ == "__main__":
    main(sys.argv[1:])
