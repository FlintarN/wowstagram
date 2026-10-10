# Wowstagram's own art, white on transparent so the addon can colour it:
# line icons (64x64), the rounded button shape (Pill, 128x64, drawn as three
# slices so it stretches), a filled circle, and the story rings (128x128).
#   python dev/make_art.py
import math, os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "Art")
K = 4  # supersampling
W = (255, 255, 255, 255)


def canvas(w=64, h=64):
    img = Image.new("RGBA", (w * K, h * K), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name, w=64, h=64):
    img.resize((w, h), Image.LANCZOS).save(os.path.join(ART, name + ".tga"))


def P(*xy):  # 64-unit coordinates -> supersampled pixels
    return [v * K for v in xy]


LINE = 5 * K  # stroke width


def heart_points(scale, cx, cy):
    pts = []
    for i in range(360):
        t = math.radians(i)
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts


def heart(outline):
    img, d = canvas()
    s = 64 * K
    d.polygon(heart_points(s / 36, s / 2, s / 2 - s * 0.02), fill=W)
    if outline:
        d.polygon(heart_points(s / 36 * 0.74, s / 2, s / 2 - s * 0.03), fill=(0, 0, 0, 0))
    return img


def bubble():
    img, d = canvas()
    d.ellipse(P(7, 7, 57, 52), outline=W, width=LINE)
    d.polygon(P(12, 44, 6, 59, 24, 51), fill=W)
    return img


def home(fill):
    img, d = canvas()
    roof = P(6, 30, 32, 7, 58, 30)
    d.line(roof, fill=W, width=LINE, joint="curve")
    if fill:
        d.polygon(P(13, 27, 32, 11, 51, 27, 51, 57, 13, 57), fill=W)
    else:
        d.line(P(13, 27, 13, 57, 51, 57, 51, 27), fill=W, width=LINE, joint="curve")
        d.rectangle(P(27, 40, 37, 57), outline=W, width=LINE)
    return img


def plus():
    img, d = canvas()
    d.rounded_rectangle(P(7, 7, 57, 57), radius=12 * K, outline=W, width=LINE)
    d.line(P(32, 19, 32, 45), fill=W, width=LINE)
    d.line(P(19, 32, 45, 32), fill=W, width=LINE)
    return img


def bookmark(fill):
    img, d = canvas()
    pts = P(15, 7, 49, 7, 49, 57, 32, 43, 15, 57)
    if fill:
        d.polygon(pts, fill=W)
    else:
        d.line(pts + pts[:2], fill=W, width=LINE, joint="curve")
    return img


def user():
    img, d = canvas()
    d.ellipse(P(20, 6, 44, 30), outline=W, width=LINE)
    d.arc(P(8, 34, 56, 82), 180, 360, fill=W, width=LINE)
    return img


def gear():
    img, d = canvas()
    c = 32 * K
    for i in range(8):
        a = math.radians(i * 45)
        x, y = c + math.cos(a) * 22 * K, c + math.sin(a) * 22 * K
        d.ellipse([x - 5 * K, y - 5 * K, x + 5 * K, y + 5 * K], fill=W)
    d.ellipse(P(13, 13, 51, 51), fill=W)
    d.ellipse(P(24, 24, 40, 40), fill=(0, 0, 0, 0))
    return img


def dots():
    img, d = canvas()
    for x in (12, 32, 52):
        d.ellipse(P(x - 5, 27, x + 5, 37), fill=W)
    return img


def grid():
    img, d = canvas()
    d.rectangle(P(7, 7, 57, 57), outline=W, width=LINE)
    for v in (24, 40):
        d.line(P(v, 7, v, 57), fill=W, width=LINE - K)
        d.line(P(7, v, 57, v), fill=W, width=LINE - K)
    return img


def close():
    img, d = canvas()
    d.line(P(12, 12, 52, 52), fill=W, width=LINE)
    d.line(P(52, 12, 12, 52), fill=W, width=LINE)
    return img


def chevron(right):
    img, d = canvas()
    pts = P(24, 12, 44, 32, 24, 52) if right else P(40, 12, 20, 32, 40, 52)
    d.line(pts, fill=W, width=LINE + K, joint="curve")
    return img


