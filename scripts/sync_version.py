#!/usr/bin/env python3
"""Copy the central addon version into every client TOC."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
source = (root / "version.lua").read_text()
match = re.search(r'^NS\.VERSION = "([0-9]+(?:\.[0-9]+)+)"$', source, re.MULTILINE)
if not match:
    raise SystemExit("No valid NS.VERSION found in version.lua")
version = match.group(1)
tocs = sorted(root.glob("Quester*.toc"))
updates = []
for toc in tocs:
    content, count = re.subn(r"^## Version:.*$", "## Version: " + version,
                             toc.read_text(), flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected exactly one Version field in {toc.name}")
    updates.append((toc, content))
for toc, content in updates:
    if toc.read_text() != content:
        toc.write_text(content)
print(f"Version {version} synchronized across {len(tocs)} TOCs.")
