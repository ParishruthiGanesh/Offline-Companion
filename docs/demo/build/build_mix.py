#!/usr/bin/env python3
"""Original ambient score + narration mix with speech-driven ducking.
The music is synthesised here, so it is royalty-free by construction."""
import json, sys, wave
import numpy as np

SP = sys.argv[1]
SR = 44100
tl = json.load(open(f"{SP}/work/timeline.json"))
DUR = tl["total"]
n = int(DUR * SR)
t = np.arange(n) / SR
rng = np.random.default_rng(11)


def lfo(rate, lo, hi, phase=0.0):
    return lo + (hi - lo) * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + phase))


def voice(freq, amp, rate, phase, detune=0.0015):
    """Two slightly detuned saw-ish tones -> gentle chorus width."""
    out = np.zeros(n)
    for k, w in ((1, 1.0), (2, 0.22), (3, 0.09), (4, 0.04)):
        f = freq * k
        if f > 7000:
            break
        out += w * np.sin(2 * np.pi * f * t + phase * k)
        out += w * 0.8 * np.sin(2 * np.pi * f * (1 + detune) * t + phase * k * 1.7)
    return out * amp * lfo(rate, 0.45, 1.0, phase)


# --- harmonic bed: D minor, opening up as the story moves on -----------------
bedL = (voice(73.42, 0.34, 0.021, 0.0)      # D2 root
        + voice(110.00, 0.20, 0.017, 1.1)   # A2 fifth
        + voice(146.83, 0.15, 0.013, 2.3))  # D3
bedR = (voice(73.42, 0.33, 0.019, 0.6)
        + voice(174.61, 0.15, 0.015, 0.4)   # F3 minor third
        + voice(220.00, 0.11, 0.011, 1.9))  # A3

# a quiet high shimmer that only really arrives from section 2 onward
shim = (np.sin(2 * np.pi * 587.33 * t) * 0.5 + np.sin(2 * np.pi * 880.0 * t) * 0.35
        + np.sin(2 * np.pi * 1174.66 * t) * 0.2) * lfo(0.047, 0.0, 1.0) * 0.045
arrive = np.clip((t - 22.0) / 10.0, 0, 1)
shim *= arrive

# --- one-pole lowpass with a slowly opening cutoff ---------------------------
def lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):          # vectorised-enough for 2.5 min at 44.1k
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


cut = 320 + 900 * np.clip((t - 18) / 60.0, 0, 1) + lfo(0.013, 0, 260)
try:
    from scipy.signal import lfilter          # not expected, fall back below
    raise ImportError
except ImportError:
    # cheap time-varying smoothing without a Python loop: cascade two fixed
    # filters and crossfade between them with the cutoff envelope
    def fixed_lp(x, fc):
        a = float(np.exp(-2 * np.pi * fc / SR))
        b = np.empty_like(x); acc = 0.0
        # vectorised IIR via cumulative trick is not exact; use numpy lfilter-ish
        from numpy import convolve
        # 400-tap exponential FIR approximation (plenty for a pad)
        taps = (1 - a) * a ** np.arange(1200)
        return convolve(x, taps, mode="same")
    lo_ = fixed_lp(bedL, 340); hi_ = fixed_lp(bedL, 1500)
    mixf = np.clip((cut - 340) / 1160, 0, 1)
    bedL = lo_ * (1 - mixf) + hi_ * mixf
    lo_ = fixed_lp(bedR, 340); hi_ = fixed_lp(bedR, 1500)
    bedR = lo_ * (1 - mixf) + hi_ * mixf

music = np.stack([bedL + shim * 0.8, bedR + shim], axis=1)

# --- swell at each section boundary ------------------------------------------
bounds = [tl["lines"][0]["start"]]
for a, b in zip(tl["lines"], tl["lines"][1:]):
    if b["sec"] != a["sec"]:
        bounds.append(b["start"])
env = np.ones(n)
for bt in bounds:
    i = int(bt * SR)
    w = int(3.2 * SR)
    s = max(0, i - w // 2)
    e = min(n, s + w)
    env[s:e] *= 1.0 + 0.42 * np.hanning(e - s)
music *= env[:, None]

# fade in / out
fi, fo = int(3.0 * SR), int(4.0 * SR)
music[:fi] *= np.linspace(0, 1, fi)[:, None]
music[-fo:] *= np.linspace(1, 0, fo)[:, None]
music /= max(1e-9, np.abs(music).max())

# --- narration ----------------------------------------------------------------
with wave.open(f"{SP}/work/narration.wav") as w:
    vo = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768.0
    vsr = w.getframerate()
vo = np.interp(np.arange(n) / SR, np.arange(len(vo)) / vsr, vo)   # 22.05k -> 44.1k

# --- ducking envelope straight from the narration timeline ---------------------
duck = np.ones(n)
for L in tl["lines"]:
    s = int(max(0, L["start"] - 0.35) * SR)
    e = int(min(DUR, L["start"] + L["dur"] + 0.45) * SR)
    duck[s:e] = 0.30
k = int(0.30 * SR)
duck = np.convolve(duck, np.hanning(k) / np.hanning(k).sum(), mode="same")

MUSIC_DB, VO_GAIN = -19.0, 1.0
music *= duck[:, None] * (10 ** (MUSIC_DB / 20)) * 3.4
mix = music + np.stack([vo, vo], axis=1) * VO_GAIN
mix = np.tanh(mix * 1.05) * 0.95
mix /= max(1.0, np.abs(mix).max() / 0.97)

out = f"{SP}/work/final_audio.wav"
with wave.open(out, "w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
print(f"final_audio.wav  {DUR:.2f}s  peak={np.abs(mix).max():.3f}  swells at {[round(b,1) for b in bounds]}")
