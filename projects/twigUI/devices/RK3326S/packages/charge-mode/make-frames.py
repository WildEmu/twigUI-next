#!/usr/bin/env python3
"""Charge-mode frames for the GKD Pixel 2 (twigUI).

    make-frames.py            (from this directory; Pillow + DejaVu fonts, e.g. the Lima VM)

Writes sources/frames/level-NNN.bmp.gz (NNN = 0, 5 ... 100): twig's logo.bmp with the text and
battery below it, and booting.bmp.gz (the logo and "Loading frontend…", shown when the power key
boots); 8-bit BMPs in the panel's portrait orientation like logo.bmp, for fbv.
"""
import gzip, io, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "..", "..", "..", "packages", "twig", "install", "logo.bmp")
OUT = os.path.join(HERE, "sources", "frames")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
TEXT = "Charging, press Power to turn on"
BOOT_TEXT = "Loading frontend…"
LEVELS = range(0, 101, 5)


def logo():
    # Landscape 640x480, as the panel is seen; the logo comes from the splash picture itself.
    im = Image.open(LOGO).convert("RGB").transpose(Image.ROTATE_270)
    return im, ImageDraw.Draw(im), im.getbbox()[3]


def panel(im):
    # Back to the panel's orientation, then 256 colours without dithering (fbv reads 8-bit BMPs).
    return im.transpose(Image.ROTATE_90).quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                                                  dither=Image.Dither.NONE)


def booting():
    im, d, logo_bottom = logo()
    f = ImageFont.truetype(FONT, 22)
    d.text(((im.size[0] - d.textlength(BOOT_TEXT, font=f)) / 2, logo_bottom + 34), BOOT_TEXT,
           font=f, fill=(170, 170, 170))
    return panel(im)


def frame(level):
    im, d, logo_bottom = logo()
    w = im.size[0]
    small = ImageFont.truetype(FONT, 22)
    y = logo_bottom + 34
    d.text(((w - d.textlength(TEXT, font=small)) / 2, y), TEXT, font=small, fill=(170, 170, 170))
    asc, desc = small.getmetrics()
    y += asc + desc + 26
    bw, bh, nub = 96, 44, 8
    pf = ImageFont.truetype(FONTB, 30)
    pct = f"{level}%"
    total = bw + nub + 18 + d.textlength(pct, font=pf)
    x = (w - total) / 2
    d.rectangle([x, y, x + bw, y + bh], outline=(235, 235, 235), width=3)
    d.rectangle([x + bw, y + bh * 0.3, x + bw + nub, y + bh * 0.7], fill=(235, 235, 235))
    if level > 0:
        inner = 6
        fill = (220, 60, 60) if level < 15 else (80, 200, 90)
        d.rectangle([x + inner, y + inner, x + inner + (bw - 2 * inner) * level / 100, y + bh - inner], fill=fill)
    pasc, pdesc = pf.getmetrics()
    d.text((x + bw + nub + 18, y + (bh - pasc - pdesc) / 2), pct, font=pf, fill=(235, 235, 235))
    return panel(im)


def save(im, name):
    buf = io.BytesIO()
    im.save(buf, format="BMP")
    with gzip.GzipFile(os.path.join(OUT, f"{name}.bmp.gz"), "wb", mtime=0) as f:
        f.write(buf.getvalue())


def main():
    os.makedirs(OUT, exist_ok=True)
    for level in LEVELS:
        save(frame(level), f"level-{level:03d}")
    save(booting(), "booting")
    print(f"{len(LEVELS) + 1} frames in {OUT}")


if __name__ == "__main__":
    main()
