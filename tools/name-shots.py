#!/usr/bin/env python3
"""Gives the screenshots exported from a result bundle their test-side names.

`xcresulttool export attachments` writes every attachment under a UUID and records the name the
test asked for in `manifest.json`, so the folder is unreadable until the two are put back together.
The UI smokes name each shot for the step it belongs to, and that is the name worth keeping.

Run through `make shots`, which exports the newest bundle first.
"""
import json
import pathlib
import re
import sys


def attachments(node):
    """Every attachment record, wherever the manifest happens to keep it."""
    if isinstance(node, dict):
        for entry in node.get("attachments", []) or []:
            yield entry
        for value in node.values():
            yield from attachments(value)
    elif isinstance(node, list):
        for value in node:
            yield from attachments(value)


def main() -> None:
    folder = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "DD/shots")
    manifest = folder / "manifest.json"
    if not manifest.exists():
        raise SystemExit(f"no manifest in {folder}")
    renamed = 0
    for entry in attachments(json.loads(manifest.read_text())):
        source = entry.get("exportedFileName")
        wanted = entry.get("suggestedHumanReadableName")
        if not source or not wanted:
            continue
        path = folder / source
        if not path.exists():
            continue
        # The runner appends an index and a UUID to keep names unique inside the bundle.
        path.rename(folder / re.sub(r"_\d+_[0-9A-F-]{36}", "", wanted))
        renamed += 1
    print(f"{renamed} screenshots named in {folder}")


if __name__ == "__main__":
    main()
