#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/MSSQLStudio-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swift_tool="$(xcrun --find swift)"
export DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib
"$swift_tool" test --package-path "$project_dir" --scratch-path "$test_dir" "$@"