def shield():
    img, d = canvas()
    pts = P(32, 6, 54, 14, 52, 36, 32, 58, 12, 36, 10, 14)
    d.line(pts + pts[:2], fill=W, width=LINE, joint="curve")
    return img


def circle():
    img, d = canvas()
    d.ellipse(P(1, 1, 63, 63), fill=W)
    return img


def pill():
    img, d = canvas(128, 64)
    d.rounded_rectangle([0, 0, 128 * K - 1, 64 * K - 1], radius=32 * K, fill=W)
    return img


def rounded():
    img, d = canvas()
    d.rounded_rectangle([0, 0, 64 * K - 1, 64 * K - 1], radius=16 * K, fill=W)
    return img


def red_button():
    # Like WoW's red close button: a dark red square, gold rim.
    s = 64 * K
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2 * K, 2 * K, s - 2 * K, s - 2 * K], radius=9 * K, fill=(20, 8, 4, 255))
    d.rounded_rectangle([5 * K, 5 * K, s - 5 * K, s - 5 * K], radius=7 * K, fill=(214, 168, 52, 255))
    inner = [9 * K, 9 * K, s - 9 * K, s - 9 * K]
    grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(inner[1], inner[3]):
        t = (y - inner[1]) / (inner[3] - inner[1])
        c = (int(186 - 80 * t), int(32 - 20 * t), int(22 - 14 * t), 255)
        gd.line([(inner[0], y), (inner[2], y)], fill=c)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(inner, radius=4 * K, fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def window_max():
    img, d = canvas()
    d.rectangle(P(14, 14, 50, 50), outline=W, width=LINE)
    d.rectangle(P(14, 14, 50, 22), fill=W)
    return img


def window_restore():
    img, d = canvas()
    # The back window, then the front one over it.
    d.line(P(24, 18, 24, 10, 54, 10, 54, 40, 46, 40), fill=W, width=LINE - K, joint="curve")
    d.rectangle(P(10, 24, 40, 54), fill=(0, 0, 0, 0))
    d.rectangle(P(10, 24, 40, 54), outline=W, width=LINE - K)
    d.rectangle(P(10, 24, 40, 30), fill=W)
    return img


def ring(colours):
    s = 128 * K
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    c = s / 2
    outer, inner = s / 2 - 2, s / 2 - 9 * K
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - c, y - c)
            if inner <= r <= outer:
                # Colour along the diagonal, bottom-left to top-right.
                t = ((x - y) / s + 1) / 2
                n = len(colours) - 1
                i = min(int(t * n), n - 1)
                f = t * n - i
                a, b = colours[i], colours[i + 1]
                px[x, y] = tuple(int(a[j] + (b[j] - a[j]) * f) for j in range(3)) + (255,)
    img = img.resize((128, 128), Image.LANCZOS)
    return img


os.makedirs(ART, exist_ok=True)
save(heart(False), "Heart")
save(heart(True), "HeartOutline")
save(bubble(), "Bubble")
save(home(False), "Home")
save(home(True), "HomeFill")
save(plus(), "Plus")
save(bookmark(False), "Bookmark")
save(bookmark(True), "BookmarkFill")
save(user(), "User")
save(gear(), "Gear")
save(dots(), "Dots")
save(grid(), "Grid")
save(close(), "Close")
save(chevron(False), "ChevronLeft")
save(chevron(True), "ChevronRight")
save(shield(), "Shield")
save(circle(), "Circle")
save(pill(), "Pill", 128, 64)
save(rounded(), "Round")
save(red_button(), "RedButton")
save(window_max(), "WindowMax")
save(window_restore(), "WindowRestore")
ring([(254, 218, 117), (250, 126, 30), (214, 41, 118), (150, 47, 191)]).save(os.path.join(ART, "Ring.tga"))
# Effects (UI\Fx.lua): a vignette (dark edges, clear middle, 4 : 5), a soft
# glow, a snowflake, a five-point star, a raindrop streak, a bubble ring.
def vignette():
    w, h = 128, 160
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
            r = math.sqrt(dx * dx + dy * dy) / math.sqrt(2)
            a = max(0.0, min(1.0, (r - 0.35) / 0.65)) ** 1.6
            px[x, y] = (0, 0, 0, int(a * 255))
    return img


