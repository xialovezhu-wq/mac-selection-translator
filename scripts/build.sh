#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build"
case "$(uname -m)" in
  arm64) build_target=arm64-apple-macosx15.0 ;;
  x86_64) build_target=x86_64-apple-macosx15.0 ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac
xcrun swiftc -O -parse-as-library -target "$build_target" \
  "$project_dir/src/DictionaryHelper.swift" -o "$project_dir/build/dictionary-helper"
codesign --force --sign - "$project_dir/build/dictionary-helper"
echo "Built $project_dir/build/dictionary-helper"
preparation_app="$project_dir/build/LanguagePreparation.app"
mkdir -p "$preparation_app/Contents/MacOS"
xcrun swiftc -O -parse-as-library -target "$build_target" \
  "$project_dir/src/LanguagePreparation.swift" -o "$preparation_app/Contents/MacOS/LanguagePreparation"
cat > "$preparation_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mac-selection-translator.language-preparation</string>
<key>CFBundleName</key><string>整句离线翻译准备</string>
<key>CFBundleExecutable</key><string>LanguagePreparation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$preparation_app"
echo "Built $preparation_app"
