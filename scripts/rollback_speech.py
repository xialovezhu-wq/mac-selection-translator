#!/usr/bin/env python3
"""Restore one speech-only backup; preserve voice preferences and study assets."""
import argparse
import json
import shutil
from pathlib import Path

ALLOWED = {"selection_translator.lua", "selection_speech.lua", "speech_logic.lua",
           "mac-selection-translator/SpeechHelper.app"}

parser = argparse.ArgumentParser()
parser.add_argument("backup", type=Path)
parser.add_argument("--config-dir", type=Path, default=Path.home() / ".hammerspoon")
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
rows = json.loads((args.backup / "manifest.json").read_text())
if {row["path"] for row in rows} != ALLOWED:
    raise SystemExit("This is not an exact speech-only backup; no files changed")
for row in rows:
    if row["existed"] and not (args.backup / row["path"]).exists():
        raise SystemExit("Backup is incomplete; no files changed")
if not args.apply:
    print("Restore only these speech files:")
    for row in rows:
        print(row["path"])
    print("Voice preferences, init.lua, translation assets, and English data will remain intact.")
else:
    for row in rows:
        target = args.config_dir / row["path"]
        if target.exists():
            shutil.rmtree(target) if target.is_dir() else target.unlink()
        if row["existed"]:
            saved = args.backup / row["path"]
            shutil.copytree(saved, target) if saved.is_dir() else shutil.copy2(saved, target)
    print("Speech files restored. Reload only selectionTranslator as described in docs/SPEECH.md.")
