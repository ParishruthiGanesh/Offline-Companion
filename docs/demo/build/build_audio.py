#!/usr/bin/env python3
"""Narration timeline + SRT. Everything else in the edit syncs to timeline.json."""
import json, sys, wave, subprocess, os
import numpy as np

SP = sys.argv[1]
SR = 22050                       # piper output rate
LEAD, TAIL = 0.60, 1.80
GAP_LINE, GAP_SECTION = 0.28, 0.75

lines = json.load(open(f"{SP}/work/script.json"))


def read_wav(p):
    with wave.open(p) as w:
        assert w.getframerate() == SR, w.getframerate()
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if w.getnchannels() == 2:
            a = a.reshape(-1, 2).mean(axis=1)
    return a


track = [np.zeros(int(LEAD * SR), np.float32)]
t = LEAD
timeline = []
prev_sec = lines[0]["sec"]
for i, L in enumerate(lines):
    if i:
        g = GAP_SECTION if L["sec"] != prev_sec else GAP_LINE
        track.append(np.zeros(int(g * SR), np.float32)); t += g
    a = read_wav(f"{SP}/vo/{L['id']}.wav")
    d = len(a) / SR
    timeline.append({"id": L["id"], "sec": L["sec"], "start": round(t, 3),
                     "dur": round(d, 3), "cap": L["cap"], "srt": L["srt"]})
    track.append(a); t += d
    prev_sec = L["sec"]
track.append(np.zeros(int(TAIL * SR), np.float32)); t += TAIL

vo = np.concatenate(track)
# gentle level control: peak-normalise then a soft limiter ceiling
vo = vo / max(1e-6, np.abs(vo).max()) * 0.92
vo = np.tanh(vo * 1.08) * 0.93

out = f"{SP}/work/narration.wav"
with wave.open(out, "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((vo * 32767).astype(np.int16).tobytes())

json.dump({"total": round(t, 3), "lines": timeline}, open(f"{SP}/work/timeline.json", "w"), indent=1)


def ts(x):
    h = int(x // 3600); m = int(x % 3600 // 60); s = x % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}".replace(".", ",")


with open(f"{SP}/work/captions.srt", "w") as f:
    for n, L in enumerate(timeline, 1):
        f.write(f"{n}\n{ts(L['start'])} --> {ts(L['start'] + L['dur'])}\n{L['srt']}\n\n")

print(f"narration.wav  {t:.2f}s  ({int(t//60)}:{t%60:04.1f})")
for s in (1, 2, 3, 4):
    g = [L for L in timeline if L["sec"] == s]
    print(f"  section {s}: {g[0]['start']:6.2f}s -> {g[-1]['start']+g[-1]['dur']:6.2f}s")
