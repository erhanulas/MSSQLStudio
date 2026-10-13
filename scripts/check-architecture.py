#!/usr/bin/env python3
"""Check dependency and source-size boundaries of the modular source tree."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
errors = []
for module in ("MSSQLStudio", "SQLServerKit", "SQLTextCore"):
    for path in (root / "Sources" / module).rglob("*.swift"):
        source = path.read_text()
        imports = set(re.findall(r"(?m)^import (\w+)", source))
        if module == "SQLTextCore" and imports - {"Foundation"}:
            errors.append(f"{path.relative_to(root)}: SQLTextCore only depends on Foundation")
        if module == "SQLServerKit" and imports & {"AppKit", "SwiftUI", "MSSQLStudio"}:
            errors.append(f"{path.relative_to(root)}: database/core code cannot depend on UI")
        if len(source.splitlines()) > 1100:
            errors.append(f"{path.relative_to(root)}: exceeds 1,100 lines; review responsibility boundaries")
    if module != "SQLTextCore":
        for path in (root / "Sources" / module).glob("*.swift"):
            errors.append(f"{path.relative_to(root)}: place source in its feature/domain directory")

# Source moves must also update build, signing and release harness references.
for folder in (root / "scripts", root / ".github/workflows"):
    for path in folder.rglob("*"):
        if path.is_file() and path.suffix in {".py", ".sh", ".yml", ".yaml"}:
            for reference in re.findall(r"Sources/[A-Za-z0-9_./-]+\.swift", path.read_text()):
                if not (root / reference).is_file():
                    errors.append(f"{path.relative_to(root)}: missing source reference {reference}")

if errors:
    sys.exit("\n".join(errors))
subprocess.run([sys.executable, str(root / "scripts/sync-xcode-sources.py"), "--check"], check=True)
print("Architecture boundaries passed.")
