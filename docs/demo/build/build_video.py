#!/usr/bin/env python3
"""Render every beat to a 1920x1080 segment, concatenate, mux the final audio."""
import json, os, subprocess, sys, shutil

SP = sys.argv[1]
U = "/root/.claude/uploads/b832c624-7ed8-5a4a-a947-abc343a4e122"
SRC = {
    "A": f"{U}/ffddec5a-IMG_1827.MOV",
    "B": f"{U}/8a4ec540-ScreenRecording_11-04-2026_18-42-08_1.MP4",
    "C": f"{U}/4fa45ce7-ScreenRecording_11-04-2026_18-38-22_1.MP4",
    "D": f"{U}/f8c9d772-ScreenRecording_11-04-2026_18-53-17_1.MP4",
}
STILL = {"ILL1": f"{SP}/ill/ill1_street.png", "ILL2": f"{SP}/ill/ill2_trail.png",
         "ILL3": f"{SP}/ill/ill3_nosignal.png", "ILL4": f"{SP}/ill/ill4_title.png",
         "CARD_model_a": f"{SP}/cards/card_model_a.png",
         "CARD_model_b": f"{SP}/cards/card_model_b.png",
         "CARD_pairing": f"{SP}/cards/card_pairing.png",
         "CARD_limits": f"{SP}/cards/card_limits.png",
         "CARD_outro": f"{SP}/cards/card_outro.png"}
KENBURNS = {"ILL1": (1.00, 1.10, 0.0, 0.0), "ILL2": (1.09, 1.00, 0.0, 0.0),
            "ILL3": (1.00, 1.08, 0.0, 0.0), "ILL4": (1.06, 1.00, 0.0, 0.0)}
LANDSCAPE = {"A"}
FPS = 30
SEG = f"{SP}/segments"
shutil.rmtree(SEG, ignore_errors=True); os.makedirs(SEG)

tl = json.load(open(f"{SP}/work/timeline.json"))
beats_by_line = json.load(open(f"{SP}/work/beats.json"))

# flatten into an ordered beat list with exact durations derived from narration
# Each line's visuals must also cover the silence that follows it, so that the
# concatenated video stays locked to the narration timeline (0 .. tl["total"]).
L_ = tl["lines"]
spans_t = []
prev_end = 0.0
for i, L in enumerate(L_):
    end = tl["total"] if i == len(L_) - 1 else L["start"] + L["dur"]
    spans_t.append((prev_end, end))
    prev_end = end
assert abs(spans_t[-1][1] - tl["total"]) < 1e-6

plan = []
for L, (vs, ve) in zip(L_, spans_t):
    vdur = ve - vs
    bl = beats_by_line[L["id"]]
    spans = [(b[2] - b[1]) if b[0] in SRC else 1.0 for b in bl]
    total = sum(spans)
    acc = 0.0
    for i, (b, sp) in enumerate(zip(bl, spans)):
        d = round(vdur * sp / total, 3) if i < len(bl) - 1 else round(vdur - acc, 3)
        acc += d
        plan.append({"line": L["id"], "sec": L["sec"], "src": b[0], "a": b[1], "b": b[2],
                     "crop": b[3], "dur": d})
print(f"video plan total {sum(p['dur'] for p in plan):.3f}s vs audio {tl['total']:.3f}s")

sec_first = {}; sec_last = {}
for i, p in enumerate(plan):
    sec_first.setdefault(p["sec"], i); sec_last[p["sec"]] = i

FG_CX, FG_W, FG_H = 500, 700, 1004


def fit(w, h, bw, bh):
    s = min(bw / w, bh / h)
    return int(round(w * s / 2) * 2), int(round(h * s / 2) * 2)


