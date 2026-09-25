#!/usr/bin/env python3
"""Generates the notification sounds: Psst/psst.wav, a soft whispered "psst",
plus the Psst+ variants psst-soft.wav (quieter, slower) and psst-quick.wav.

Filtered noise only (no recording, no licences): a short breathy "p", a
rising "ss", and a light "t". About 0.55 s, 16-bit mono PCM, which iOS accepts
for notification sounds (they must be under 30 s).

    python3 scripts/make_psst_sound.py
"""
import math
import pathlib
import random
import struct
import wave

RATE = 44_100
random.seed(7)  # the same file every run


def bandpass(samples, centre, q):
    """RBJ biquad band-pass (constant 0 dB peak). `centre` may be a function of time."""
    out, x1 = [], 0.0
    x2 = y1 = y2 = 0.0
    for i, x in enumerate(samples):
        f = centre(i / RATE) if callable(centre) else centre
        w = 2 * math.pi * f / RATE
        alpha = math.sin(w) / (2 * q)
        b0, b2 = alpha, -alpha
        a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


def envelope(t):
    """Breathy p (0–0.05 s), gap, rising ss (0.09–0.43 s), soft t (0.46–0.5 s)."""
    if t < 0.05:
        return 0.55 * math.sin(math.pi * t / 0.05)
    if 0.09 <= t < 0.43:
        u = (t - 0.09) / 0.34
        return min(1.0, u / 0.25) * (1 - max(0.0, (u - 0.7) / 0.3)) * 0.9
    if 0.46 <= t < 0.50:
        return 0.45 * math.sin(math.pi * (t - 0.46) / 0.04)
    return 0.0


def centre(t):
    if t < 0.05:
        return 1_800
    if t < 0.43:
        return 5_200 + 1_800 * min(1.0, (t - 0.09) / 0.2)
    return 4_200


def render(filename, stretch=1.0, level=0.6, q=1.4, seed=7):
    random.seed(seed)
    length = int(RATE * 0.56 * stretch)
    noise = [random.uniform(-1, 1) for _ in range(length)]
    shaped = [n * envelope(i / RATE / stretch) for i, n in enumerate(noise)]
    filtered = bandpass(shaped, lambda t: centre(t / stretch), q=q)
    peak = max(abs(s) for s in filtered) or 1
    gain = level / peak  # leave headroom; notification sounds shouldn't be loud
    path = pathlib.Path(__file__).resolve().parents[1] / "Psst" / filename
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in filtered))
    print(f"wrote {path} ({length / RATE:.2f} s)")


render("psst.wav")
render("psst-soft.wav", stretch=1.35, level=0.35, q=1.0, seed=11)
render("psst-quick.wav", stretch=0.7, level=0.6, q=1.8, seed=3)
