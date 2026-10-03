#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$project_dir/build/LanguagePreparation.app" ]; then
  echo "Run bash scripts/build.sh first" >&2
  exit 1
fi
open "$project_dir/build/LanguagePreparation.app"