def render(i, p):
    out = f"{SEG}/{i:03d}.mp4"
    D = p["dur"]
    land = p["src"] in STILL or p["src"] in LANDSCAPE
    mode = "full" if land else "panel"
    cap = f"{SP}/caps/{p['line']}_{mode}.png"
    fades = []
    if i == sec_first[p["sec"]]:
        fades.append("fade=t=in:st=0:d=0.30:color=black")
    if i == sec_last[p["sec"]]:
        fades.append(f"fade=t=out:st={max(0.0, D-0.30):.3f}:d=0.30:color=black")
    fade = ("," + ",".join(fades)) if fades else ""

    if p["src"] in STILL:
        img = STILL[p["src"]]
        if p["src"] in KENBURNS:
            z0, z1, _, _ = KENBURNS[p["src"]]
            N = max(2, int(D * FPS))
            zexpr = f"{z0}+({z1}-{z0})*on/{N-1}"
            vf = (f"[0:v]scale=3840:2160,"
                  f"zoompan=z='{zexpr}':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
                  f":s=1920x1080:fps={FPS},setsar=1[v]")
        else:
            vf = f"[0:v]scale=1920:1080,setsar=1,fps={FPS}[v]"
        cmd = ["ffmpeg", "-v", "error", "-y", "-loop", "1", "-framerate", str(FPS),
               "-t", f"{D:.3f}", "-i", img, "-i", cap,
               "-filter_complex", f"{vf};[v][1:v]overlay=0:0{fade},format=yuv420p[o]"]
    else:
        srcdur = p["b"] - p["a"]
        speed = D / srcdur                       # >1 = slower
        pre = f"setpts=(PTS-STARTPTS)*{speed:.6f},fps={FPS}"
        crop = ("," + p["crop"]) if p["crop"] else ""
        if land:
            vf = (f"[0:v]{pre}{crop},scale=1920:1080:force_original_aspect_ratio=increase,"
                  f"crop=1920:1080,setsar=1[v]")
        else:
            probe_w, probe_h = 1170, 2532
            if p["crop"]:
                parts = p["crop"].split("=")[1].split(":")
                probe_w, probe_h = int(parts[0]), int(parts[1])
            fw, fh = fit(probe_w, probe_h, FG_W, FG_H)
            fx, fy = FG_CX - fw // 2, 540 - fh // 2
            vf = (f"[0:v]{pre},split=2[bg][fg];"
                  f"[bg]scale=1920:-2,crop=1920:1080,scale=96:54,scale=1920:1080,"
                  f"gblur=sigma=28,colorchannelmixer=rr=0.22:gg=0.24:bb=0.30,setsar=1[bgo];"
                  f"[fg]{p['crop'] + ',' if p['crop'] else ''}scale={fw}:{fh},setsar=1[fgo];"
                  f"[bgo]drawbox=x={fx-12}:y={fy-12}:w={fw+24}:h={fh+24}:"
                  f"color=black@0.85:t=fill[bgb];"
                  f"[bgb][fgo]overlay={fx}:{fy}[v]")
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{p['a']:.3f}", "-t", f"{srcdur:.3f}",
               "-i", SRC[p["src"]], "-i", cap,
               "-filter_complex", f"{vf};[v][1:v]overlay=0:0{fade},format=yuv420p[o]"]

    cmd += ["-map", "[o]", "-an", "-t", f"{D:.3f}", "-c:v", "libx264", "-preset", "medium",
            "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS), out]
    subprocess.run(cmd, check=True)
    return out


print(f"rendering {len(plan)} beats …")
for i, p in enumerate(plan):
    render(i, p)
    print(f"  {i:03d} {p['line']} {p['src']:14s} {p['dur']:5.2f}s"
          + (f"  [{p['crop']}]" if p["crop"] else ""))

with open(f"{SEG}/list.txt", "w") as f:
    for i in range(len(plan)):
        f.write(f"file '{SEG}/{i:03d}.mp4'\n")

silent = f"{SP}/work/video_silent.mp4"
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0",
                "-i", f"{SEG}/list.txt", "-c", "copy", silent], check=True)

final = f"{SP}/out/OfflineCompanion-demo.mp4"
os.makedirs(f"{SP}/out", exist_ok=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", silent, "-i", f"{SP}/work/final_audio.wav",
                "-filter_complex",
                "[0:v]fade=t=in:st=0:d=0.8,fade=t=out:st=143.6:d=1.6[v];"
                "[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=143.4:d=1.8[a]",
                "-map", "[v]", "-map", "[a]",
                "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-pix_fmt", "yuv420p",
                "-profile:v", "high", "-level", "4.1", "-movflags", "+faststart",
                "-c:a", "aac", "-b:a", "192k", "-ar", "48000", final], check=True)
print("\nwrote", final)
