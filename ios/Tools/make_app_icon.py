#!/usr/bin/env python3
"""Draw the Dock Finder app icon: a map pin holding a bike, pointing at a
row of docks, over a street map.

Writes the three 1024x1024 variants iOS uses (light, dark, tinted) into
biker-app/Assets.xcassets/AppIcon.appiconset. Needs Pillow:

    python3 ios/Tools/make_app_icon.py
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "biker-app" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024
SCALE = 4  # draw large, then downsample for smooth edges
S = SIZE * SCALE

# Design coordinates are on a 1024 grid.
PIN_CENTER, PIN_RADIUS, PIN_TIP = (512, 335), 232, 690
DISC_RADIUS = 166
DOCK_XS = (262, 512, 762)
DOCK_TOP, DOCK_BOTTOM = 680, 900


def p(x, y):
    return (x * SCALE, y * SCALE)


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def blend(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def corner_gradient(top_left, top_right, bottom_left, bottom_right):
    """Bilinear blend of four corner colors."""
    small = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            u, v = x / 63, y / 63
            small.putpixel((x, y), blend(blend(top_left, top_right, u), blend(bottom_left, bottom_right, u), v))
    return small.resize((S, S), Image.BICUBIC).convert("RGBA")


def stroke(draw, points, width, fill):
    """A polyline with round joins and caps."""
    w = width * SCALE
    pts = [p(*pt) for pt in points]
    draw.line(pts, fill=fill, width=round(w), joint="curve")
    for x, y in (pts[0], pts[-1]):
        draw.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=fill)


def bezier(points, steps=60):
    """Points along a chain of cubic Béziers: p0, c1, c2, p1, c1, c2, p2, …"""
    out = []
    for i in range(0, len(points) - 1, 3):
        p0, c1, c2, p1 = points[i:i + 4]
        for s in range(steps + 1):
            t = s / steps
            out.append(tuple(
                (1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t ** 2 * c + t ** 3 * d
                for a, b, c, d in zip(p0, c1, c2, p1)
            ))
    return out


def soft_shadow(shape, blur, offset, opacity, color=(0, 20, 60)):
    alpha = shape.getchannel("A").filter(ImageFilter.GaussianBlur(blur * SCALE))
    sh = Image.new("RGBA", (S, S), color + (0,))
    sh.putalpha(alpha.point(lambda v: round(v * opacity)))
    out = layer()
    out.alpha_composite(sh, (0, offset * SCALE))
    return out


# MARK: - Background map

def streets(color):
    """Light street lines on a slight angle, like a city grid."""
    img = layer()
    d = ImageDraw.Draw(img)
    for line in [
        [(-40, 150), (1060, 560)],
        [(-40, 470), (1060, 880)],
        [(-40, 790), (700, 1066)],
        [(330, -40), (60, 1060)],
        [(660, -40), (380, 1060)],
        [(1000, 130), (720, 1060)],
    ]:
        stroke(d, line, 40, color)
    return img


def route(color):
    """A winding cycling route down the right side."""
    img = layer()
    d = ImageDraw.Draw(img)
    pts = bezier([
        (640, -60), (760, 80), (980, 160), (960, 330),
        (940, 470), (790, 480), (830, 600),
        (870, 720), (1010, 760), (1080, 900),
    ])
    stroke(d, pts, 64, color)
    return img


# MARK: - Pin and bike

def pin_shape(fill):
    img = layer()
    d = ImageDraw.Draw(img)
    cx, cy = PIN_CENTER
    r, tip = PIN_RADIUS, PIN_TIP
    a = math.asin(r / (tip - cy))  # tangent from the tip to the circle
    tx, ty = r * math.cos(a), r * math.sin(a)
    d.ellipse([*p(cx - r, cy - r), *p(cx + r, cy + r)], fill=fill)
    d.polygon([p(cx - tx, cy + ty), p(cx + tx, cy + ty), p(cx, tip)], fill=fill)
    # round off the tip
    tr = 14
    d.ellipse([*p(cx - tr, tip - 2 * tr - 4), *p(cx + tr, tip - 4)], fill=fill)
    return img


def bike(color):
    """An outlined bike centered in the pin's disc."""
    img = layer()
    d = ImageDraw.Draw(img)
    cx, cy = PIN_CENTER
    k = 0.84  # bike drawn on a 300-wide box, scaled into the disc
    ox, oy = cx - 150 * k, cy - 141 * k

    def q(x, y):
        return (ox + x * k, oy + y * k)

    line = 17
    wheel_r = 56
    rear, front = q(62, 170), q(238, 170)
    crank, seat, head = q(138, 170), q(108, 92), q(206, 92)
    for c in (rear, front):
        r = wheel_r * k
        w = line
        d.ellipse([*p(c[0] - r - w / 2, c[1] - r - w / 2), *p(c[0] + r + w / 2, c[1] + r + w / 2)], outline=color, width=round(w * SCALE))
    stroke(d, [rear, crank, head], line, color)
    stroke(d, [crank, seat, rear], line, color)
    stroke(d, [head, front], line, color)
    stroke(d, [seat, q(98, 58)], line, color)
    stroke(d, [q(70, 58), q(126, 58)], line, color)
    stroke(d, [head, q(196, 54), q(236, 54)], line, color)
    return img


# MARK: - Docks

