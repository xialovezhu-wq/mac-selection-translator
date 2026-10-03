#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
python3 -m unittest discover -s tests -p 'test_*.py'
if command -v hs >/dev/null 2>&1; then
  # Pass the path as a Lua literal via JSON escaping; do not interpolate selected text.
  logic_file="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1],ensure_ascii=False))' "$project_dir/tests/test_logic.lua")"
  hs -c "dofile($logic_file)"
else
  echo "Hammerspoon CLI unavailable; run tests/test_logic.lua in the Hammerspoon console."
fi
