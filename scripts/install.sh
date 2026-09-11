#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Zkalan InkDeck.app"
applications_dir="$HOME/Applications"
installed_app="$applications_dir/Zkalan InkDeck.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
mkdir -p "$project_dir/.build/module-cache" "$project_dir/.backups" "$applications_dir"
codesign --verify --deep --strict "$app_dir"
xcrun swiftc -module-cache-path "$project_dir/.build/module-cache" "$project_dir/scripts/AppLifecycle.swift" -o "$project_dir/.build/app-lifecycle"
"$project_dir/.build/app-lifecycle" --quit
backup_dir=$(mktemp -d "$project_dir/.backups/before-$version.XXXXXX")
if [[ -d "$installed_app" ]]; then ditto "$installed_app" "$backup_dir/Zkalan InkDeck.app"; fi
drafts_dir="$HOME/Library/Application Support/TrackpadInk"
if [[ -d "$drafts_dir" ]]; then ditto "$drafts_dir" "$backup_dir/TrackpadInk"; fi
stage_dir=$(mktemp -d "$applications_dir/.inkdeck-install.XXXXXX")
ditto "$app_dir" "$stage_dir/Zkalan InkDeck.app"
codesign --verify --deep --strict "$stage_dir/Zkalan InkDeck.app"
if [[ -d "$installed_app" ]]; then mv "$installed_app" "$stage_dir/previous.app"; fi
if ! mv "$stage_dir/Zkalan InkDeck.app" "$installed_app"; then
    if [[ -d "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$installed_app"; fi
    exit 1
fi
# Keep the prior copy in the ignored backup; remove only this installation's staging files.
if [[ -d "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$backup_dir/replaced.app"; fi
rmdir "$stage_dir"
codesign --verify --deep --strict "$installed_app"
print -r -- "Installed Zkalan InkDeck $version; previous app and drafts backed up in .backups/."
open "$installed_app"
