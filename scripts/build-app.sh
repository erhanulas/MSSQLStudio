#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/scripts/check-architecture.py"
output_dir="${1:-$project_dir/releases}"
build_dir="$(mktemp -d /tmp/MSSQLStudio-build.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$output_dir"
xcodebuild -project "$project_dir/MSSQLStudio.xcodeproj" -scheme MSSQLStudio -configuration Release -derivedDataPath "$build_dir" "MSSQL_UPDATE_FEED_URL=${MSSQL_UPDATE_FEED_URL:-https://github.com/erhanulas/MSSQLStudio/releases/latest/download/update.json}" build
app_path="$build_dir/Build/Products/Release/MSSQLStudio.app"
credential_dir="${RUNNER_TEMP:-$build_dir}/MSSQLStudio-credential-v1-${GITHUB_RUN_ID:-local}"
python3 "$project_dir/scripts/credential-agent.py" --output "$credential_dir" --app "$app_path"
cp "$credential_dir/MSSQLStudio-CredentialAgent-v1.zip" "$output_dir/"
python3 "$project_dir/scripts/signing.py" sign "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
# File Provider/iCloud may attach FinderInfo to unpacked .app files and break signatures.
ditto -c -k --keepParent --norsrc "$app_path" "$output_dir/MSSQLStudio-$version.zip"
echo "Created $output_dir/MSSQLStudio-$version.zip"

"$project_dir/scripts/build-pkg.sh" "$output_dir/MSSQLStudio-$version.zip" "$output_dir"