def glow():
    w = 64
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    px = img.load()
    for y in range(w):
        for x in range(w):
            r = math.hypot(x + 0.5 - w / 2, y + 0.5 - w / 2) / (w / 2)
            a = max(0.0, 1 - r) ** 2
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def snowflake():
    img, d = canvas()
    c = 32
    for i in range(6):
        t = math.radians(i * 60)
        x, y = c + 26 * math.cos(t), c + 26 * math.sin(t)
        d.line(P(c, c, x, y), fill=W, width=4 * K)
        for b in (0.55,):
            bx, by = c + 26 * b * math.cos(t), c + 26 * b * math.sin(t)
            for s in (-1, 1):
                t2 = t + s * math.radians(40)
                d.line(P(bx, by, bx + 9 * math.cos(t2), by + 9 * math.sin(t2)), fill=W, width=3 * K)
    return img


def star():
    img, d = canvas()
    pts = []
    for i in range(10):
        t = math.radians(-90 + i * 36)
        r = 29 if i % 2 == 0 else 12
        pts.append((32 + r * math.cos(t), 33 + r * math.sin(t)))
    d.polygon(P(*[v for p in pts for v in p]), fill=W)
    return img


def drop():
    img, d = canvas(16, 64)
    d.line(P(8, 2, 8, 62), fill=W, width=3 * K)
    return img


def ring_bubble():
    img, d = canvas()
    d.ellipse(P(4, 4, 60, 60), outline=W, width=3 * K)
    d.ellipse(P(16, 14, 26, 24), fill=W)
    return img


vignette().save(os.path.join(ART, "Vignette.tga"))
glow().save(os.path.join(ART, "Glow.tga"))
save(snowflake(), "Snowflake")
save(star(), "Star")
save(drop(), "Drop", 16, 64)
save(ring_bubble(), "BubbleRing")
# Create's tool rail: line icons, 64x64.
def tool_people():
    img, d = canvas()
    d.ellipse(P(10, 10, 30, 30), outline=W, width=LINE)
    d.arc(P(2, 34, 38, 70), 180, 360, fill=W, width=LINE)
    d.ellipse(P(36, 14, 54, 32), outline=W, width=LINE)
    d.arc(P(30, 38, 62, 70), 200, 340, fill=W, width=LINE)
    return img


def tool_outfit():
    img, d = canvas()
    pts = P(22, 8, 10, 14, 4, 28, 14, 32, 16, 56, 48, 56, 50, 32, 60, 28, 54, 14, 42, 8, 32, 16, 22, 8)
    d.line(pts, fill=W, width=LINE, joint="curve")
    return img


def tool_pose():
    img, d = canvas()
    d.ellipse(P(26, 4, 38, 16), outline=W, width=LINE)
    d.line(P(32, 18, 32, 38), fill=W, width=LINE)
    d.line(P(32, 22, 14, 12), fill=W, width=LINE)
    d.line(P(32, 22, 50, 30), fill=W, width=LINE)
    d.line(P(32, 38, 20, 58), fill=W, width=LINE)
    d.line(P(32, 38, 46, 58), fill=W, width=LINE)
    return img


def tool_image():
    img, d = canvas()
    d.rounded_rectangle(P(6, 10, 58, 54), radius=6 * K, outline=W, width=LINE)
    d.line(P(10, 48, 26, 30, 36, 40, 44, 32, 56, 46), fill=W, width=LINE, joint="curve")
    d.ellipse(P(38, 16, 48, 26), fill=W)
    return img


def tool_filter():
    img, d = canvas()
    d.ellipse(P(6, 6, 38, 38), outline=W, width=LINE)
    d.ellipse(P(26, 6, 58, 38), outline=W, width=LINE)
    d.ellipse(P(16, 26, 48, 58), outline=W, width=LINE)
    return img


def tool_sparkle():
    img, d = canvas()
    def spark(cx, cy, r):
        d.polygon(P(cx, cy - r, cx + r * 0.25, cy - r * 0.25, cx + r, cy, cx + r * 0.25, cy + r * 0.25,
                    cx, cy + r, cx - r * 0.25, cy + r * 0.25, cx - r, cy, cx - r * 0.25, cy - r * 0.25), fill=W)
    spark(26, 34, 22)
    spark(50, 14, 10)
    spark(52, 48, 7)
    return img


