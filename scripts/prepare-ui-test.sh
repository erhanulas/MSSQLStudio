#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
archive="${1:?Pass the release ZIP to test}"
test_dir="$(mktemp -d /tmp/MSSQLStudio-ui.XXXXXX)"
ditto -x -k "$archive" "$test_dir"
app="$test_dir/MSSQLStudio.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.mssqlstudio.uitest' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName MSSQL Studio UI Test' "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "$app"