def docks(body_top, body_bottom, face, light, base, glow):
    img = layer()
    base_layer = layer()
    bd = ImageDraw.Draw(base_layer)
    bd.rounded_rectangle([*p(130, DOCK_BOTTOM - 22), *p(894, DOCK_BOTTOM + 16)], radius=16 * SCALE, fill=base)
    img.alpha_composite(base_layer)

    for x in DOCK_XS:
        post = layer()
        d = ImageDraw.Draw(post)
        top_w, bottom_w = 124, 176
        d.polygon([
            p(x - top_w / 2, DOCK_TOP + 30), p(x + top_w / 2, DOCK_TOP + 30),
            p(x + bottom_w / 2, DOCK_BOTTOM), p(x - bottom_w / 2, DOCK_BOTTOM),
        ], fill=(255, 255, 255, 255))
        d.rounded_rectangle([*p(x - top_w / 2, DOCK_TOP), *p(x + top_w / 2, DOCK_TOP + 80)], radius=30 * SCALE, fill=(255, 255, 255, 255))
        # vertical shading on the post
        shade = Image.new("RGBA", (1, 2))
        shade.putpixel((0, 0), body_top)
        shade.putpixel((0, 1), body_bottom)
        shade = shade.resize((S, (DOCK_BOTTOM - DOCK_TOP) * SCALE), Image.BILINEAR)
        fill = layer()
        fill.alpha_composite(shade, (0, DOCK_TOP * SCALE))
        fill.putalpha(ImageChops.multiply(fill.getchannel("A"), post.getchannel("A")))
        img.alpha_composite(soft_shadow(post, 10, 6, 0.35))
        img.alpha_composite(fill)

        # dark front panel with the status light
        d = ImageDraw.Draw(img)
        fw_top, fw_bottom = 50, 68
        d.polygon([
            p(x - fw_top / 2, DOCK_TOP + 40), p(x + fw_top / 2, DOCK_TOP + 40),
            p(x + fw_bottom / 2, DOCK_BOTTOM - 22), p(x - fw_bottom / 2, DOCK_BOTTOM - 22),
        ], fill=face)
        d.rounded_rectangle([*p(x - fw_top / 2, DOCK_TOP + 18), *p(x + fw_top / 2, DOCK_TOP + 70)], radius=20 * SCALE, fill=face)

        glow_layer = layer()
        gd = ImageDraw.Draw(glow_layer)
        gd.rounded_rectangle([*p(x - 9, DOCK_TOP + 52), *p(x + 9, DOCK_TOP + 132)], radius=9 * SCALE, fill=light)
        if glow:
            img.alpha_composite(soft_shadow(glow_layer, 10, 0, glow, color=light[:3]))
        img.alpha_composite(glow_layer)
    return img


# MARK: - Composition

def compose(colors, tinted=False):
    if tinted:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    else:
        img = corner_gradient(*colors["background"])
        img.alpha_composite(streets(colors["street"]))
        img.alpha_composite(route(colors["route"]))

    img.alpha_composite(docks(**colors["docks"], glow=0 if tinted else 0.9))

    pin = pin_shape(colors["pin"])
    if not tinted:
        img.alpha_composite(soft_shadow(pin, 18, 14, 0.4))
    img.alpha_composite(pin)
    disc = ImageDraw.Draw(img)
    cx, cy = PIN_CENTER
    disc.ellipse([*p(cx - DISC_RADIUS, cy - DISC_RADIUS), *p(cx + DISC_RADIUS, cy + DISC_RADIUS)], fill=colors["disc"])
    img.alpha_composite(bike(colors["bike"]))
    return img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


LIGHT = {
    "background": ((6, 118, 240), (20, 206, 200), (8, 52, 140), (4, 92, 160)),
    "street": (90, 170, 255, 70),
    "route": (40, 226, 240, 230),
    "pin": (255, 255, 255, 255),
    "disc": (8, 44, 96, 255),
    "bike": (255, 255, 255, 255),
    "docks": {
        "body_top": (250, 252, 255, 255), "body_bottom": (176, 198, 226, 255),
        "face": (10, 34, 78, 255), "light": (30, 240, 236, 255), "base": (8, 30, 70, 255),
    },
}

DARK = {
    "background": ((10, 34, 70), (8, 70, 80), (4, 12, 28), (4, 24, 40)),
    "street": (70, 120, 190, 45),
    "route": (30, 200, 210, 180),
    "pin": (236, 242, 248, 255),
    "disc": (6, 22, 48, 255),
    "bike": (60, 230, 230, 255),
    "docks": {
        "body_top": (214, 222, 234, 255), "body_bottom": (120, 140, 168, 255),
        "face": (6, 18, 40, 255), "light": (30, 240, 236, 255), "base": (2, 10, 24, 255),
    },
}

TINTED = {
    "pin": (255, 255, 255, 255),
    "disc": (0, 0, 0, 255),
    "bike": (255, 255, 255, 255),
    "docks": {
        "body_top": (215, 215, 215, 255), "body_bottom": (150, 150, 150, 255),
        "face": (40, 40, 40, 255), "light": (255, 255, 255, 255), "base": (60, 60, 60, 255),
    },
}


def main():
    files = {
        "AppIcon.png": compose(LIGHT),
        "AppIcon-Dark.png": compose(DARK),
        "AppIcon-Tinted.png": compose(TINTED, tinted=True).convert("L"),
    }
    for name, image in files.items():
        image.save(OUT / name, optimize=True)
        print("wrote", OUT / name)


if __name__ == "__main__":
    main()
