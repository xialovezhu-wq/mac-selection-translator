#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
speech_app="$project_dir/build/SpeechHelper.app"
mkdir -p "$speech_app/Contents/MacOS"
case "$(uname -m)" in
  arm64) build_target=arm64-apple-macosx15.0 ;;
  x86_64) build_target=x86_64-apple-macosx15.0 ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac
xcrun swiftc -O -parse-as-library -target "$build_target" \
  "$project_dir/src/SpeechEngine.swift" "$project_dir/src/SpeechSettings.swift" \
  "$project_dir/src/SpeechHelper.swift" -o "$speech_app/Contents/MacOS/SpeechHelper"
cat > "$speech_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mac-selection-translator.speech</string>
<key>CFBundleName</key><string>划词朗读设置</string>
<key>CFBundleExecutable</key><string>SpeechHelper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$speech_app"
echo "Built $speech_app"
