#!/usr/bin/env python3
"""Keep the native app's explicit Xcode sources equal to SwiftPM's source tree.

Run after adding/moving app Swift files; --check is read-only and suitable for CI.
Only app Swift references, their build entries and the app source group are changed.
"""
import argparse
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "MSSQLStudio.xcodeproj/project.pbxproj"


def synchronized(source: str) -> str:
    pattern = r'^([A-F0-9]{24}) = \{ isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = "(Sources/MSSQLStudio/[^"\n]+\.swift)"; sourceTree = SOURCE_ROOT; \};\n'
    old = dict((path, identifier) for identifier, path in re.findall(pattern, source, re.M))
    old_ids = set(old.values())
    builds = re.findall(r'^([A-F0-9]{24}) = \{ isa = PBXBuildFile; fileRef = ([A-F0-9]{24}); \};\n', source, re.M)
    old_builds = {ref: build for build, ref in builds if ref in old_ids}
    paths = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "Sources/MSSQLStudio").rglob("*.swift"))
    def identifier(kind, path):
        return hashlib.sha256((kind + ":" + path).encode()).hexdigest()[:24].upper()
    refs = {path: old.get(path, identifier("source", path)) for path in paths}
    entries = {path: old_builds.get(refs[path], identifier("build", path)) for path in paths}
    source = re.sub(pattern, "", source, flags=re.M)
    for build in old_builds.values():
        source = re.sub(r'^' + build + r' = [^\n]+\n', "", source, flags=re.M)
    generated = "".join(
        f'{refs[path]} = {{ isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT; }};\n'
        f'{entries[path]} = {{ isa = PBXBuildFile; fileRef = {refs[path]}; }};\n'
        for path in paths
    )
    source = source.replace("objects = {\n", "objects = {\n" + generated, 1)
    group = "64292B1C2B2E13EAD8788FC8"
    phase = "BCE16DD0260827ECF338C787"
    group_pattern = r'(' + group + r' = \{ isa = PBXGroup; children = \()([^)]*)(\);)'
    match = re.search(group_pattern, source)
    if not match:
        raise ValueError("App source group is missing")
    retained = [item for item in match[2].split(",") if item and item not in old_ids]
    children = ",".join(list(refs.values()) + retained) + ","
    source = re.sub(group_pattern, lambda m: m[1] + children + m[3], source)
    phase_pattern = r'(' + phase + r' = \{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = \()([^)]*)(\);)'
    if not re.search(phase_pattern, source):
        raise ValueError("App source phase is missing")
    source = re.sub(phase_pattern, lambda m: m[1] + ",".join(entries.values()) + "," + m[3], source)
    return source


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    before = PROJECT.read_text()
    after = synchronized(before)
    if args.check:
        if before != after:
            parser.exit(1, "Xcode sources differ from SwiftPM. Run scripts/sync-xcode-sources.py\n")
        print("Xcode/SwiftPM app sources match.")
    else:
        PROJECT.write_text(after)
        print("Xcode app sources synchronized.")
