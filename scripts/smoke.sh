#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Zkalan InkDeck.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
output_dir="$project_dir/artifacts/v${version%.*}"
mkdir -p "$output_dir" "$project_dir/.build"
marker=$(mktemp "$project_dir/.build/smoke-start.XXXXXX")
# LaunchServices gives the bundle normal foreground activation after a name/id change.
open -n -W --env "TRACKPAD_INK_ARTIFACTS=$output_dir" "$app_dir" --args --smoke-test
python3 - "$output_dir/smoke-results.json" "$marker" <<'PY'
import json, pathlib, sys
result, marker = map(pathlib.Path, sys.argv[1:])
if not result.exists() or result.stat().st_mtime_ns < marker.stat().st_mtime_ns:
    raise SystemExit('Smoke test did not produce a fresh result; unlock the Mac and retry.')
checks = {key: value for key, value in json.loads(result.read_text()).items() if type(value) is bool}
failed = [key for key, passed in checks.items() if not passed]
print(f'{sum(checks.values())}/{len(checks)} application checks passed.')
if not checks or failed:
    raise SystemExit('Failed: ' + ', '.join(failed))
PY
