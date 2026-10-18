#!/usr/bin/env python3
"""Builds api/_card/glyphs.bin, the Inter Tight Black glyphs api/card.js draws
link-preview cards with (no font engine on Vercel, so the letters are
pre-rendered here). Run again only if the font or the character set changes:

    python3 api/_card/make_glyphs.py

Needs Pillow (with raqm for kerning) and fontTools + brotli for the woff2.
Format: b"PSG1", uint32 BE header length, JSON header, then zlib-compressed
4-bit alpha bitmaps (two pixels per byte, high nibble first, rows padded).
"""
import json
import os
import struct
import zlib

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont, features

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "..", "site", "fonts", "InterTight-Black.woff2")
SIZE = 136
RANGES = [(0x20, 0x24F), (0x370, 0x3FF), (0x400, 0x4FF), (0x1E00, 0x1EFF), (0x2010, 0x2027)]
KERN_CHARS = [chr(c) for c in range(0x20, 0x7F)]


def main():
    cmap = TTFont(FONT).getBestCmap()
    font = ImageFont.truetype(FONT, SIZE, layout_engine=ImageFont.Layout.RAQM if features.check("raqm") else ImageFont.Layout.BASIC)
    ascent, descent = font.getmetrics()
    glyphs, blob = {}, bytearray()
    for lo, hi in RANGES:
        for cp in range(lo, hi + 1):
            if cp not in cmap:
                continue
            ch = chr(cp)
            advance = round(font.getlength(ch), 2)
            x0, y0, x1, y1 = font.getbbox(ch, anchor="ls")
            w, h = max(0, x1 - x0), max(0, y1 - y0)
            offset = len(blob)
            if w and h:
                image = Image.new("L", (w, h), 0)
                ImageDraw.Draw(image).text((-x0, -y0), ch, font=font, fill=255, anchor="ls")
                pixels = image.tobytes()
                for row in range(h):
                    line = pixels[row * w:(row + 1) * w]
                    for i in range(0, w, 2):
                        a = (line[i] + 8) // 17
                        b = (line[i + 1] + 8) // 17 if i + 1 < w else 0
                        blob.append((a << 4) | b)
            glyphs[cp] = [advance, x0, y0, w, h, offset]
    kern = {}
    if features.check("raqm"):
        widths = {c: font.getlength(c) for c in KERN_CHARS}
        for a in KERN_CHARS:
            for b in KERN_CHARS:
                k = round(font.getlength(a + b) - widths[a] - widths[b], 1)
                if abs(k) >= 0.5:
                    kern[a + b] = k
    header = json.dumps({"size": SIZE, "ascent": ascent, "descent": descent, "glyphs": glyphs, "kern": kern},
                        separators=(",", ":")).encode()
    out = os.path.join(HERE, "glyphs.bin")
    with open(out, "wb") as f:
        f.write(b"PSG1" + struct.pack(">I", len(header)) + header + zlib.compress(bytes(blob), 9))
    print(f"{len(glyphs)} glyphs, {len(kern)} kerning pairs, {os.path.getsize(out)} bytes -> {out}")


if __name__ == "__main__":
    main()
