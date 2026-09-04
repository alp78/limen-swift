#!/usr/bin/env python3
"""Reduces libphonenumber's metadata to what the port's phone check reads.

Android validates and formats phone numbers with Google's libphonenumber, which has no iOS
equivalent in the platform. Its metadata file (Apache 2.0) is the part that matters: per
region, the calling code, the prefixes to strip, the national number patterns per type with
their possible lengths, the formats, and an example. This script reads the pinned release
`tools/PhoneNumberMetadata.xml` (v9.0.34, the version the Android build carries) and writes
`LimenKit/Resources/PhoneMetadata.json` for `InternationalPhone` to read. Run `make phones`
after fetching a new release:

    curl -sSL -o tools/PhoneNumberMetadata.xml \
      https://raw.githubusercontent.com/google/libphonenumber/v9.0.34/resources/PhoneNumberMetadata.xml
"""
from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SOURCE = HERE / "tools" / "PhoneNumberMetadata.xml"
OUT = HERE / "LimenKit" / "Resources" / "PhoneMetadata.json"

TYPES = ["fixedLine", "mobile", "pager", "tollFree", "premiumRate", "sharedCost", "personalNumber", "voip", "uan", "voicemail"]


def pattern(text: str | None) -> str | None:
    if text is None:
        return None
    return re.sub(r"\s+", "", text)


def lengths(node: ET.Element | None) -> list[int]:
    """`national="9"`, `national="[7-9]"`, `national="6,8,[10-12]"` to a plain list."""
    if node is None:
        return []
    spec = node.attrib.get("national", "")
    result: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        match = re.match(r"^\[(\d+)-(\d+)\]$", part)
        if match:
            result.extend(range(int(match.group(1)), int(match.group(2)) + 1))
        else:
            result.append(int(part))
    return result


def main() -> None:
    root = ET.parse(SOURCE).getroot()
    territories = {}
    for node in root.iter("territory"):
        code = node.attrib["id"]
        if len(code) != 2:
            continue
        general = node.find("generalDesc/nationalNumberPattern")
        if general is None:
            continue
        entry = {
            "countryCode": int(node.attrib["countryCode"]),
            "internationalPrefix": node.attrib.get("internationalPrefix"),
            "nationalPrefix": node.attrib.get("nationalPrefix"),
            "nationalPrefixForParsing": pattern(node.attrib.get("nationalPrefixForParsing")),
            "nationalPrefixTransformRule": node.attrib.get("nationalPrefixTransformRule"),
            "nationalPrefixFormattingRule": node.attrib.get("nationalPrefixFormattingRule"),
            "mainCountryForCode": node.attrib.get("mainCountryForCode") == "true",
            "generalPattern": pattern(general.text),
            "types": {},
            "formats": [],
        }
        for kind in TYPES:
            typed = node.find(kind)
            if typed is None:
                continue
            national = typed.find("nationalNumberPattern")
            if national is None or pattern(national.text) == "NA":
                continue
            example = typed.find("exampleNumber")
            entry["types"][kind] = {
                "pattern": pattern(national.text),
                "lengths": lengths(typed.find("possibleLengths")),
                "example": example.text.strip() if example is not None and example.text else None,
            }
        for fmt in node.findall("availableFormats/numberFormat"):
            leading = [pattern(item.text) for item in fmt.findall("leadingDigits")]
            format_node = fmt.find("format")
            entry["formats"].append({
                "pattern": pattern(fmt.attrib["pattern"]),
                "leadingDigits": leading[-1] if leading else None,
                "format": format_node.text.strip() if format_node is not None and format_node.text else "",
                "nationalPrefixFormattingRule": fmt.attrib.get("nationalPrefixFormattingRule"),
            })
        territories[code] = entry
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(territories, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    print(f"{len(territories)} territories, {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
