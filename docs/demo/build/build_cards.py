#!/usr/bin/env python3
"""Title/explainer cards, per-line caption overlays, and the thumbnail."""
import json, sys, os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

SP = sys.argv[1]
W, H = 1920, 1080
F = "/usr/share/fonts/opentype/inter/"
TEAL = (45, 212, 200)
WARN = (255, 176, 92)
os.makedirs(f"{SP}/cards", exist_ok=True)
os.makedirs(f"{SP}/caps", exist_ok=True)


def font(name, size):
    return ImageFont.truetype(F + name, size)


def bg(dark=(7, 16, 22), light=(14, 33, 40), tealglow=0.28):
    a = np.linspace(0, 1, H)[:, None, None]
    arr = np.array(dark)[None, None, :] * (1 - a) + np.array(light)[None, None, :] * a
    img = Image.fromarray(np.repeat(arr.astype(np.uint8), W, axis=1))
    if tealglow:
        g = Image.new("RGB", (W, H), (0, 0, 0))
        d = ImageDraw.Draw(g)
        for i in range(24, 0, -1):
            f = i / 24; r = W * 0.45 * f; v = int(255 * (1 - f) ** 2.2)
            d.ellipse([W*0.5-r, H*0.55-r, W*0.5+r, H*0.55+r],
                      fill=(TEAL[0]*v//255, TEAL[1]*v//255, TEAL[2]*v//255))
        g = g.filter(ImageFilter.GaussianBlur(70))
        img = Image.fromarray(np.clip(np.asarray(img, float) + np.asarray(g, float) * tealglow, 0, 255).astype(np.uint8))
    n = np.random.normal(0, 4, (H, W))[:, :, None]
    return Image.fromarray(np.clip(np.asarray(img, float) + n, 0, 255).astype(np.uint8)).convert("RGBA")


def centre(d, y, text, fnt, fill, spacing=12):
    for ln in text.split("\n"):
        w = d.textbbox((0, 0), ln, font=fnt)[2]
        d.text(((W - w) / 2, y), ln, font=fnt, fill=fill)
        y += fnt.size + spacing
    return y


def badge(d, text, colour=(255, 255, 255, 210), x=52, y=46, bgc=(0, 0, 0, 120)):
    f = font("Inter-SemiBold.otf", 25)
    w = d.textbbox((0, 0), text, font=f)[2]
    d.rounded_rectangle([x, y, x + w + 40, y + 50], radius=25, fill=bgc,
                        outline=(255, 255, 255, 45), width=1)
    d.text((x + 20, y + 12), text, font=f, fill=colour)


# ------------------------------------------------------------------ cards
def card_model_a():
    img = bg(); d = ImageDraw.Draw(img, "RGBA")
    centre(d, H*0.42, "Intelligence that lives\non the phone itself.",
           font("InterDisplay-SemiBold.otf", 86), (238, 250, 249), 26)
    badge(d, "ILLUSTRATION · NOT APP FOOTAGE")
    img.convert("RGB").save(f"{SP}/cards/card_model_a.png")


def card_model_b():
    img = bg(); d = ImageDraw.Draw(img, "RGBA")
    f1 = font("InterDisplay-Bold.otf", 76)
    f2 = font("Inter-Medium.otf", 36)
    f3 = font("Inter-Regular.otf", 30)
    y = centre(d, H*0.17, "Meta Llama 3.2 1B Instruct", f1, (255, 255, 255), 16)
    y = centre(d, y + 6, "GGUF · Q4_K_M · 808 MB", font("Inter-SemiBold.otf", 40), TEAL, 26)
    rows = [("Runs on", "llama.cpp via LlamaSwift — on the iPhone itself"),
            ("Chosen for", "a 1B model at 4-bit fits an iPhone 13 beside a map and Bluetooth"),
            ("Context", "2048 tokens · greedy sampling · cleared before every question"),
            ("Network", "one download during setup — then no cloud, no API key, no account")]
    y += 58
    for k, v in rows:
        d.text((W*0.17, y), k, font=font("Inter-SemiBold.otf", 32), fill=(120, 190, 185))
        d.text((W*0.17 + 210, y), v, font=f3, fill=(214, 228, 230))
        y += 74
    d.text((W*0.17, y + 40), "Practical selection under device limits — not an exhaustive benchmark.",
           font=font("Inter-Italic.otf", 27), fill=(140, 160, 165))
    badge(d, "ILLUSTRATION · NOT APP FOOTAGE")
    img.convert("RGB").save(f"{SP}/cards/card_model_b.png")


def card_pairing():
    img = bg(tealglow=0.18); d = ImageDraw.Draw(img, "RGBA")
    centre(d, H*0.13, "Pairing one trusted person", font("InterDisplay-Bold.otf", 68), (255, 255, 255), 10)
    centre(d, H*0.13 + 92, "diagram — the pairing handshake is not shown in these recordings",
           font("Inter-Italic.otf", 28), (150, 172, 176), 10)

    def phone(cx, cy, label, qr=False):
        pw, ph = 190, 380
        d.rounded_rectangle([cx-pw/2-8, cy-ph/2-8, cx+pw/2+8, cy+ph/2+8], radius=42, fill=(10, 20, 26))
        d.rounded_rectangle([cx-pw/2, cy-ph/2, cx+pw/2, cy+ph/2], radius=34, fill=(20, 36, 44))
        if qr:
            rng = np.random.default_rng(5); s = 13; o = cx-91, cy-91
            for i in range(14):
                for j in range(14):
                    if rng.random() > 0.5:
                        d.rectangle([o[0]+i*s, o[1]+j*s, o[0]+i*s+s-2, o[1]+j*s+s-2], fill=TEAL)
        else:
            d.ellipse([cx-46, cy-46, cx+46, cy+46], outline=TEAL, width=5)
            d.ellipse([cx-16, cy-16, cx+16, cy+16], fill=TEAL)
        w = d.textbbox((0, 0), label, font=font("Inter-SemiBold.otf", 30))[2]
        d.text((cx-w/2, cy+ph/2+34), label, font=font("Inter-SemiBold.otf", 30), fill=(222, 236, 238))

    phone(W*0.27, H*0.52, "shows a private QR", qr=True)
    phone(W*0.73, H*0.52, "scans it, sends a request")
    d.line([W*0.27+140, H*0.52, W*0.73-140, H*0.52], fill=(45, 212, 200, 150), width=5)
    for i, t in enumerate(["scan", "Accept", "encrypted GPS"]):
        x = W*0.36 + i*W*0.14
        tw = d.textbbox((0, 0), t, font=font("Inter-Medium.otf", 27))[2]
        d.rounded_rectangle([x-tw/2-16, H*0.615, x+tw/2+16, H*0.615+46], radius=23,
                            fill=(8, 22, 28), outline=(45, 212, 200, 120), width=2)
        d.text((x-tw/2, H*0.615+9), t, font=font("Inter-Medium.otf", 27), fill=TEAL)
    centre(d, H*0.86, "AES-GCM over Bluetooth LE · each phone opts in separately · Bluetooth range only",
           font("Inter-Regular.otf", 30), (178, 198, 202), 10)
    badge(d, "DIAGRAM · NOT APP FOOTAGE")
    img.convert("RGB").save(f"{SP}/cards/card_pairing.png")


def card_limits():
    img = bg((16, 10, 10), (34, 18, 16), tealglow=0.0); d = ImageDraw.Draw(img, "RGBA")
    centre(d, H*0.17, "What this is not", font("InterDisplay-Bold.otf", 76), (255, 255, 255), 10)
    items = ["No satellite communication", "No SOS transmission",
             "No rescue or emergency dispatch", "No guaranteed background tracking",
             "Not a promise that anyone is safe"]
    y = H*0.36
    for t in items:
        d.line([W*0.30, y+22, W*0.30+30, y+22], fill=WARN, width=5)
        d.text((W*0.30+54, y), t, font=font("Inter-Medium.otf", 44), fill=(243, 232, 228))
        y += 76
    centre(d, H*0.855, "Offline Companion is a prototype.", font("Inter-SemiBold.otf", 36), WARN, 10)
    img.convert("RGB").save(f"{SP}/cards/card_limits.png")


def card_outro():
    img = bg(tealglow=0.34); d = ImageDraw.Draw(img, "RGBA")
    centre(d, H*0.27, "Offline Companion", font("InterDisplay-Bold.otf", 104), (255, 255, 255), 10)
    centre(d, H*0.27 + 132, "Useful assistance when the internet is unavailable",
           font("Inter-Regular.otf", 40), (186, 214, 216), 10)
    r = 4
    d.rounded_rectangle([W*0.5-250, H*0.56, W*0.5+250, H*0.56+76], radius=38,
                        fill=(8, 26, 30), outline=(45, 212, 200, 160), width=2)
    t = "Built with Llama"
    tw = d.textbbox((0, 0), t, font=font("Inter-SemiBold.otf", 40))[2]
    d.text((W*0.5-tw/2, H*0.56+16), t, font=font("Inter-SemiBold.otf", 40), fill=TEAL)
    centre(d, H*0.73, "github.com/ParishruthiGanesh/Offline-Companion",
           font("Inter-Medium.otf", 34), (214, 232, 234), 10)
    centre(d, H*0.73 + 62,
           "Text: Meta Llama 3.2  ·  Photos: SmolVLM (Hugging Face)  ·  Speech: Apple  ·  Maps: MapLibre + © OpenStreetMap contributors",
           font("Inter-Regular.otf", 24), (138, 162, 166), 10)
    img.convert("RGB").save(f"{SP}/cards/card_outro.png")


# ------------------------------------------------- caption overlays per line
def wrap(d, text, fnt, maxw):
    out = []
    for para in text.split("\n"):
        cur = ""
        for word in para.split():
            trial = (cur + " " + word).strip()
            if d.textbbox((0, 0), trial, font=fnt)[2] <= maxw or not cur:
                cur = trial
            else:
                out.append(cur); cur = word
        out.append(cur)
    return out


def caption_overlay(lid, text, mode, kind):
    """mode: 'full' (lower third) or 'panel' (right side). kind: REAL / ILLUSTRATION."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind:
        col = (255, 255, 255, 215)
        bgc = (6, 26, 30, 170) if kind.startswith("ACTUAL") else (0, 0, 0, 140)
        badge(d, kind, col, x=52, y=46, bgc=bgc)
    if not text.strip():
        img.save(f"{SP}/caps/{lid}_{mode}.png"); return

    if mode == "full":
        fnt = font("Inter-SemiBold.otf", 42)
        lines = wrap(d, text, fnt, int(W * 0.74))
        lh = 58
        block = len(lines) * lh
        top = H - 108 - block
        d.rectangle([0, top - 54, W, H], fill=(0, 0, 0, 0))
        grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ga = np.zeros((H, W, 4), np.uint8)
        for yy in range(top - 70, H):
            f = min(1.0, (yy - (top - 70)) / max(1, (H - (top - 70))))
            ga[yy, :, 3] = int(185 * min(1.0, f * 1.6))
        grad = Image.fromarray(ga)
        img = Image.alpha_composite(img, grad)
        d = ImageDraw.Draw(img)
        y = top
        for ln in lines:
            w = d.textbbox((0, 0), ln, font=fnt)[2]
            d.text(((W - w) / 2 + 2, y + 2), ln, font=fnt, fill=(0, 0, 0, 170))
            d.text(((W - w) / 2, y), ln, font=fnt, fill=(255, 255, 255, 248))
            y += lh
    else:
        x0, x1 = 980, 1836
        fnt = font("Inter-SemiBold.otf", 44)
        lines = wrap(d, text, fnt, x1 - x0)
        lh = 62
        y = H / 2 - len(lines) * lh / 2
        d.rounded_rectangle([x0 - 36, y - 46, x1 + 36, y + len(lines) * lh + 40],
                            radius=26, fill=(6, 18, 24, 150))
        d.line([x0 - 36, y - 30, x0 - 30, y + len(lines) * lh + 24], fill=TEAL + (210,), width=6)
        for ln in lines:
            d.text((x0, y), ln, font=fnt, fill=(255, 255, 255, 248))
            y += lh
    img.save(f"{SP}/caps/{lid}_{mode}.png")


def thumbnail():
    import subprocess
    U = "/root/.claude/uploads/b832c624-7ed8-5a4a-a947-abc343a4e122"
    subprocess.run(["ffmpeg", "-v", "error", "-ss", "19.4", "-i",
                    f"{U}/f8c9d772-ScreenRecording_11-04-2026_18-53-17_1.MP4",
                    "-frames:v", "1", "-y", f"{SP}/work/_thumbsrc.png"], check=True)
    shot = Image.open(f"{SP}/work/_thumbsrc.png").convert("RGB")
    img = bg(tealglow=0.26).convert("RGB")
    ph = 900
    pw = int(shot.width * ph / shot.height)
    shot = shot.resize((pw, ph), Image.LANCZOS)
    px, py = 190, (H - ph) // 2
    frame = Image.new("RGB", (pw + 22, ph + 22), (12, 24, 30))
    img.paste(frame, (px - 11, py - 11)); img.paste(shot, (px, py))
    d = ImageDraw.Draw(img, "RGBA")
    x = px + pw + 110
    d.text((x, H*0.22), "Offline", font=font("InterDisplay-Bold.otf", 104), fill=(255, 255, 255))
    d.text((x, H*0.22 + 110), "Companion", font=font("InterDisplay-Bold.otf", 104), fill=(255, 255, 255))
    d.rounded_rectangle([x, H*0.52, x + 650, H*0.52 + 78], radius=39,
                        fill=(8, 28, 32), outline=(45, 212, 200, 180), width=3)
    d.text((x + 34, H*0.52 + 18), "Powered by Meta Llama 3.2", font=font("Inter-SemiBold.otf", 38), fill=TEAL)
    d.text((x, H*0.66), "Answers on the phone — in airplane mode",
           font=font("Inter-Medium.otf", 36), fill=(205, 226, 228))
    d.text((x, H*0.66 + 56), "Offline maps · compass · nearby location sharing",
           font=font("Inter-Regular.otf", 30), fill=(150, 176, 180))
    img.save(f"{SP}/work/thumbnail.png")


card_model_a(); card_model_b(); card_pairing(); card_limits(); card_outro()

LAYOUT = json.load(open(f"{SP}/work/layout.json"))
tl = json.load(open(f"{SP}/work/timeline.json"))
for L in tl["lines"]:
    _, kind = LAYOUT[L["id"]]
    # a line can mix portrait and landscape beats, so emit both layouts
    caption_overlay(L["id"], L["cap"], "full", kind)
    caption_overlay(L["id"], L["cap"], "panel", kind)
thumbnail()
print("cards, captions and thumbnail written")