def tool_sticker():
    img, d = canvas()
    d.line(P(8, 8, 56, 8, 56, 36, 36, 56, 8, 56, 8, 8), fill=W, width=LINE, joint="curve")
    d.line(P(56, 36, 36, 36, 36, 56), fill=W, width=LINE, joint="curve")
    d.ellipse(P(18, 20, 24, 26), fill=W)
    d.ellipse(P(32, 20, 38, 26), fill=W)
    return img


def tool_text():
    img, d = canvas()
    d.line(P(10, 12, 54, 12), fill=W, width=LINE + K)
    d.line(P(32, 12, 32, 56), fill=W, width=LINE + K)
    d.line(P(22, 56, 42, 56), fill=W, width=LINE)
    return img


def tool_frame():
    img, d = canvas()
    d.rectangle(P(6, 6, 58, 58), outline=W, width=LINE)
    d.rectangle(P(16, 16, 48, 44), outline=W, width=3 * K)
    return img


def tool_lens():
    img, d = canvas()
    d.line(P(10, 54, 40, 24), fill=W, width=LINE + K)
    for cx, cy, r in ((46, 18, 9), (24, 12, 5), (54, 38, 5)):
        d.polygon(P(cx, cy - r, cx + r * 0.3, cy - r * 0.3, cx + r, cy, cx + r * 0.3, cy + r * 0.3,
                    cx, cy + r, cx - r * 0.3, cy + r * 0.3, cx - r, cy, cx - r * 0.3, cy - r * 0.3), fill=W)
    return img


for fn, name in ((tool_people, "ToolPeople"), (tool_outfit, "ToolOutfit"), (tool_pose, "ToolPose"),
                 (tool_image, "ToolImage"), (tool_filter, "ToolFilter"), (tool_sparkle, "ToolSparkle"),
                 (tool_sticker, "ToolSticker"), (tool_text, "ToolText"), (tool_frame, "ToolFrame"), (tool_lens, "ToolLens")):
    save(fn(), name)
# More overlay art: leaf, butterfly, music note, a Z, balloon, bat, ghost,
# lightning bolt, light ray (32x128), feather.
def leaf():
    img, d = canvas()
    d.polygon(P(32, 4, 48, 18, 52, 36, 40, 54, 32, 60, 24, 54, 12, 36, 16, 18), fill=W)
    d.line(P(32, 10, 32, 62), fill=(0, 0, 0, 0), width=2 * K)
    return img


def butterfly():
    img, d = canvas()
    d.ellipse(P(4, 8, 30, 34), fill=W)
    d.ellipse(P(34, 8, 60, 34), fill=W)
    d.ellipse(P(10, 30, 30, 54), fill=W)
    d.ellipse(P(34, 30, 54, 54), fill=W)
    d.rectangle(P(30, 12, 34, 52), fill=W)
    return img


def note():
    img, d = canvas()
    d.ellipse(P(8, 40, 28, 58), fill=W)
    d.rectangle(P(24, 8, 29, 50), fill=W)
    d.polygon(P(24, 8, 52, 2, 52, 14, 29, 20), fill=W)
    d.ellipse(P(36, 34, 56, 52), fill=W)
    d.rectangle(P(51, 6, 56, 44), fill=W)
    return img


def zee():
    img, d = canvas()
    d.line(P(12, 12, 52, 12, 12, 52, 52, 52), fill=W, width=7 * K, joint="curve")
    return img


def balloon():
    img, d = canvas()
    d.ellipse(P(14, 2, 50, 44), fill=W)
    d.polygon(P(29, 42, 35, 42, 32, 48), fill=W)
    d.line(P(32, 48, 28, 56, 34, 62), fill=W, width=2 * K)
    return img


def bat():
    img, d = canvas()
    d.polygon(P(32, 24, 22, 18, 4, 14, 10, 24, 6, 32, 18, 30, 26, 38, 32, 44,
                38, 38, 46, 30, 58, 32, 54, 24, 60, 14, 42, 18), fill=W)
    d.polygon(P(26, 20, 28, 12, 31, 20, 33, 20, 36, 12, 38, 20), fill=W)
    return img


