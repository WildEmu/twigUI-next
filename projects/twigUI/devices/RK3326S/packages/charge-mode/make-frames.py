#!/usr/bin/env python3
"""Charge-mode frames for the GKD Pixel 2 (twigUI).

    make-frames.py            (from this directory; Pillow + DejaVu fonts, e.g. the Lima VM)

Writes sources/frames/level-NNN.bmp.gz (NNN = 0, 5 ... 100): twig's logo.bmp with the text and
battery below it, 8-bit BMPs in the panel's portrait orientation like logo.bmp, for fbv.
"""
import gzip, io, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "..", "..", "..", "packages", "twig", "install", "logo.bmp")
OUT = os.path.join(HERE, "sources", "frames")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
TEXT = "Charging, press Power to turn on"
LEVELS = range(0, 101, 5)


def frame(level):
    # Landscape 640x480, as the panel is seen; the logo comes from the splash picture itself.
    im = Image.open(LOGO).convert("RGB").transpose(Image.ROTATE_270)
    w, h = im.size
    d = ImageDraw.Draw(im)
    _, _, _, logo_bottom = im.getbbox()
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
    # Back to the panel's orientation, then 256 colours without dithering (fbv reads 8-bit BMPs).
    return im.transpose(Image.ROTATE_90).quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                                                  dither=Image.Dither.NONE)


def main():
    os.makedirs(OUT, exist_ok=True)
    for level in LEVELS:
        buf = io.BytesIO()
        frame(level).save(buf, format="BMP")
        with gzip.GzipFile(os.path.join(OUT, f"level-{level:03d}.bmp.gz"), "wb", mtime=0) as f:
            f.write(buf.getvalue())
    print(f"{len(LEVELS)} frames in {OUT}")


if __name__ == "__main__":
    main()
