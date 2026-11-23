#!/usr/bin/env python3
"""Original vector-style illustrations for the Offline Companion demo opening.
Rendered at 2x then downsampled for clean edges. No photographic content,
no imitation of real app screens."""
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

OUT = sys.argv[1]
W, H = 2400, 1350          # final illustration size (Ken Burns headroom over 1920x1080)
S = 2                      # supersample factor
CW, CH = W * S, H * S

TEAL = (45, 212, 200)
AMBER = (255, 183, 94)


def vgrad(top, bottom):
    img = Image.new("RGB", (CW, CH))
    a = np.linspace(0, 1, CH)[:, None]
    arr = (np.array(top)[None, None, :] * (1 - a[:, :, None])
           + np.array(bottom)[None, None, :] * a[:, :, None])
    return Image.fromarray(np.repeat(arr.astype(np.uint8), CW, axis=1))


def glow(img, cx, cy, r, color, strength=0.55):
    """Soft radial light."""
    layer = Image.new("RGB", (CW, CH), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 26
    for i in range(steps, 0, -1):
        f = i / steps
        rr = r * f
        v = int(255 * (1 - f) ** 2.1)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                  fill=(color[0] * v // 255, color[1] * v // 255, color[2] * v // 255))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.10))
    return Image.blend(img, Image.fromarray(
        np.clip(np.asarray(img, float) + np.asarray(layer, float) * strength, 0, 255).astype(np.uint8)), 1.0)


def walker(d, x, y, h, color, facing=1):
    """Stylised walking figure with a shoulder bag, drawn from rounded strokes."""
    u = h / 260.0
    lw = int(19 * u)

    def L(p, q, w=lw):
        d.line([ (x + p[0]*u*facing, y + p[1]*u), (x + q[0]*u*facing, y + q[1]*u) ],
               fill=color, width=max(2, int(w)), joint="curve")

    def C(cx, cy, r):
        d.ellipse([x + (cx-r)*u*facing, y + (cy-r)*u, x + (cx+r)*u*facing, y + (cy+r)*u], fill=color)

    # back leg / arm first (depth)
    L((50, 150), (26, 198), lw*0.92)
    L((26, 198), (16, 250), lw*0.85)
    L((50, 78), (26, 124), lw*0.80)
    L((26, 124), (22, 160), lw*0.72)
    # torso
    L((50, 68), (50, 152), lw*1.45)
    # front leg
    L((50, 150), (74, 196), lw)
    L((74, 196), (82, 250), lw*0.92)
    # front arm swinging forward
    L((50, 78), (76, 118), lw*0.86)
    L((76, 118), (84, 150), lw*0.78)
    # head + hair
    C(50, 36, 21)
    C(42, 30, 23)                      # hair volume
    C(34, 56, 13)                      # ponytail
    # shoulder bag
    L((52, 74), (30, 146), lw*0.30)    # strap
    d.rounded_rectangle([x + (14)*u*facing, y + 136*u, x + (44)*u*facing, y + 176*u],
                        radius=int(9*u), fill=color)


def grain(img, amount=7):
    a = np.asarray(img, float)
    n = np.random.normal(0, amount, a.shape[:2])[:, :, None]
    return Image.fromarray(np.clip(a + n, 0, 255).astype(np.uint8))


def finish(img, name, vignette=0.55):
    y, x = np.mgrid[0:CH, 0:CW]
    nx = (x - CW/2) / (CW/2); ny = (y - CH/2) / (CH/2)
    r = np.sqrt(nx**2 + ny**2)
    mask = np.clip(1 - vignette * np.clip(r - 0.35, 0, None)**1.6, 0, 1)[:, :, None]
    img = Image.fromarray((np.asarray(img, float) * mask).astype(np.uint8))
    img = img.resize((W, H), Image.LANCZOS)
    img = grain(img)
    img.save(f"{OUT}/{name}.png")
    print("wrote", name)


# ---------------------------------------------------------------- scene 1
# Night street: a woman walking alone between pools of lamplight.
def scene1():
    img = vgrad((8, 16, 28), (26, 44, 62))
    img = glow(img, CW*0.72, CH*0.14, CW*0.42, (70, 110, 150), 0.40)   # sky haze
    d = ImageDraw.Draw(img, "RGBA")
    # distant buildings
    random.seed(7)
    bx = 0
    while bx < CW:
        bw = random.randint(int(CW*0.05), int(CW*0.11))
        bh = random.randint(int(CH*0.22), int(CH*0.46))
        d.rectangle([bx, CH*0.62 - bh, bx + bw, CH*0.66], fill=(14, 24, 36))
        for _ in range(random.randint(2, 7)):     # lit windows
            wx = random.uniform(bx + bw*0.15, bx + bw*0.8)
            wy = random.uniform(CH*0.62 - bh + 20, CH*0.60)
            d.rectangle([wx, wy, wx + 9*S, wy + 13*S],
                        fill=(255, 196, 120, random.randint(40, 150)))
        bx += bw + random.randint(6, 22)
    # road
    d.rectangle([0, CH*0.66, CW, CH], fill=(17, 27, 40))
    d.rectangle([0, CH*0.655, CW, CH*0.668], fill=(30, 46, 64))
    # lamp post
    lx = CW*0.30
    d.rectangle([lx-5*S, CH*0.20, lx+5*S, CH*0.70], fill=(10, 18, 28))
    d.ellipse([lx-26*S, CH*0.185, lx+26*S, CH*0.225], fill=(255, 210, 150))
    img = glow(img, lx, CH*0.205, CW*0.30, AMBER, 0.60)
    d = ImageDraw.Draw(img, "RGBA")
    # light pool on the ground
    d.ellipse([lx-CW*0.17, CH*0.66, lx+CW*0.17, CH*0.86], fill=(255, 180, 110, 26))
    # lamp light cone
    d.polygon([(lx-16*S, CH*0.22), (lx+16*S, CH*0.22),
               (lx+CW*0.15, CH*0.72), (lx-CW*0.15, CH*0.72)], fill=(255, 190, 120, 16))
    # long shadow + figure
    fx, fy = CW*0.55, CH*0.41
    fh = CH*0.46
    d.polygon([(fx-10*S, CH*0.875), (fx+30*S, CH*0.875),
               (fx+CW*0.20, CH*0.98), (fx+CW*0.10, CH*0.98)], fill=(0, 0, 0, 90))
    walker(d, fx, fy, fh, (6, 11, 18), facing=1)
    finish(img, "ill1_street")


# ---------------------------------------------------------------- scene 2
# Forest trail: the path forks and the trees close in.
def scene2():
    img = vgrad((10, 24, 22), (30, 52, 44))
    img = glow(img, CW*0.50, CH*0.26, CW*0.46, (120, 160, 130), 0.30)
    d = ImageDraw.Draw(img, "RGBA")
    # ground
    d.rectangle([0, CH*0.60, CW, CH], fill=(22, 38, 33))
    # the path, tapering to the horizon, forking near the top
    d.polygon([(CW*0.12, CH), (CW*0.88, CH), (CW*0.56, CH*0.605), (CW*0.45, CH*0.605)],
              fill=(86, 101, 82))
    d.polygon([(CW*0.455, CH*0.615), (CW*0.545, CH*0.615),
               (CW*0.70, CH*0.57), (CW*0.655, CH*0.566)], fill=(72, 86, 70))
    def pines(ybase, scale, color, n, seed, edges=False, clear=None):
        random.seed(seed)
        for _ in range(n):
            if edges:
                px = random.choice([random.uniform(-CW*0.06, CW*0.20),
                                    random.uniform(CW*0.80, CW*1.06)])
            elif clear:
                px = random.choice([random.uniform(-CW*0.04, CW*clear[0]),
                                    random.uniform(CW*clear[1], CW*1.04)])
            else:
                px = random.uniform(-CW*0.04, CW*1.04)
            hgt = CH * scale * random.uniform(0.75, 1.3)
            wid = hgt * 0.40
            top = ybase - hgt
            for k in range(3):                       # stacked canopy tiers
                f = 1 - k*0.26
                yy = top + hgt*0.30*k
                d.polygon([(px, yy), (px - wid*f/2, yy + hgt*0.46),
                           (px + wid*f/2, yy + hgt*0.46)], fill=color)
            d.rectangle([px-wid*0.05, ybase-hgt*0.10, px+wid*0.05, ybase], fill=color)
    pines(CH*0.64, 0.30, (26, 46, 40), 26, 3)        # far
    # mist band
    d.rectangle([0, CH*0.55, CW, CH*0.70], fill=(170, 200, 190, 26))
    pines(CH*0.74, 0.46, (16, 32, 28), 16, 11, clear=(0.33, 0.67))   # mid, path kept clear
    # figure, small, on the path
    walker(d, CW*0.500, CH*0.455, CH*0.185, (9, 18, 16), facing=1)
    pines(CH*1.06, 0.80, (7, 17, 15), 8, 23, edges=True)   # near, framing the edges only
    d.rectangle([0, CH*0.46, CW, CH*0.60], fill=(160, 195, 185, 16))
    finish(img, "ill2_trail")


# ---------------------------------------------------------------- scene 3
# The signal goes.
def scene3():
    img = vgrad((10, 14, 24), (22, 28, 44))
    img = glow(img, CW*0.5, CH*0.46, CW*0.34, (60, 90, 130), 0.34)
    d = ImageDraw.Draw(img, "RGBA")
    # fading broadcast arcs
    for i, rr in enumerate([0.16, 0.24, 0.32, 0.40, 0.48]):
        al = int(70 * (1 - i/5.0) ** 2.2)
        r = CW * rr
        d.arc([CW/2 - r, CH*0.52 - r, CW/2 + r, CH*0.52 + r],
              start=205, end=335, fill=(120, 170, 210, al), width=int(5*S))
    # phone body
    pw, ph = CW*0.115, CH*0.40
    px, py = CW/2 - pw/2, CH*0.40
    d.rounded_rectangle([px-7*S, py-7*S, px+pw+7*S, py+ph+7*S], radius=int(30*S), fill=(8, 12, 20))
    d.rounded_rectangle([px, py, px+pw, py+ph], radius=int(24*S), fill=(20, 28, 42))
    # dead signal bars on the screen
    bx, by = px + pw*0.22, py + ph*0.45
    for i in range(4):
        hgt = ph*0.045*(i+1)
        on = i == 0
        d.rounded_rectangle([bx + i*pw*0.16, by - hgt, bx + i*pw*0.16 + pw*0.10, by],
                            radius=int(4*S), fill=(90, 105, 125) if on else (44, 54, 70))
    d.line([px+pw*0.20, py+ph*0.52, px+pw*0.80, py+ph*0.28],
           fill=(214, 92, 92), width=int(7*S))
    finish(img, "ill3_nosignal", vignette=0.70)


# ---------------------------------------------------------------- scene 4
# Title card.
def scene4():
    img = vgrad((7, 18, 22), (13, 34, 40))
    img = glow(img, CW*0.5, CH*0.52, CW*0.40, TEAL, 0.30)
    d = ImageDraw.Draw(img, "RGBA")
    r = CW*0.088
    d.ellipse([CW/2-r, CH*0.50-r, CW/2+r, CH*0.50+r], outline=(45, 212, 200, 150), width=int(5*S))
    r2 = r*0.62
    d.ellipse([CW/2-r2, CH*0.50-r2, CW/2+r2, CH*0.50+r2], outline=(45, 212, 200, 90), width=int(4*S))
    r3 = r*0.30
    d.ellipse([CW/2-r3, CH*0.50-r3, CW/2+r3, CH*0.50+r3], fill=(45, 212, 200, 200))
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        d.line([CW/2 + math.cos(a)*r*1.18, CH*0.50 + math.sin(a)*r*1.18,
                CW/2 + math.cos(a)*r*1.34, CH*0.50 + math.sin(a)*r*1.34],
               fill=(45, 212, 200, 110), width=int(4*S))
    finish(img, "ill4_title", vignette=0.45)


scene1(); scene2(); scene3(); scene4()
