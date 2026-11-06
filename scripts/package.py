#!/usr/bin/env python3
"""Build a CurseForge upload ZIP with a stable Quester/ root folder."""
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile


def main():
    root = Path(__file__).resolve().parent.parent
    source = (root / "version.lua").read_text()
    match = re.search(r'^NS\.VERSION = "([0-9]+(?:\.[0-9]+)+)"$', source, re.MULTILINE)
    if not match:
        raise SystemExit("No valid NS.VERSION found in version.lua")
    version = match.group(1)
    tocs = sorted(root.glob("Quester*.toc"))
    if root / "Quester.toc" not in tocs:
        raise SystemExit("Missing Quester.toc")
    for toc in tocs:
        content = toc.read_text()
        if re.findall(r"^## Version:\s*(\S+)\s*$", content, re.MULTILINE) != [version]:
            raise SystemExit(f"Version mismatch in {toc.name}; run scripts/sync_version.py")
        for line in content.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                if not (root / line.replace("\\", "/")).is_file():
                    raise SystemExit(f"Missing file in {toc.name}: {line}")

    files = set(tocs)
    for pattern in ("*.lua", "*.xml", "Media/**/*"):
        files.update(path for path in root.glob(pattern) if path.is_file())
    files.update(root / name for name in ("LICENSE", "README.md", "changelog.md"))
    output = root / "dist" / f"Quester-{version}.zip"
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, "Quester/" + path.relative_to(root).as_posix())
    print(f"Created {output}")


if __name__ == "__main__":
    main()