def ghost():
    img, d = canvas()
    d.ellipse(P(12, 4, 52, 44), fill=W)
    d.rectangle(P(12, 24, 52, 52), fill=W)
    d.polygon(P(12, 52, 18, 60, 24, 52, 32, 60, 40, 52, 46, 60, 52, 52), fill=W)
    d.ellipse(P(22, 18, 29, 28), fill=(0, 0, 0, 0))
    d.ellipse(P(35, 18, 42, 28), fill=(0, 0, 0, 0))
    return img


def bolt():
    img, d = canvas()
    d.polygon(P(36, 2, 14, 34, 30, 34, 22, 62, 50, 24, 34, 24, 44, 2), fill=W)
    return img


def ray():
    w, h = 32, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            a = max(0.0, 1 - abs(x + 0.5 - w / 2) / (w / 2)) ** 1.5 * (1 - y / h)
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def feather():
    img, d = canvas()
    d.polygon(P(32, 2, 44, 16, 46, 36, 36, 54, 32, 62, 28, 54, 18, 36, 20, 16), fill=W)
    d.line(P(32, 6, 32, 62), fill=(0, 0, 0, 0), width=2 * K)
    for y in range(14, 54, 8):
        d.line(P(32, y, 22, y + 6), fill=(0, 0, 0, 0), width=K)
        d.line(P(32, y, 42, y + 6), fill=(0, 0, 0, 0), width=K)
    return img


for fn, name in ((leaf, "Leaf"), (butterfly, "Butterfly"), (note, "Note"), (zee, "Zee"), (balloon, "Balloon"),
                 (bat, "Bat"), (ghost, "Ghost"), (bolt, "Bolt"), (feather, "Feather")):
    save(fn(), name)
ray().save(os.path.join(ART, "Ray.tga"))
def tool_motion():
    img, d = canvas()
    for y in (16, 32, 48):
        pts = []
        for i in range(0, 57, 2):
            x = 4 + i
            pts += [x, y + 6 * math.sin(i / 56 * 2 * math.pi * 1.5)]
        d.line(P(*pts), fill=W, width=LINE, joint="curve")
    return img


save(tool_motion(), "ToolMotion")
# Face filters (UI\Decor.lua draws them on the head): white, tinted there.
def cat_ear():
    img, d = canvas()
    d.polygon(P(8, 60, 32, 4, 56, 60), fill=W)
    return img


def bunny_ear():
    img, d = canvas(32, 96)
    d.ellipse(P(2, 2, 30, 94), fill=W)
    return img


def dog_ear():
    img, d = canvas()
    d.ellipse(P(10, 2, 54, 62), fill=W)
    return img


def sunglasses():
    img, d = canvas(128, 40)
    d.rectangle(P(0, 2, 128, 8), fill=W)
    for x in (6, 70):
        d.rounded_rectangle(P(x, 4, x + 52, 36), radius=10 * K, fill=W)
    return img


def glasses():
    img, d = canvas(128, 48)
    for x in (8, 72):
        d.ellipse(P(x, 4, x + 48, 44), outline=W, width=5 * K)
    d.line(P(56, 20, 72, 20), fill=W, width=5 * K)
    return img


def crown():
    img, d = canvas(64, 40)
    d.polygon(P(2, 38, 2, 10, 16, 22, 32, 2, 48, 22, 62, 10, 62, 38), fill=W)
    return img


def halo():
    img, d = canvas(128, 32)
    d.ellipse(P(4, 4, 124, 28), outline=W, width=5 * K)
    return img


def horn():
    img, d = canvas(32, 64)
    d.polygon(P(4, 62, 28, 62, 22, 30, 10, 2, 12, 34), fill=W)
    return img


def flower():
    img, d = canvas()
    for i in range(5):
        t = math.radians(i * 72 - 90)
        cx, cy = 32 + 16 * math.cos(t), 32 + 16 * math.sin(t)
        d.ellipse(P(cx - 13, cy - 13, cx + 13, cy + 13), fill=W)
    d.ellipse(P(24, 24, 40, 40), fill=(0, 0, 0, 0))
    return img


def mustache():
    img, d = canvas(128, 48)
    for side in (-1, 1):
        pts = []
        for i in range(0, 61, 3):
            x = 64 + side * i
            y = 18 + 10 * math.sin(i / 60 * math.pi) - (i / 60) ** 3 * 18
            pts.append((x, y))
        for i in range(60, -1, -3):
            x = 64 + side * i
            y = 18 + 22 * math.sin(i / 60 * math.pi) * 0.9 - (i / 60) ** 3 * 18 + 2
            pts.append((x, y))
        d.polygon(P(*[v for p in pts for v in p]), fill=W)
    return img


