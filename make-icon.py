# Draws Blossom's app icon: a five-petal sakura on a dark rounded square, then every size Xcode wants.
import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
W = 1024 * S
BG_TOP, BG_BOT = (44, 30, 52), (16, 12, 22)
PETAL_IN, PETAL_OUT = (255, 214, 232), (240, 140, 186)
CENTER = (255, 236, 160)

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# Background: a vertical gradient inside the macOS rounded square, with a margin like Apple's icons
m = 100 * S
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
for y in range(W):
    t = y / W
    gd.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)) + (255,))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([m, m, W - m, W - m], radius=185 * S, fill=255)
img.paste(grad, (0, 0), mask)

cx, cy = W / 2, W / 2 + 10 * S

def petal(angle):
    # A petal: an ellipse pointing out from the centre, with the sakura notch at its tip
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    length, width = 250 * S, 190 * S
    for i in range(60, 0, -1):
        t = i / 60
        colour = tuple(int(a + (b - a) * t) for a, b in zip(PETAL_IN, PETAL_OUT)) + (255,)
        ImageDraw.Draw(layer).ellipse([cx - width / 2 * t, cy - length * t - 20 * S, cx + width / 2 * t, cy - 20 * S + 30 * S * (1 - t)], fill=colour)
    notch = 34 * S
    ImageDraw.Draw(layer).polygon([(cx - notch, cy - length - 30 * S), (cx + notch, cy - length - 30 * S), (cx, cy - length + 34 * S)], fill=(0, 0, 0, 0))
    return layer.rotate(-angle, center=(cx, cy), resample=Image.BICUBIC)

flower = Image.new("RGBA", (W, W), (0, 0, 0, 0))
for k in range(5):
    flower = Image.alpha_composite(flower, petal(k * 72))

# A soft pink glow under the flower
glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([cx - 300 * S, cy - 300 * S, cx + 300 * S, cy + 300 * S], fill=(240, 140, 186, 90))
glow = glow.filter(ImageFilter.GaussianBlur(70 * S))
img = Image.alpha_composite(img, Image.composite(glow, Image.new("RGBA", (W, W)), mask))
img = Image.alpha_composite(img, flower)

# Centre and stamens
d = ImageDraw.Draw(img)
for k in range(10):
    a = math.radians(k * 36 + 18)
    x, y = cx + math.cos(a) * 70 * S, cy + math.sin(a) * 70 * S
    d.line([(cx, cy), (x, y)], fill=(214, 96, 150, 255), width=6 * S)
    d.ellipse([x - 13 * S, y - 13 * S, x + 13 * S, y + 13 * S], fill=CENTER + (255,))
d.ellipse([cx - 38 * S, cy - 38 * S, cx + 38 * S, cy + 38 * S], fill=(232, 110, 160, 255))

out = sys.argv[1]
big = img.resize((1024, 1024), Image.LANCZOS)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        big.resize((size * scale, size * scale), Image.LANCZOS).save(f"{out}/icon_{size}x{size}{'@2x' if scale == 2 else ''}.png")
