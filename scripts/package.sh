#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Zkalan InkDeck.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
release_dir="$project_dir/release"
mkdir -p "$release_dir" "$project_dir/.build"
stage_dir=$(mktemp -d "$project_dir/.build/package-$version.XXXXXX")
codesign --verify --deep --strict "$app_dir"
ditto "$app_dir" "$stage_dir/Zkalan InkDeck.app"
cp "$project_dir/README.md" "$project_dir/CHANGELOG.md" "$project_dir/PROVENANCE.md" "$stage_dir/"
ditto "$project_dir/artifacts/v$version" "$stage_dir/artifacts/v$version"
ditto -c -k --norsrc "$stage_dir" "$release_dir/ZkalanInkDeck-$version-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$project_dir/artifacts/v$version" "$release_dir/ZkalanInkDeck-$version-validation.zip"
cd "$release_dir"
shasum -a 256 "ZkalanInkDeck-$version-macOS-arm64.zip" "ZkalanInkDeck-$version-validation.zip" > SHA256SUMS.txt
print -r -- "$release_dir"
