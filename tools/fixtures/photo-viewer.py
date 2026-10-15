#!/usr/bin/env python3
"""Seed/verify only three reserved records in a simulator's installed audit app.

Usage: python3 tools/fixtures/photo-viewer.py SIMULATOR_UDID [--verify]
No real photographs, production bundle, device, reset or network operation is used.
"""
import argparse
import copy
import hashlib
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import zlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("simulator")
parser.add_argument("--verify", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
bundle = "dev.peringer.limen.audit"

def container(kind):
    output = subprocess.check_output(["xcrun", "simctl", "get_app_container", args.simulator, bundle, kind], text=True).strip()
    path = Path(output).resolve()
    assert f"CoreSimulator/Devices/{args.simulator}/data/" in str(path), "Only a simulator container is allowed"
    return path

app = container("app")
assert plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"] == bundle
support = container("data") / "Library/Application Support"
manifest_path = support / "photo-viewer-fixture.json"
ids = ["photo-viewer-draft", "photo-viewer-final", "photo-viewer-exit"]
image_name = "synthetic-grid.png"

if args.verify:
    manifest = json.loads(manifest_path.read_text())
    for identifier in ids:
        record = json.loads((support / "protocols" / f"{identifier}.json").read_text())
        assert record["id"] == identifier
        assert record.get("contentRevision", 0) == manifest[identifier]["contentRevision"]
        assert record.get("evidenceFingerprint", "") == manifest[identifier]["evidenceFingerprint"]
        if identifier == "photo-viewer-exit":
            assert record["seedId"] == "photo-viewer-final"
            assert record.get("details", {}).get("roomPhotos", {}) == {}
        else:
            evidence = record["details"]["roomPhotos"]["photo-room"]
            assert len(evidence) == 1 and evidence[0]["file"] == image_name
            image = support / "photos" / identifier / image_name
            digest = hashlib.sha256(image.read_bytes()).hexdigest().upper()
            assert digest == evidence[0]["sha256"] == manifest[identifier]["imageSHA256"]
            print(f"UNCHANGED {identifier} {digest} {image}")
    print("All three fixture references, content revisions, finalized fingerprint and original photo hashes are unchanged.")
    raise SystemExit(0)

subprocess.run(["xcrun", "simctl", "terminate", args.simulator, bundle], capture_output=True, check=False)

# A deterministic 1600 x 1200 RGB image: four different quadrants, grid, outer border and cross.
# The full frame and its crop are visibly distinguishable at every zoom without real evidence.
width, height = 1600, 1200
colours = [(190, 75, 70), (55, 135, 100), (55, 95, 165), (220, 175, 65)]
rows = bytearray()
for y in range(height):
    rows.append(0)
    for x in range(width):
        colour = colours[(2 if y >= height // 2 else 0) + (1 if x >= width // 2 else 0)]
        if x < 12 or y < 12 or x >= width - 12 or y >= height - 12:
            colour = (0, 0, 0)
        elif abs(x - width // 2) < 5 or abs(y - height // 2) < 5:
            colour = (20, 20, 20)
        elif x % 100 < 3 or y % 100 < 3:
            colour = (245, 245, 245)
        rows.extend(colour)

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
image_hash = hashlib.sha256(png).hexdigest().upper()
canonical_source = (repo / "LimenKitTests/Fixtures/Compatibility/final.canonical.json").read_text().rstrip("\n")
template = json.loads(canonical_source)
compact = lambda value: json.dumps(value, ensure_ascii=False, separators=(",", ":"))
assert compact(template) == canonical_source, "Preserve the independently verified canonical byte order/escaping"

manifest = {}
(support / "protocols").mkdir(parents=True, exist_ok=True)
for identifier in ids:
    target = support / "protocols" / f"{identifier}.json"
    if target.exists():
        previous = json.loads(target.read_text())
        assert previous.get("address") == "Synthetic photo viewer fixture", "Refuse to replace an unrelated record"
    p = copy.deepcopy(template)
    p.update(id=identifier, kind="Exit" if identifier.endswith("exit") else "Entry", address="Synthetic photo viewer fixture", place="5000 Aarau", seedId="photo-viewer-final" if identifier.endswith("exit") else "", amendedFromId="", amendedFromFingerprint="", remarks="Synthetic UI fixture only", objects=[], defects=[], signatures=[], evidenceFingerprint="", deliveryReceipts=[], deliveryMetadataEpochMs=0, exportedEpochMs=0, deliveryRevision=0, exportHistory=[], saveSequence=0, contentRevision=1)
    room = p["rooms"][0]
    room.update(id="photo-room", name="Synthetic grid room", items=[], inspected=True)
    p["rooms"] = [room]
    p["details"].update(roomPhotos={}, readings=[], attachments=[], followUps=[], estimates={}, reservations={})
    p["finalizedEpochMs"] = 1791885600000 if identifier.endswith("final") else 0
    if not identifier.endswith("exit"):
        photo = {"file": image_name, "sha256": image_hash, "capturedEpochMs": 0, "source": "Gallery", "importedEpochMs": 1791885600000}
        p["details"]["roomPhotos"] = {"photo-room": [photo]}
        directory = support / "photos" / identifier
        directory.mkdir(parents=True, exist_ok=True)
        (directory / image_name).write_bytes(png)
    if p["finalizedEpochMs"]:
        p["evidenceFingerprint"] = hashlib.sha256((compact(p) + "photo/" + image_name + image_hash).encode()).hexdigest().upper()
    target.write_text(compact(p))
    manifest[identifier] = {"contentRevision": p["contentRevision"], "evidenceFingerprint": p["evidenceFingerprint"], "imageSHA256": image_hash if not identifier.endswith("exit") else None}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Seeded only {', '.join(ids)} in {support}")
print(f"Synthetic image: {width}x{height}, {len(png)} bytes, SHA256 {image_hash}")
