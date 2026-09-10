#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
mkdir -p "$project_dir/.build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/InkModel.swift" "$project_dir/Tests/InkEngineTests.swift" \
  -o "$project_dir/.build/ink-model-tests"
"$project_dir/.build/ink-model-tests"
