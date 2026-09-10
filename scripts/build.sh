#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Zkalan InkDeck.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/.build/module-cache"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/InkModel.swift" "$project_dir/Sources/InkRenderer.swift" "$project_dir/Sources/CanvasView.swift" \
  "$project_dir/Sources/DesktopOverlay.swift" "$project_dir/Sources/App.swift" "$project_dir/Sources/main.swift" \
  -framework AppKit -framework CoreGraphics -o "$app_dir/Contents/MacOS/ZkalanInkDeck"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ZkalanInkDeck</string>
<key>CFBundleIdentifier</key><string>io.github.zkalan.inkdeck</string>
<key>CFBundleName</key><string>Zkalan InkDeck</string>
<key>CFBundleDisplayName</key><string>Zkalan InkDeck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
<key>NSSupportsAutomaticTermination</key><false/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
