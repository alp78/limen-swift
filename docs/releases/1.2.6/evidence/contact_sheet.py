#!/usr/bin/env python3
"""A contact sheet of every page of a Limen PDF, and a check of the cover's contents against the pages.

The Android repository's _scratch/annex-bench/contact_sheet.py is not on this Mac, so this does the
same two things with PyMuPDF: renders every page small into one grid, and reads the contents panel
on the cover (title ... page number) and checks that each named page carries the title.
"""
import re
import sys
from pathlib import Path

import fitz  # PyMuPDF
from PIL import Image

pdf_path = Path(sys.argv[1])
out = Path(sys.argv[2]) if len(sys.argv) > 2 else pdf_path.with_suffix(".contact.png")
columns = int(sys.argv[3]) if len(sys.argv) > 3 else 8
doc = fitz.open(pdf_path)
pages = [doc[i] for i in range(doc.page_count)]
zoom = 0.28
tiles = [p.get_pixmap(matrix=fitz.Matrix(zoom, zoom)) for p in pages]
w, h = tiles[0].width, tiles[0].height
rows = (len(tiles) + columns - 1) // columns
sheet = Image.new("RGB", (columns * (w + 6) + 6, rows * (h + 6) + 6), (120, 124, 132))
for i, t in enumerate(tiles):
    img = Image.frombytes("RGB", (t.width, t.height), t.samples)
    sheet.paste(img, (6 + (i % columns) * (w + 6), 6 + (i // columns) * (h + 6)))
sheet.save(out)
print(f"contact sheet {out} ({doc.page_count} pages, {pdf_path.stat().st_size} bytes)")

sizes = {(round(p.rect.width), round(p.rect.height)) for p in pages}
print(f"page sizes: {sorted(sizes)}")

# The cover's contents: on page 1 or 2, a line whose last word is a page number at the right edge
# and whose other words are the title. Lines are rebuilt from the words by baseline, because the
# text order of a page is not the reading order when two faces share a line.
def lines_of(page):
    rows = {}
    for x0, y0, x1, y1, word, *_ in page.get_text("words"):
        rows.setdefault(round(y1), []).append((x0, word))
    return [(" ".join(w for _, w in sorted(ws)), max(x for x, _ in ws)) for _, ws in sorted(rows.items())]

contents = []
for page in pages[:2]:
    for line, right in lines_of(page):
        m = re.fullmatch(r"(.+?)\s+(\d{1,3})", line)
        if m and right > 480 and "/" not in line and int(m.group(2)) <= doc.page_count:
            contents.append((m.group(1).strip(), int(m.group(2))))
missing = []
for title, number in contents:
    page_text = re.sub(r"\s+", " ", pages[number - 1].get_text("text"))
    if title not in page_text and title.upper() not in page_text:
        missing.append((title, number))
print(f"contents entries read: {len(contents)}; entries whose named page does not carry the title: {len(missing)}")
for m in missing:
    print("  missing:", m)
fonts = set()
for p in pages:
    for f in p.get_fonts():
        fonts.add(f[3])
print(f"fonts: {sorted(fonts)}")
images = 0
masked = 0
for p in pages:
    for info in p.get_images(full=True):
        images += 1
        if info[1] != 0:
            masked += 1
print(f"image objects placed: {images}, with a soft mask: {masked}")
