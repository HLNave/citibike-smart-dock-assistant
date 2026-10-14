#!/usr/bin/env python3
"""Draw the Dock Finder app icon: a bicycle under a map pin.

Writes the three 1024x1024 variants iOS uses (light, dark, tinted) into
biker-app/Assets.xcassets/AppIcon.appiconset. Needs Pillow:

    python3 ios/Tools/make_app_icon.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "biker-app" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024
SCALE = 4  # draw large, then downsample for smooth edges
S = SIZE * SCALE


def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    px = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        px.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def p(x, y):
    """Design coordinates are on a 1024 grid."""
    return (x * SCALE, y * SCALE)


def stroke(draw, points, width, fill):
    w = width * SCALE
    pts = [p(*pt) for pt in points]
    draw.line(pts, fill=fill, width=round(w), joint="curve")
    for x, y in pts:  # round caps
        draw.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=fill)


def ring(draw, cx, cy, r, width, fill):
    o, i = (r + width / 2) * SCALE, (r - width / 2) * SCALE
    x, y = cx * SCALE, cy * SCALE
    draw.ellipse([x - o, y - o, x + o, y + o], fill=fill)
    draw.ellipse([x - i, y - i, x + i, y + i], fill=(0, 0, 0, 0))


def bike_layer(color):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    wheel_y, r, line = 690, 150, 46
    rear, front = (300, wheel_y), (724, wheel_y)
    crank = (480, wheel_y)
    seat = (420, 500)
    head = (660, 500)
    # wheels (drawn on their own layer so the hub cut-outs don't erase the frame)
    wheels = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wheels)
    ring(wd, *rear, r, line, color)
    ring(wd, *front, r, line, color)
    layer.alpha_composite(wheels)
    # frame
    stroke(d, [rear, crank, head, seat, rear], line, color)
    stroke(d, [head, front], line, color)
    stroke(d, [seat, (400, 448)], line, color)         # seat post
    stroke(d, [(352, 440), (452, 440)], line, color)   # saddle
    stroke(d, [head, (640, 444), (704, 430)], line, color)  # stem + bar
    hub = 30 * SCALE
    for cx, cy in (rear, front, crank):
        d.ellipse([cx * SCALE - hub, cy * SCALE - hub, cx * SCALE + hub, cy * SCALE + hub], fill=color)
    return layer


def pin_layer(body, dot):
    """A map pin above the bike: a circle with a point, and a hole."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy, r = 512, 250, 130
    tip = 440
    # tangent points from the tip to the circle
    dist = tip - cy
    a = math.asin(r / dist)
    tx = r * math.cos(a)
    ty = r * math.sin(a)
    d.ellipse([*p(cx - r, cy - r), *p(cx + r, cy + r)], fill=body)
    d.polygon([p(cx - tx, cy + ty), p(cx + tx, cy + ty), p(cx, tip)], fill=body)
    hr = 54
    d.ellipse([*p(cx - hr, cy - hr), *p(cx + hr, cy + hr)], fill=dot)
    return layer


def shadow(layer, opacity):
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(14 * SCALE))
    sh = Image.new("RGBA", (S, S), (0, 20, 40, 0))
    sh.putalpha(alpha.point(lambda v: round(v * opacity)))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(sh, (0, 10 * SCALE))
    return out


def fit(layer, scale=0.84, lift=10):
    """Shrinks the artwork toward the center so it clears the rounded corners."""
    small = layer.resize((round(S * scale), round(S * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    offset = (S - small.width) // 2
    out.alpha_composite(small, (offset, offset - lift * SCALE))
    return out


def compose(background, bike_color, pin_color, pin_dot, shadow_opacity):
    img = background.convert("RGBA")
    bike = fit(bike_layer(bike_color))
    pin = fit(pin_layer(pin_color, pin_dot))
    for layer in (bike, pin):
        if shadow_opacity:
            img.alpha_composite(shadow(layer, shadow_opacity))
        img.alpha_composite(layer)
    return img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


def main():
    teal_top, teal_bottom = (22, 190, 170), (8, 112, 128)
    light = compose(gradient(teal_top, teal_bottom), (255, 255, 255, 255), (255, 214, 64, 255), teal_bottom + (255,), 0.25)
    dark = compose(gradient((28, 36, 40), (10, 14, 16)), (94, 224, 204, 255), (255, 214, 64, 255), (14, 20, 22, 255), 0)
    tinted = compose(Image.new("RGB", (S, S), (0, 0, 0)), (255, 255, 255, 255), (200, 200, 200, 255), (0, 0, 0, 255), 0).convert("L")

    files = {"AppIcon.png": light, "AppIcon-Dark.png": dark, "AppIcon-Tinted.png": tinted}
    for name, image in files.items():
        image.save(OUT / name, optimize=True)
        print("wrote", OUT / name)


if __name__ == "__main__":
    main()
