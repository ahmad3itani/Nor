#!/usr/bin/env python3
"""REDLINE music + ambience post-processor (SOUND_DIRECTION.md section 4).

Reproducible from raw downloads (<ASSETGEN_RAW>/<id>.mp3; the MP3s are kept outside the repo):
    python3 tools/assetgen/process_music_amb.py <id> [<id> ...]
    python3 tools/assetgen/process_music_amb.py --all        # every music_amb item with a raw file
    python3 tools/assetgen/process_music_amb.py --check      # QA every processed output (json meta)

Presets:
  amb_loop           stereo, HPF 30 Hz, -2 dB peaking dip @2 kHz (Q1), 2.0 s equal-power
                     tail->head crossfade (drop tail), mono fold, -26 LUFS-I, OGG q2 (BED_Q), loop.
                     Non-loop items that use this preset (thunder, pipe groan, train) are
                     one-shots: mono, trimmed, -24 LUFS, OGG q4.
  amb_oneshot_slice  sheet slicing (silence -45 dB, d 0.12) -> best N takes, mono,
                     tail kept to -70 dBFS, -24 LUFS, OGG q4, AudioStreamRandomizer .tres.
  music_loop         stereo, loop point search in the last 12 s (bar-snapped when the
                     prompt names a BPM), 1.5 s equal-power crossfade, -20 LUFS-I, OGG q3 (MUSIC_Q).
                     Rejects (flag in meta) if first/last 5 s are > 6 LU under the middle.
  music_oneshot      stereo, trim, 3 s fade-out, -20 LUFS-I, OGG q4.
Outputs assets/audio/<ambience|music>/<id>.ogg (+ .json measurements; loop=true goes in the .import).
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
# Size pass (T01, desktop/macOS zip budgets): music at ~96 kbps (q3), beds as
# mono q2. The loudness targets and loop rules are unchanged.
MUSIC_Q = 3
BED_Q = 2
BED_MONO = True


def _ff():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


FF = _ff()


def load_manifest():
    with open(os.path.join(DATA, "sound_manifest.json")) as f:
        return {i["id"]: i for i in json.load(f)}


# ---------------------------------------------------------------- io
def decode(path):
    """-> float32 array (n, 2) @44.1k."""
    cmd = [FF, "-v", "error", "-i", path, "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def write_wav(path, y):
    import wave
    y = np.atleast_2d(y.T).T if y.ndim == 1 else y
    ch = 1 if y.ndim == 1 else y.shape[1]
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def ffilter(y, af):
    """Run an ffmpeg audio filter chain over y (mono or stereo float)."""
    ch = 1 if y.ndim == 1 else y.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        p = f.name
    write_wav(p, y)
    raw = subprocess.run([FF, "-v", "error", "-i", p, "-af", af, "-ac", str(ch), "-ar", str(SR),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    os.unlink(p)
    z = np.frombuffer(raw, dtype=np.float32).copy()
    return z if ch == 1 else z.reshape(-1, ch)


def encode_ogg(y, path, q):
    ch = 1 if y.ndim == 1 else y.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        p = f.name
    write_wav(p, y)
    subprocess.run([FF, "-v", "error", "-y", "-i", p, "-c:a", "libvorbis", "-q:a", str(q),
                    "-ar", str(SR), "-ac", str(ch), path], check=True)
    os.unlink(p)


# ---------------------------------------------------------------- measurement
def ebur(y, pad_to=0.5):
    """-> dict(I, LRA, TP, Mmax) via ffmpeg ebur128 (momentary max from framelog)."""
    n = len(y)
    padn = max(0, int(pad_to * SR) - n)
    if padn:
        z = np.zeros((padn,) + y.shape[1:], dtype=np.float32)
        y = np.concatenate([y, z])
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        p = f.name
    write_wav(p, y)
    r = subprocess.run([FF, "-hide_banner", "-nostats", "-i", p, "-af",
                        "ebur128=peak=true:framelog=info", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    os.unlink(p)
    out = dict(I=None, LRA=None, TP=None, Mmax=None)
    ms = [float(m) for m in re.findall(r" M:\s*(-?[\d.]+)", r)]
    # skip first 400 ms frames (warm-up)
    ms = [m for m in ms[4:] if m > -120]
    out["Mmax"] = max(ms) if ms else None
    for line in r.splitlines()[::-1]:
        s = line.strip()
        if s.startswith("I:") and out["I"] is None:
            out["I"] = float(s.split()[1])
        elif s.startswith("LRA:") and out["LRA"] is None:
            out["LRA"] = float(s.split()[1])
        elif s.startswith("Peak:") and out["TP"] is None:
            out["TP"] = float(s.split()[1])
    return out


def seg_lufs(y, a, b):
    s, t = int(a * SR), int(b * SR)
    return ebur(y[s:t])["I"]


def soft_limit(y, ceil):
    a = np.abs(y) if y.ndim == 1 else np.abs(y).max(axis=1)
    g = np.ones_like(a)
    over = a > ceil
    g[over] = ceil / a[over]
    rel = int(0.005 * SR)
    from numpy.lib.stride_tricks import sliding_window_view
    gp = np.concatenate([np.ones(rel), g, np.ones(rel)])
    gm = sliding_window_view(gp, 2 * rel + 1).min(axis=1)
    gs = np.minimum(np.convolve(gm, np.ones(rel) / rel, mode="same"), g)
    return (y * (gs if y.ndim == 1 else gs[:, None])).astype(np.float32)


def loudnorm(y, target, ceiling=-1.0):
    m = ebur(y)
    if m["I"] is None or m["I"] < -70:
        return y, m
    gain = target - m["I"]
    over = (m["TP"] + gain) - ceiling
    if over > 0:
        if over > 3.0:  # limiter would work > 3 dB: accept lower loudness
            gain -= over - 3.0
        y = soft_limit(y * 10 ** (gain / 20), 10 ** ((ceiling - 0.3) / 20))
    else:
        y = y * 10 ** (gain / 20)
    m2 = ebur(y)
    if m2["TP"] is not None and m2["TP"] > ceiling:
        y = y * 10 ** ((ceiling - 0.1 - m2["TP"]) / 20)
        m2 = ebur(y)
    return y.astype(np.float32), m2


# ---------------------------------------------------------------- helpers
def env(y, win):
    x = y if y.ndim == 1 else y.mean(axis=1)
    n = int(win * SR)
    k = len(x) // n
    return np.sqrt((x[: k * n].reshape(k, n) ** 2).mean(1) + 1e-12)


def trim_ends(y, head_db=-50, tail_db=-60):
    a = np.abs(y) if y.ndim == 1 else np.abs(y).max(axis=1)
    pk = a.max() + 1e-12
    idx = np.where(a > pk * 10 ** (head_db / 20))[0]
    idx2 = np.where(a > pk * 10 ** (tail_db / 20))[0]
    if len(idx) == 0:
        return y
    return y[idx[0]: idx2[-1] + 1]


def fade(y, fin=0.0, fout=0.0):
    y = y.copy()
    for sec, head in ((fin, True), (fout, False)):
        f = min(len(y), int(sec * SR))
        if f > 1:
            c = np.sin(np.linspace(0, np.pi / 2, f)) ** 2
            c = c if head else c[::-1]
            if y.ndim == 2:
                c = c[:, None]
            if head:
                y[:f] *= c
            else:
                y[-f:] *= c
    return y


def xfade_loop(y, head_len_idx, cut_idx, L):
    """Loop = y[head:cut]; the audio after cut (y[cut:cut+L]) fades out over the
    loop head, so playback end->start continues exactly into y[cut]."""
    t = np.linspace(0, np.pi / 2, L)
    fi, fo = np.sin(t), np.cos(t)
    if y.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    body = y[head_len_idx:cut_idx].copy()
    tail = y[cut_idx: cut_idx + L]
    body[:L] = body[:L] * fi + tail * fo
    return body


def zero_cross_cut(y, target, span):
    """Nearest index c in [target-span, target] (c + crossfade must stay inside the file)
    where every channel crosses zero on a rising slope: y[c-1] < 0 <= y[c]. Falls back to
    the index with the smallest max-channel |step| + |level| if no common crossing exists."""
    Y = y if y.ndim == 2 else y[:, None]
    lo = max(1, target - span)
    idx = np.arange(lo, target + 1)
    rising = np.all((Y[idx - 1] < 0) & (Y[idx] >= 0), axis=1)
    if rising.any():
        c = idx[rising]
        return int(c[np.argmin(np.abs(c - target))])
    cost = np.abs(Y[idx] - Y[idx - 1]).max(axis=1) + np.abs(Y[idx]).max(axis=1)
    return int(idx[np.argmin(cost)])


def decoded_seam(ogg):
    """Seam metrics on the DECODED OGG (what Godot plays): wrap step vs in-file step
    percentiles, 20 ms RMS delta across the wrap, integrated LUFS, mono drop."""
    z = decode(ogg)
    d = np.abs(np.diff(z, axis=0)).max(axis=1)
    w = float(np.abs(z[0] - z[-1]).max())
    n = int(0.02 * SR)
    a = np.sqrt((z[-n:] ** 2).mean() + 1e-12)
    b = np.sqrt((z[:n] ** 2).mean() + 1e-12)
    return dict(wrap_step=round(w, 5), p99_step=round(float(np.percentile(d, 99)), 5),
                p999_step=round(float(np.percentile(d, 99.9)), 5),
                wrap_rank=round(float((d < w).mean()), 4),
                seam_rms_db=round(float(abs(20 * np.log10(a / b))), 2),
                lufs=ebur(z)["I"], mono_drop=mono_drop(z))


def seam_check(y):
    """Loop wrap check. Returns (rms_db, dc, jump):
    rms_db = |RMS(last 20 ms) - RMS(first 20 ms)| in dB,
    dc     = max |channel mean|,
    jump   = sample step across the wrap / 99.9th percentile of in-file sample steps
             (< 1.0 means the wrap is no bigger than an ordinary sample step: no click)."""
    n = int(0.02 * SR)
    a = np.sqrt((y[-n:] ** 2).mean() + 1e-12)
    b = np.sqrt((y[:n] ** 2).mean() + 1e-12)
    d = np.abs(np.diff(y, axis=0))
    ref = np.percentile(d, 99.9) + 1e-9
    jump = float(np.abs(y[0] - y[-1]).max() / ref)
    return (round(float(abs(20 * np.log10(a / b))), 2), round(float(np.abs(y.mean(axis=0)).max()), 5),
            round(jump, 3))


def mono_drop(y):
    if y.ndim == 1:
        return 0.0
    st = ebur(y)["I"]
    mo = ebur((y[:, 0] + y[:, 1]) * 0.5)["I"]
    # ebur128 of a mono file is played on one channel (-3 dB vs dual mono): compensate
    return round(float(st - (mo + 3.01)), 2)


def band_spec(y, a, n):
    x = y[a:a + n]
    x = x if x.ndim == 1 else x.mean(axis=1)
    sp = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    edges = np.geomspace(40, 12000, 25)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    v = np.array([sp[(f >= edges[i]) & (f < edges[i + 1])].mean() + 1e-9 for i in range(24)])
    v = np.log(v)
    return (v - v.mean()) / (v.std() + 1e-9)


HOP = 0.01


def flux(y):
    """Onset strength (half-wave rectified spectral flux), 10 ms hop, 40 ms frames."""
    x = y if y.ndim == 1 else y.mean(axis=1)
    h, n = int(HOP * SR), int(0.04 * SR)
    k = (len(x) - n) // h
    idx = np.arange(n)[None, :] + h * np.arange(k)[:, None]
    S = np.log1p(np.abs(np.fft.rfft(x[idx] * np.hanning(n), axis=1)))
    f = np.maximum(np.diff(S, axis=0), 0).sum(axis=1)
    return np.concatenate([[0], f])


def _z(v):
    return (v - v.mean()) / (v.std() + 1e-9)


def find_loop_cut(y, start_max, bpm, xf):
    """Search (start, cut) with start in [0, start_max] and cut in [N-12 s, N-xf]
    so that the audio after cut matches the audio after start (the crossfade
    region). Coarse grid (bars if a BPM is known, else 0.25 s), then a fine
    +-250 ms onset-flux alignment of cut. Returns (score, start, cut, flux_corr,
    spec_corr, level_jump_db)."""
    N = len(y)
    fl = flux(y)
    W = int(4.0 / HOP)
    lvl = 20 * np.log10(env(y, 0.5))
    def win_lvl(i):
        j = int(i / SR / 0.5)
        return lvl[j:j + 6].mean() if j < len(lvl) else lvl[-1]
    step = 4 * 60.0 / bpm * SR if bpm else 0.25 * SR
    starts = [int(i * step) for i in range(int(start_max / step) + 1)]
    lo, hi = max(int(20 * SR), N - int(12 * SR)), N - int((xf + 0.3) * SR)
    best = None
    for st in starts:
        ref = fl[st // int(HOP * SR): st // int(HOP * SR) + W]
        if len(ref) < W:
            continue
        refz = _z(ref)
        ref_sp = band_spec(y, st, int(0.5 * SR))
        k0 = int(np.ceil((lo - st) / step))
        c = st + k0 * step
        while c < hi:
            ci = int(c)
            # fine align: +-250 ms
            fi0 = ci // int(HOP * SR)
            bestd, bestcorr = 0, -9
            for d in range(-25, 26):
                seg = fl[fi0 + d: fi0 + d + W]
                if len(seg) < W // 2:
                    continue
                cc = float(np.dot(_z(seg), refz[: len(seg)]) / len(seg))
                if cc > bestcorr:
                    bestcorr, bestd = cc, d
            cf = ci + bestd * int(HOP * SR)
            if cf + int(xf * SR) >= N:
                c += step
                continue
            spc = float(np.dot(band_spec(y, cf, int(0.5 * SR)), ref_sp) / 24)
            lj = abs(win_lvl(cf) - win_lvl(st))
            score = bestcorr + 0.5 * spc - 0.15 * lj + 0.002 * (cf - st) / SR
            if best is None or score > best[0]:
                best = (score, st, cf, bestcorr, spc, lj)
            c += step
    return best


# ---------------------------------------------------------------- presets
def split_takes(x, thr=-45.0, min_sil=0.12):
    e = 20 * np.log10(env(x, 0.01))
    e -= e.max()
    loud = e > thr
    n = int(0.01 * SR)
    minsil = int(min_sil / 0.01)
    takes, start, sil = [], None, 0
    for i, l in enumerate(loud):
        if l:
            start = i if start is None else start
            sil = 0
        elif start is not None:
            sil += 1
            if sil >= minsil:
                takes.append((start * n, (i - sil + 1) * n))
                start, sil = None, 0
    if start is not None:
        takes.append((start * n, (len(loud) - sil) * n))
    return [(a, min(len(x), b + int(0.1 * SR))) for a, b in takes if (b - a) > 0.03 * SR]


def write_randomizer(path, names, cat):
    base = f"res://assets/audio/{cat}/"
    lines = ['[gd_resource type="AudioStreamRandomizer" load_steps=%d format=3]' % (len(names) + 1), ""]
    for i, n in enumerate(names):
        lines.append(f'[ext_resource type="AudioStream" path="{base}{n}" id="{i + 1}"]')
    lines += ["", "[resource]", "playback_mode = 1", "random_pitch = 1.0",
              f"streams_count = {len(names)}"]
    for i in range(len(names)):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def write_loop_hint(ogg):
    """loop=true / loop_offset=0 live in the committed .import (importflags.py); a
    brand-new file gets them after `godot --headless --import` + importflags.py --write."""
    import importflags
    if not importflags.set_loop(ogg):
        print("note: no .import yet for", os.path.basename(ogg), "- import, then run importflags.py --write")


def process(item, raw):
    pp, iid = item["post_process"], item["id"]
    cat = "music" if item["category"] == "music" else "ambience"
    odir = os.path.join(OUT, cat)
    os.makedirs(odir, exist_ok=True)
    y = decode(raw)
    meta = dict(id=iid, category=item["category"], preset=pp, raw="raw/" + os.path.basename(raw),
                raw_dur=round(len(y) / SR, 2), loop=bool(item.get("loop")), flags=[])
    files = []

    if pp == "amb_loop" and item.get("loop"):
        y = ffilter(y, "highpass=f=30:poles=2,equalizer=f=2000:t=q:w=1:g=-2")
        if BED_MONO:  # fold before the loop cut, so the crossfade and the seam are measured on what ships
            y = ((y[:, 0] + y[:, 1]) * 0.5).astype(np.float32)
            meta["mono"] = True
        L = int(2.0 * SR) if len(y) > 8 * SR else int(min(1.0, len(y) / SR / 4) * SR)
        # loop body = y[0:cut] with y[cut:cut+L] crossfaded into the head. The wrap plays
        # y[cut-1] -> y[cut]; put cut on a common rising zero crossing of both channels
        # within 10 ms of N-L so the wrap step is as small as an ordinary sample step.
        cut = zero_cross_cut(y, len(y) - L, int(0.010 * SR))
        meta["loop_cut_s"] = round(cut / SR, 4)
        y = xfade_loop(y, 0, cut, L)
        for _ in range(4 if y.ndim == 2 else 0):  # mono-safety, same rule as music
            if mono_drop(y) < 2.5:
                break
            mid_, side = (y[:, 0] + y[:, 1]) / 2, (y[:, 0] - y[:, 1]) / 2 * 0.75
            y = np.stack([mid_ + side, mid_ - side], axis=1).astype(np.float32)
            meta["width_scale"] = round(meta.get("width_scale", 1.0) * 0.75, 3)
        y, m = loudnorm(y, -26)
        ogg = os.path.join(odir, iid + ".ogg")
        encode_ogg(y, ogg, BED_Q)
        write_loop_hint(ogg)
        seam, dc, jump = seam_check(y)
        dq = decoded_seam(ogg)
        files.append(dict(file=iid + ".ogg", dur=round(len(y) / SR, 2), lufs=m["I"], tp=m["TP"],
                          lra=m["LRA"], mmax_minus_i=round(m["Mmax"] - m["I"], 1) if m["Mmax"] else None,
                          seam_db=seam, dc=dc, wrap_jump=jump, mono_drop=mono_drop(y), bytes=os.path.getsize(ogg),
                          decoded=dq))
        if dq["wrap_step"] > dq["p99_step"]:
            meta["flags"].append("decoded wrap step > p99 of in-file steps (click risk)")
        if files[-1]["mmax_minus_i"] and files[-1]["mmax_minus_i"] > 8:
            meta["flags"].append("event louder than bed +8 LU")
        meta["target_lufs"] = -26

    elif pp == "amb_loop":  # non-loop ambience one-shot (thunder, pipe groan, train pass)
        x = (y[:, 0] + y[:, 1]) * 0.7071
        x = ffilter(x, "highpass=f=30:poles=2")
        x = trim_ends(x, -50, -70)
        cap = item["duration_s"] * 1.5
        if len(x) > cap * SR:
            x = x[: int(cap * SR)]
        x = fade(x, 0.002, 0.3)
        x, m = loudnorm(x, -24)
        ogg = os.path.join(odir, iid + ".ogg")
        encode_ogg(x, ogg, 4)
        files.append(dict(file=iid + ".ogg", dur=round(len(x) / SR, 2), lufs=m["I"], tp=m["TP"],
                          bytes=os.path.getsize(ogg)))
        meta["target_lufs"] = -24

    elif pp == "amb_oneshot_slice":
        x = (y[:, 0] + y[:, 1]) * 0.7071
        x = ffilter(x, "highpass=f=35:poles=2")
        # -35 dB / 80 ms separates close drips better than -45 / 120 ms (tails overlap);
        # takes whose peak is > 20 dB under the loudest are dropped (noise when normalized)
        spans = split_takes(x, thr=-35.0, min_sil=0.08)
        pk = max(np.abs(x[a:b]).max() for a, b in spans)
        spans = [(a, b) for a, b in spans if np.abs(x[a:b]).max() > pk * 0.1]
        tgt = item["duration_s"]
        cands = []
        for s, t in spans:
            seg = trim_ends(x[s:t], -50, -70)
            Ls = len(seg) / SR
            if Ls < 0.03:
                continue
            onset = int(np.argmax(env(seg, 0.002)))
            cands.append((-abs(np.log(Ls / tgt)) - 0.002 * onset, s, seg))
        meta["takes_found"] = len(cands)
        cands.sort(key=lambda c: -c[0])
        chosen = sorted(cands[: item["variations"]], key=lambda c: c[1]) or [(0, 0, trim_ends(x))]
        names = []
        for k, (_, _, seg) in enumerate(chosen):
            seg = seg[: int(tgt * 1.5 * SR)]
            seg = fade(seg, 0.0, 0.15)
            seg, m = loudnorm(seg, -24)
            name = f"{iid}_{k + 1}.ogg" if len(chosen) > 1 else f"{iid}.ogg"
            encode_ogg(seg, os.path.join(odir, name), 4)
            names.append(name)
            files.append(dict(file=name, dur=round(len(seg) / SR, 3), lufs=m["I"], tp=m["TP"],
                              bytes=os.path.getsize(os.path.join(odir, name))))
        if len(names) > 1:
            write_randomizer(os.path.join(odir, iid + ".tres"), names, "ambience")
        meta["target_lufs"] = -24

    elif pp in ("music_loop", "music_oneshot"):
        y = trim_ends(y, -45, -60)
        N = len(y)
        mid = ebur(y[int(N * 0.3): int(N * 0.7)])["I"]
        head = seg_lufs(y, 0, 5)
        tail = seg_lufs(y, N / SR - 5, N / SR)
        meta.update(mid_lufs=mid, head_lufs=head, tail_lufs=tail)
        if pp == "music_loop":
            bpm = None
            mb = re.search(r"(\d{2,3}) BPM", item["prompt"])
            if mb:
                bpm = float(mb.group(1))
            start_max = 12.0 * SR
            if head is not None and mid is not None and mid - head > 6:
                meta["flags"].append(f"intro {mid - head:.1f} LU quieter than middle; loop start searched past it")
                e = env(y, 0.5)
                lv = 20 * np.log10(e) - (20 * np.log10(np.median(e)))
                start_max = max(start_max, (int(np.argmax(lv > -4)) + 8) * 0.5 * SR)
            xf = 1.5
            N_eff = N
            if tail is not None and mid is not None and mid - tail > 6:
                meta["flags"].append(f"outro {mid - tail:.1f} LU quieter; loop end moved earlier")
                e = env(y, 0.5)
                lv = 20 * np.log10(e) - (20 * np.log10(np.median(e)))
                ok = np.where(lv > -4)[0]
                N_eff = min(N, (ok[-1] + 1) * int(0.5 * SR) + int(xf * SR) + 1)
            score, start, cut, corr, spc, lvl = find_loop_cut(y[:N_eff], start_max, bpm, xf)
            L = int(xf * SR)
            y2 = xfade_loop(y, start, cut, L)
            meta.update(bpm=bpm, loop_start_s=round(start / SR, 3), loop_cut_s=round(cut / SR, 3),
                        loop_score=round(score, 3), env_corr=round(corr, 3), spec_corr=round(spc, 3),
                        level_jump_db=round(lvl, 2))
        else:
            y2 = fade(y, 0.0, 3.0)
        y2 = ffilter(y2, "highpass=f=25:poles=2")
        # mono-safety: narrow the side signal until the fold-down drop is < 2.5 dB
        for _ in range(4):
            if mono_drop(y2) < 2.5:
                break
            mid_, side = (y2[:, 0] + y2[:, 1]) / 2, (y2[:, 0] - y2[:, 1]) / 2 * 0.75
            y2 = np.stack([mid_ + side, mid_ - side], axis=1).astype(np.float32)
            meta.setdefault("width_scale", 1.0)
            meta["width_scale"] = round(meta["width_scale"] * 0.75, 3)
        if ebur(y2)["LRA"] > 10:
            y2 = ffilter(y2, "acompressor=threshold=0.06:ratio=2:attack=200:release=1500:makeup=1")
            meta["flags"].append("gentle compression for LRA <= 10")
        y2, m = loudnorm(y2, -20)
        ogg = os.path.join(odir, iid + ".ogg")
        encode_ogg(y2, ogg, MUSIC_Q)
        if pp == "music_loop":
            write_loop_hint(ogg)
        seam, dc, jump = seam_check(y2)
        files.append(dict(file=iid + ".ogg", dur=round(len(y2) / SR, 2), lufs=m["I"], tp=m["TP"],
                          lra=m["LRA"], seam_db=seam, dc=dc, wrap_jump=jump, mono_drop=mono_drop(y2),
                          bytes=os.path.getsize(ogg)))
        n2 = len(y2) / SR
        fin = dict(head=seg_lufs(y2, 0, 5), mid=ebur(y2[int(len(y2) * .3):int(len(y2) * .7)])["I"],
                   tail=seg_lufs(y2, n2 - 5, n2))
        files[-1]["head_mid_tail_lufs"] = [fin["head"], fin["mid"], fin["tail"]]
        if fin["mid"] - min(fin["head"], fin["tail"]) > 6:
            meta["flags"].append("REJECT: first/last 5 s > 6 LU under middle")
        if m["LRA"] and m["LRA"] > 10:
            meta["flags"].append(f"LRA {m['LRA']} > 10")
        meta["target_lufs"] = -20
    else:
        raise SystemExit(f"unknown preset {pp}")

    meta["files"] = files
    with open(os.path.join(odir, iid + ".json"), "w") as f:
        json.dump(meta, f, indent=1, default=float)
    return meta


def find_raw(i):
    c = [p for p in glob.glob(os.path.join(RAW, i + ".*")) if not p.endswith(".json")]
    return c[0] if c else None


def check():
    bad = 0
    for mf in sorted(glob.glob(os.path.join(OUT, "music", "*.json")) + glob.glob(os.path.join(OUT, "ambience", "*.json"))):
        m = json.load(open(mf))
        for f in m["files"]:
            p = os.path.join(os.path.dirname(mf), f["file"])
            # quieter than target is allowed when the -1 dBTP ceiling would need > 3 dB limiting
            lvl_ok = f["lufs"] is not None and (abs(f["lufs"] - m["target_lufs"]) <= 1.0
                                                or (f["lufs"] < m["target_lufs"] and f["tp"] >= -1.6))
            ok = os.path.exists(p) and lvl_ok \
                and f["tp"] is not None and f["tp"] <= -0.9
            if m.get("loop"):
                ok = ok and f.get("wrap_jump", 0) < 1.0 and f.get("dc", 0) < 0.01
                if m["category"] != "music":  # beds: 20 ms RMS match too
                    ok = ok and f.get("seam_db", 0) < 3
            if any(fl.startswith("REJECT") for fl in m.get("flags", [])):
                ok = False
            if "mono_drop" in f:
                ok = ok and f["mono_drop"] < 3
            bad += not ok
            print(("OK  " if ok else "BAD ") + f"{m['id']:<24} {f['file']:<28} {f['dur']:>7}s "
                  f"I={f['lufs']} TP={f['tp']} LRA={f.get('lra')} seam={f.get('seam_db')} jump={f.get('wrap_jump')} mono={f.get('mono_drop')} "
                  f"{'; '.join(m.get('flags', []))}")
    print("FAIL" if bad else "ALL OK", bad)
    return bad


def main(argv):
    if "--check" in argv:
        sys.exit(1 if check() else 0)
    man = load_manifest()
    ids = [i for i, v in man.items() if v["owner"] == "music_amb"] if "--all" in argv else argv
    for i in ids:
        raw = find_raw(i)
        if not raw:
            print("skip (no raw)", i)
            continue
        m = process(man[i], raw)
        print(json.dumps(m, default=float))


if __name__ == "__main__":
    main(sys.argv[1:])
