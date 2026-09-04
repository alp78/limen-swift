#!/usr/bin/env python3
"""Rewrites an Android VectorDrawable as an SVG, path data verbatim.

VectorDrawable path data is SVG path data, and its fills, strokes and group scales have direct
SVG spellings, so the seal reaches the asset catalog without being redrawn.
"""
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "{http://schemas.android.com/apk/res/android}"


def attr(node: ET.Element, name: str, default: str | None = None) -> str | None:
    return node.attrib.get(NS + name, default)


def convert(source: Path, target: Path) -> None:
    root = ET.parse(source).getroot()
    width = attr(root, "viewportWidth")
    height = attr(root, "viewportHeight")
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">']

    def emit(node: ET.Element, indent: str) -> None:
        for child in node:
            tag = child.tag
            if tag == "group":
                transforms = []
                tx, ty = attr(child, "translateX", "0"), attr(child, "translateY", "0")
                if tx != "0" or ty != "0":
                    transforms.append(f"translate({tx} {ty})")
                sx, sy = attr(child, "scaleX", "1"), attr(child, "scaleY", "1")
                if sx != "1" or sy != "1":
                    transforms.append(f"scale({sx} {sy})")
                out.append(f'{indent}<g transform="{" ".join(transforms)}">')
                emit(child, indent + "  ")
                out.append(f"{indent}</g>")
            elif tag == "path":
                parts = [f'd="{attr(child, "pathData")}"']
                fill = attr(child, "fillColor")
                parts.append(f'fill="{fill}"' if fill else 'fill="none"')
                stroke = attr(child, "strokeColor")
                if stroke:
                    parts.append(f'stroke="{stroke}"')
                    parts.append(f'stroke-width="{attr(child, "strokeWidth", "1")}"')
                    cap = attr(child, "strokeLineCap")
                    if cap:
                        parts.append(f'stroke-linecap="{cap}"')
                    join = attr(child, "strokeLineJoin")
                    if join:
                        parts.append(f'stroke-linejoin="{join}"')
                out.append(f"{indent}<path {' '.join(parts)}/>")

    emit(root, "  ")
    out.append("</svg>")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(out) + "\n", encoding="utf-8")


if __name__ == "__main__":
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
