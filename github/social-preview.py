"""Draws Blossom's GitHub social preview (1280x640), in the DMG's quiet plum:
the icon and name on the left, a little launcher on the right with a command being typed.

Usage: python3 social-preview.py [out.png]     (default: social-preview.png beside this script)
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1280, 640
S = 2  # drawing scale
here = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(here, "..", "Blossom", "Assets.xcassets", "AppIcon.appiconset", "icon_512x512@2x.png")
FONT = "/System/Library/Fonts/SFNS.ttf"
ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
MENLO = "/System/Library/Fonts/Menlo.ttc"  # SF has no ↩
PINK = (219, 92, 148)


def px(v):
    return int(round(v * S))


def font(path, size, weight=400):
    """SF at a weight; every axis has to be given, so the others keep their defaults."""
    f = ImageFont.truetype(path, px(size))
    try:
        axes = f.get_variation_axes()
    except OSError:
        return f  # not a variable font
    values = []
    for axis in axes:
        name = axis["name"]
        if name == b"Weight":
            values.append(weight)
        elif name == b"Optical Size":
            values.append(max(axis["minimum"], min(size, axis["maximum"])))
        else:
            values.append(axis["default"])
    f.set_variation_by_axes(values)
    return f


def sakura(d, cx, cy, r, fill):
    """Blossom's flower head, as in Themes.swift."""
    def cubic(p0, p1, p2, p3, steps=24):
        return [tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t * t * c + t ** 3 * e
                      for a, b, c, e in zip(p0, p1, p2, p3)) for t in (i / steps for i in range(steps + 1))]
    petal = (cubic((0, -0.12), (-0.4, -0.35), (-0.44, -0.9), (-0.14, -0.98)) + [(0, -0.84)]
             + cubic((0.14, -0.98), (0.44, -0.9), (0.4, -0.35), (0, -0.12)))
    for k in range(5):
        a = k * 2 * math.pi / 5
        d.polygon([(cx + r * (x * math.cos(a) - y * math.sin(a)), cy + r * (x * math.sin(a) + y * math.cos(a))) for x, y in petal], fill=fill)
    d.ellipse([cx - r * 0.13, cy - r * 0.13, cx + r * 0.13, cy + r * 0.13], fill=fill)


def speaker(d, cx, cy, size, fill, muted=False):
    """A small speaker, with sound waves or a slash."""
    u = size / 10
    d.rectangle([px(cx - 4 * u), px(cy - 1.6 * u), px(cx - 2 * u), px(cy + 1.6 * u)], fill=fill)
    d.polygon([(px(cx - 2 * u), px(cy - 1.6 * u)), (px(cx + 1 * u), px(cy - 4 * u)),
               (px(cx + 1 * u), px(cy + 4 * u)), (px(cx - 2 * u), px(cy + 1.6 * u))], fill=fill)
    if muted:
        d.line([px(cx - 4.5 * u), px(cy - 4.5 * u), px(cx + 4.5 * u), px(cy + 4.5 * u)], fill=fill, width=px(1.6))
    else:
        for r in (2.4, 4.2):
            d.arc([px(cx + 1 * u - r * u), px(cy - r * u), px(cx + 1 * u + r * u), px(cy + r * u)], -50, 50, fill=fill, width=px(1.4))


def layer():
    return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))


def backdrop():
    top, bottom = (38, 24, 44), (20, 14, 26)
    img = Image.new("RGBA", (W * S, H * S))
    d = ImageDraw.Draw(img)
    for y in range(H * S):
        t = y / (H * S)
        d.line([(0, y), (W * S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    # One soft pink glow behind the launcher, so it doesn't sit on flat black
    glow = layer()
    ImageDraw.Draw(glow).ellipse([px(700), px(170), px(1180), px(470)], fill=PINK + (60,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(px(90))))
    return img


def title(img):
    icon = Image.open(ICON).convert("RGBA").resize((px(150), px(150)), Image.LANCZOS)
    img.alpha_composite(icon, (px(84), px(150)))
    l = layer()
    d = ImageDraw.Draw(l)
    d.text((px(96), px(318)), "Blossom", font=font(FONT, 78, 700), fill=(255, 255, 255, 255))
    d.text((px(98), px(420)), "Press ⌥ Space, type a word,", font=font(FONT, 26, 400), fill=(255, 255, 255, 170))
    d.text((px(98), px(456)), "watch it bloom.", font=font(FONT, 26, 400), fill=(255, 255, 255, 170))
    d.text((px(98), px(530)), "A tiny launcher for macOS", font=font(ROUNDED, 18, 500), fill=PINK + (230,))
    img.alpha_composite(l)


def launcher(img):
    x0, y0, w = 640, 190, 560
    field_h, row_h = 76, 62
    h = field_h + 12 + row_h * 2 + 12
    box = [px(x0), px(y0), px(x0 + w), px(y0 + h)]

    shadow = layer()
    ImageDraw.Draw(shadow).rounded_rectangle([b + (px(10) if i % 2 else 0) for i, b in enumerate(box)], radius=px(22), fill=(0, 0, 0, 150))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(22))))

    l = layer()
    d = ImageDraw.Draw(l)
    d.rounded_rectangle(box, radius=px(22), fill=(52, 38, 58, 235), outline=(255, 255, 255, 34), width=px(1))
    # The field
    sakura(d, px(x0 + 44), px(y0 + field_h / 2), px(16), PINK + (255,))
    d.text((px(x0 + 72), px(y0 + field_h / 2)), "volume 30", font=font(MONO, 26), fill=(255, 255, 255, 240), anchor="lm")
    d.rectangle([px(x0 + 238), px(y0 + 24), px(x0 + 240), px(y0 + field_h - 24)], fill=PINK + (255,))
    d.line([px(x0), px(y0 + field_h), px(x0 + w), px(y0 + field_h)], fill=(255, 255, 255, 26), width=px(1))

    rows = [("volume", "Set Volume · 30", True), ("mute", "Mute / Unmute", False)]
    for i, (keyword, subtitle, selected) in enumerate(rows):
        ry = y0 + field_h + 12 + i * row_h
        if selected:
            d.rounded_rectangle([px(x0 + 10), px(ry), px(x0 + w - 10), px(ry + row_h - 4)], radius=px(12), fill=PINK + (255,))
        ink = (255, 255, 255)
        d.rounded_rectangle([px(x0 + 24), px(ry + 12), px(x0 + 58), px(ry + 46)], radius=px(9),
                            # Solid colours: on one layer a translucent fill replaces what's under it instead of blending
                            fill=(230, 132, 176, 255) if selected else (82, 40, 66, 255))
        speaker(d, x0 + 41, ry + 29, 17, ink + (255,) if selected else PINK + (255,), muted=keyword == "mute")
        d.text((px(x0 + 74), px(ry + 9)), keyword, font=font(FONT, 19, 600), fill=ink + (255,))
        d.text((px(x0 + 74), px(ry + 33)), subtitle, font=font(FONT, 15), fill=ink + (200 if selected else 130,))
        if selected:
            d.text((px(x0 + w - 36), px(ry + 29)), "↩", font=font(MENLO, 20), fill=ink + (200,), anchor="mm")
    img.alpha_composite(l)


def main(out):
    img = backdrop()
    title(img)
    launcher(img)
    img.convert("RGB").resize((W, H), Image.LANCZOS).save(out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "social-preview.png"))
