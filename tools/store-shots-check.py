#!/usr/bin/env python3
"""Check a captured set of store screenshots and sort it into the listing's folders.

    python3 tools/store-shots-check.py DD/shots --device iphone69 --into _scratch/store-shots

The result bundle's screenshots, named by `make shots`, are `<lang>-NN-name.png` with the five
language tags the walk uses. Each language's eight shots are checked for their names and for the
pixel size the device class is uploaded at, then copied under `<into>/<device>/<locale>/`,
where the upload script reads them. No Pillow on this Mac: `sips` reads the sizes.
"""
import argparse
import os
import shutil
import subprocess
import sys

NAMES = ["01-home", "02-rooms", "03-defect-editor", "04-canton-overlay", "05-review", "06-signature", "07-record-cover", "08-photo-annex"]
LOCALES = {"en": "en-US", "fr": "fr-FR", "de": "de-DE", "it": "it", "rm": "rm"}
SIZES = {"iphone69": (1320, 2868), "ipad13": (2064, 2752)}


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], check=True, capture_output=True, text=True).stdout
    values = {}
    for line in out.splitlines():
        parts = line.strip().split(":")
        if len(parts) == 2 and parts[0] in ("pixelWidth", "pixelHeight"):
            values[parts[0]] = int(parts[1])
    return values["pixelWidth"], values["pixelHeight"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--device", required=True, choices=sorted(SIZES))
    ap.add_argument("--into", required=True)
    args = ap.parse_args()
    expected = SIZES[args.device]
    failures = []
    copied = 0
    for tag, locale in LOCALES.items():
        dest = os.path.join(args.into, args.device, locale)
        os.makedirs(dest, exist_ok=True)
        for old in os.listdir(dest):
            if old.endswith(".png"):
                os.remove(os.path.join(dest, old))
        for name in NAMES:
            file = f"{tag}-{name}.png"
            path = os.path.join(args.source, file)
            if not os.path.exists(path):
                failures.append(f"{locale}: {file} missing")
                continue
            actual = size(path)
            if actual != expected:
                failures.append(f"{locale}: {file} is {actual}, not {expected}")
                continue
            shutil.copy2(path, os.path.join(dest, file))
            copied += 1
    print(f"{copied} shots at {expected[0]} x {expected[1]} under {os.path.join(args.into, args.device)}")
    for failure in failures:
        print(failure)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
