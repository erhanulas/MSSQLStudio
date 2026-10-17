#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/scripts/check-architecture.py"
test_dir="$(mktemp -d /tmp/MSSQLStudio-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swift_tool="$(xcrun --find swift)"
export DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib
# Native suites share AppKit focus, theme, hover panels and the event loop.
# Serialize execution across suites; build compilation remains parallel.
if [ "$#" -eq 0 ]; then
  # NSApplication.stopModal leaves the shared AppKit loop unsuitable for later
  # async tests. Run this modal-loop regression in its own final process.
  modal_test='WindowInteraction123Tests/modalAlertRestoresMovedPositionAcrossNewInstances'
  "$swift_tool" test --no-parallel --package-path "$project_dir" --scratch-path "$test_dir" --skip "$modal_test" 2>&1 | tee "$test_dir/full.log"
  python3 - "$test_dir/full.log" 3 <<'PY'
import re,sys
from pathlib import Path
count=len(re.findall(r'Test run with \d+ tests? in \d+ suites? passed',Path(sys.argv[1]).read_text()))
if count!=int(sys.argv[2]):
    raise SystemExit(f"Incomplete test run: expected {sys.argv[2]} completed target summaries, got {count}.")
PY
  "$swift_tool" test --no-parallel --package-path "$project_dir" --scratch-path "$test_dir" --filter "$modal_test" 2>&1 | tee "$test_dir/modal.log"
  python3 - "$test_dir/modal.log" <<'PY'
import re,sys
from pathlib import Path
if not re.search(r'Test run with 1 test in 1 suite passed',Path(sys.argv[1]).read_text()):
    raise SystemExit("The isolated modal test did not complete.")
PY
else
  "$swift_tool" test --no-parallel --package-path "$project_dir" --scratch-path "$test_dir" "$@"
fi
