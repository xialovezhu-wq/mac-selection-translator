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
