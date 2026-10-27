#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
python3 -m unittest discover -s tests -p 'test_*.py'
case "$(uname -m)" in
  arm64) speech_test_target=arm64-apple-macosx15.0 ;;
  *) speech_test_target=x86_64-apple-macosx15.0 ;;
esac
xcrun swiftc -O -parse-as-library -target "$speech_test_target" src/SpeechEngine.swift tests/SpeechPolicyTests.swift -o build/test-speech-policy
build/test-speech-policy
if command -v hs >/dev/null 2>&1; then
  # Pass the path as a Lua literal via JSON escaping; do not interpolate selected text.
  logic_file="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1],ensure_ascii=False))' "$project_dir/tests/test_logic.lua")"
  hs -c "dofile($logic_file)"
  speech_file="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1],ensure_ascii=False))' "$project_dir/tests/test_speech_logic.lua")"
  hs -c "dofile($speech_file)"
else
  echo "Hammerspoon CLI unavailable; run tests/test_logic.lua in the Hammerspoon console."
fi
