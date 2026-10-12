#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/MSSQLStudio-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swift_tool="$(xcrun --find swift)"
export DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib
# Native suites share AppKit focus, theme, hover panels and the event loop.
# Serialize execution across suites; build compilation remains parallel.
"$swift_tool" test --no-parallel --package-path "$project_dir" --scratch-path "$test_dir" "$@"
