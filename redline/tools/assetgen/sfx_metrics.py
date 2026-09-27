#!/usr/bin/env python3
"""Acceptance metrics for SFX takes (sound director checks).

    python3 tools/assetgen/sfx_metrics.py assets/audio/sfx/hit_1.ogg [...]   # prints one JSON line per file

peak_ms      time of the 1 ms-window RMS peak
attack_ms    time from first sample above peak-40 dB to the peak window
first10_db   RMS of the first 10 ms relative to the peak 10 ms window
after200_db  RMS of everything after 200 ms relative to the peak 10 ms window
first100_db / last100_db   RMS of first / last 100 ms (dBFS)
centroid_hz  spectral centroid (energy weighted, whole clip)
lufs, tp     ebur128 (padded to 0.5 s) of the DECODED file
"""
import json, os, subprocess, sys, tempfile
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import process_sfx as P  # noqa: E402

SR = P.SR


def rms_db(x):
    return float(20 * np.log10(np.sqrt((x ** 2).mean() + 1e-12) + 1e-12)) if len(x) else -120.0


def metrics(x):
    n1 = int(0.001 * SR)
    k = len(x) // n1
    e1 = np.sqrt((x[: k * n1].reshape(k, n1) ** 2).mean(1) + 1e-12)
    pk_i = int(np.argmax(e1))
    e10, n10 = P.env_db(x, 0.01)
    pk10 = float(e10.max())
    a = np.abs(x)
    on = np.where(a > a.max() * 10 ** (-40 / 20))[0]
    onset = on[0] if len(on) else 0
    sp = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    cen = float((sp * f).sum() / (sp.sum() + 1e-12))
    h = int(0.1 * SR)
    return dict(dur=round(len(x) / SR, 3), peak_ms=round(pk_i + 0.5, 1),
                attack_ms=round(max(0.0, (pk_i * n1 - onset) / SR * 1000), 1),
                first10_db=round(rms_db(x[: int(0.01 * SR)]) - pk10, 1),
                after200_db=round(rms_db(x[int(0.2 * SR):]) - pk10, 1),
                first100_db=round(rms_db(x[:h]), 1), last100_db=round(rms_db(x[-h:]), 1),
                centroid_hz=int(cen))


def decode_mono(path):
    cmd = [P.FF, "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).copy()


def file_metrics(path):
    x = decode_mono(path)
    m = metrics(x)
    m["lufs"], m["tp"] = P.measure(x)
    return m


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(os.path.basename(p), json.dumps(file_metrics(p)))
