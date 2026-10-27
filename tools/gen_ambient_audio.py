#!/usr/bin/env python3
"""Generate the procedural audio used by the game (no third-party material, free to use):

- game/audio/level_complete/chime.wav    soft bell arpeggio, 2.6 s (GS-11.1: <= 3 s)
- game/audio/ambient/sea.wav             seamless 16 s sea-wave loop (GS-11.3)
- game/audio/ambient/rain.wav            seamless 16 s rain loop (GS-11.3)

Deterministic (fixed seeds). Usage: python3 tools/gen_ambient_audio.py
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 22050


def write_wav(path, x, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x / (np.max(np.abs(x)) + 1e-9) * 0.8, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def loop_crossfade(x, fade):
    """Make x loop seamlessly: blend the tail into the head."""
    head, tail = x[:fade], x[-fade:]
    t = np.linspace(0, 1, fade)
    out = x[:-fade].copy()
    out[:fade] = head * t + tail * (1 - t)
    return out


def chime():
    sr = 44100
    t = np.arange(int(sr * 2.6)) / sr
    out = np.zeros_like(t)
    notes = [523.25, 659.25, 783.99, 1046.5]          # C5 E5 G5 C6
    for k, f in enumerate(notes):
        start = 0.18 * k
        tt = np.clip(t - start, 0, None)
        env = (t >= start) * np.exp(-tt * 2.2) * (1 - np.exp(-tt * 200))
        out += env * (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2.76 * f * tt) * np.exp(-tt * 4))
    return out, sr


def sea(seconds=16, seed=1):
    rng = np.random.default_rng(seed)
    n = SR * (seconds + 2)
    noise = rng.standard_normal(n)
    brown = np.cumsum(noise)
    brown -= lowpass(brown, 0.0005)                      # remove drift
    surf = lowpass(noise, 0.08)
    t = np.arange(n) / SR
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 8.0) ** 2   # one wave every ~8 s
    x = brown / np.std(brown) * 0.6 + surf / np.std(surf) * swell
    return loop_crossfade(x, SR * 2)


def rain(seconds=16, seed=2):
    rng = np.random.default_rng(seed)
    n = SR * (seconds + 2)
    hiss = lowpass(rng.standard_normal(n), 0.35)
    hiss -= lowpass(hiss, 0.02)
    drops = np.zeros(n)
    for pos in rng.integers(0, n - 400, size=seconds * 40):
        k = np.arange(300)
        drops[pos:pos + 300] += rng.uniform(0.2, 1.0) * np.exp(-k / 40) * np.sin(2 * np.pi * rng.uniform(1500, 4000) * k / SR)
    x = hiss / np.std(hiss) * 0.7 + drops * 0.25
    return loop_crossfade(x, SR * 2)


def main():
    c, csr = chime()
    write_wav(os.path.join(ROOT, "game/audio/level_complete/chime.wav"), c, csr)
    write_wav(os.path.join(ROOT, "game/audio/ambient/sea.wav"), sea())
    write_wav(os.path.join(ROOT, "game/audio/ambient/rain.wav"), rain())
    print("ok")


if __name__ == "__main__":
    main()
