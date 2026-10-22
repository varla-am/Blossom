"""Draws the Blossom DMG window background, kept minimal: a quiet plum gradient,
a small dotted arrow from the app (top) down to Applications (bottom), and one line of text.

Usage: python3 background.py <out-dir>
Writes background.png (1x) and background@2x.png; make-dmg.sh joins them into one HiDPI TIFF.
Everything is laid out in window points (WIDTH x HEIGHT) and drawn 4x larger, then scaled down,
so edges come out smooth.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 420, 600   # the DMG window, in points
APP = (210, 175)           # where make-dmg.sh puts the app icon (its center)
APPLICATIONS = (210, 445)  # and the Applications link
S = 4                      # drawing scale
SIZE = (WIDTH * S, HEIGHT * S)
DOT = (240, 166, 202)      # Blossom's pink, a little softer than the accent


def px(v):
    return int(round(v * S))


def backdrop():
    """Plum at the top to near-black at the bottom, barely changing."""
    top, bottom = (38, 24, 44), (20, 14, 26)
    img = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE[1]):
        t = y / SIZE[1]
        draw.line([(0, y), (SIZE[0], y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def dotted_arrow(img):
    """A short line of dots, then a little chevron of dots, between the app's name and Applications."""
    x = APP[0]
    middle = (APP[1] + APPLICATIONS[1]) / 2 + 8
    spacing, r = 8, 1.6
    tip = middle + 22
    dots = [(x, tip - k * spacing) for k in range(6)]
    for k in range(1, 4):
        step = k * spacing / 1.414
        dots += [(x - step, tip - step), (x + step, tip - step)]
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for dx, dy in dots:
        d.ellipse([px(dx - r), px(dy - r), px(dx + r), px(dy + r)], fill=DOT + (220,))
    img.alpha_composite(layer)


def caption(img):
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", px(12))
    except OSError:
        font = ImageFont.load_default()
    # On its own layer: drawing straight onto the image would replace its alpha, not blend
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((px(WIDTH / 2), px(560)), "⌥ Space to bloom", font=font, fill=(255, 255, 255, 110), anchor="mm")
    img.alpha_composite(layer)


def main(out):
    img = backdrop()
    dotted_arrow(img)
    caption(img)
    img = img.convert("RGB")
    img.resize((WIDTH * 2, HEIGHT * 2), Image.LANCZOS).save(f"{out}/background@2x.png")
    img.resize((WIDTH, HEIGHT), Image.LANCZOS).save(f"{out}/background.png")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