def party_hat():
    img, d = canvas(64, 96)
    d.polygon(P(32, 4, 6, 92, 58, 92), fill=W)
    return img


for fn, name, w, h in ((cat_ear, "FaceCatEar", 64, 64), (bunny_ear, "FaceBunnyEar", 32, 96), (dog_ear, "FaceDogEar", 64, 64),
                       (sunglasses, "FaceShades", 128, 40), (glasses, "FaceGlasses", 128, 48), (crown, "FaceCrown", 64, 40),
                       (halo, "FaceHalo", 128, 32), (horn, "FaceHorn", 32, 64), (flower, "FaceFlower", 64, 64),
                       (mustache, "FaceMustache", 128, 48), (party_hat, "FacePartyHat", 64, 96)):
    save(fn(), name, w, h)
# The logo (the addon list, the minimap button, the window's portrait and
# CurseForge): our own, not anyone's trademark: a deep blue-to-magenta
# square with a WoW-gold rim, an old box camera in white, and a gold
# sparkle. Art/Logo.tga (128) and dev/media/icon.png (400).
def logo(size):
    S = size * K
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    top, bottom = (40, 52, 140), (196, 42, 132)
    px = grad.load()
    for y in range(S):
        for x in range(S):
            t = (y * 0.75 + x * 0.25) / S
            px[x, y] = tuple(int(top[j] + (bottom[j] - top[j]) * t) for j in range(3)) + (255,)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.2), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    u = S / 100
    gold = (240, 196, 80, 255)
    d.rounded_rectangle((2 * u, 2 * u, 98 * u, 98 * u), radius=int(S * 0.19), outline=gold, width=int(4 * u))
    white = (255, 255, 255, 255)
    # Box camera: a body, a hump on top left (the viewfinder), a big lens.
    d.rounded_rectangle((16 * u, 32 * u, 84 * u, 78 * u), radius=int(8 * u), fill=white)
    d.rounded_rectangle((24 * u, 24 * u, 44 * u, 36 * u), radius=int(3 * u), fill=white)
    d.ellipse((34 * u, 38 * u, 66 * u, 70 * u), fill=(60, 50, 140, 255))
    d.ellipse((40 * u, 44 * u, 60 * u, 64 * u), fill=(150, 60, 170, 255))
    d.ellipse((44 * u, 47 * u, 50 * u, 53 * u), fill=(255, 255, 255, 200))
    # The sparkle.
    cx, cy, r = 77 * u, 20 * u, 11 * u
    d.polygon([(cx, cy - r), (cx + r * 0.28, cy - r * 0.28), (cx + r, cy), (cx + r * 0.28, cy + r * 0.28),
               (cx, cy + r), (cx - r * 0.28, cy + r * 0.28), (cx - r, cy), (cx - r * 0.28, cy - r * 0.28)], fill=gold)
    return img.resize((size, size), Image.LANCZOS)


logo(128).save(os.path.join(ART, "Logo.tga"))
logo(400).save(os.path.join(HERE, "media", "icon.png"))
# Dislike: a thumbs-down, outline and filled (a thumbs-up, flipped).
def thumb(fill):
    img, d = canvas()
    shape = P(22, 58, 22, 28, 30, 26, 36, 6, 44, 8, 44, 24, 56, 24, 60, 30, 56, 58)
    if fill:
        d.polygon(shape, fill=W)
    else:
        d.line(shape + shape[:2], fill=W, width=LINE, joint="curve")
    d.rectangle(P(4, 28, 16, 60), fill=W) if fill else d.rectangle(P(4, 28, 16, 60), outline=W, width=LINE)
    return img.transpose(Image.FLIP_TOP_BOTTOM)


save(thumb(False), "ThumbDown")
save(thumb(True), "ThumbDownFill")
def search():
    img, d = canvas()
    d.ellipse(P(8, 8, 44, 44), outline=W, width=LINE)
    d.line(P(40, 40, 58, 58), fill=W, width=LINE + K)
    return img


save(search(), "Search")
print("ok")
