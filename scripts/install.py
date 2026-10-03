#!/usr/bin/env python3
"""Install only this module; preserve all unrelated Hammerspoon configuration."""
import argparse
import datetime
import json
import shutil
import sys
from pathlib import Path
from build_english_index import build as build_english_index

BEGIN = "-- BEGIN mac-selection-translator (managed)"
END = "-- END mac-selection-translator (managed)"
PROJECT = Path(__file__).resolve().parent.parent
FILES = ["selection_logic.lua", "selection_translator.lua", "english_lookup.lua"]


def remove_block(text):
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError("Managed block is malformed; refusing to change init.lua")
    if BEGIN not in text:
        return text
    start, end_marker = text.index(BEGIN), text.index(END)
    if end_marker < start:
        raise ValueError("Managed block markers are reversed")
    end = end_marker + len(END)
    if text[end:end + 1] == "\n":
        end += 1
    return text[:start] + text[end:]


def block():
    return f'''{BEGIN}
selectionTranslator = require("selection_translator")
selectionTranslatorStartOk, selectionTranslatorStartError = selectionTranslator.start()
if not selectionTranslatorStartOk then
  hs.printf("Selection translator: %s", tostring(selectionTranslatorStartError))
end
do
  local selectionTranslatorPreviousShutdown = hs.shutdownCallback
  hs.shutdownCallback = function()
    selectionTranslator.stop()
    if selectionTranslatorPreviousShutdown then selectionTranslatorPreviousShutdown() end
  end
end
{END}
'''


def install(config_dir, apply, english_root=None):
    binary = PROJECT / "build/dictionary-helper"
    if not binary.is_file():
        raise SystemExit("Run bash scripts/build.sh first")
    init = config_dir / "init.lua"
    original = init.read_text() if init.exists() else ""
    updated = remove_block(original)
    if updated and not updated.endswith("\n"):
        updated += "\n"
    updated += block()
    targets = [init] + [config_dir / file for file in FILES]
    private_dir = config_dir / "mac-selection-translator"
    targets += [private_dir / "dictionary-helper", private_dir / "build_english_index.py"]
    source = english_root.resolve() / "bank/master_bank.csv" if english_root else None
    if source and source.is_file():
        targets += [private_dir / "english-source.json", private_dir / "english-index.json"]
    if not apply:
        print(json.dumps({"mode": "preview", "changed_files": [str(p) for p in targets]}, indent=2))
        return
    config_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = config_dir / "backups" / ("mac-selection-translator-" + stamp)
    backup.mkdir(parents=True, mode=0o700)
    manifest = []
    for target in targets:
        relative = target.relative_to(config_dir)
        existed = target.exists()
        manifest.append({"path": str(relative), "existed": existed})
        if existed:
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
            saved.chmod(0o600)
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2))
    for file in FILES:
        shutil.copy2(PROJECT / "hammerspoon" / file, config_dir / file)
    private_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, private_dir / "dictionary-helper")
    (private_dir / "dictionary-helper").chmod(0o755)
    shutil.copy2(PROJECT / "scripts/build_english_index.py", private_dir / "build_english_index.py")
    if source and source.is_file():
        config = {"source": str(source), "python": sys.executable}
        config_path = private_dir / "english-source.json"
        config_path.write_text(json.dumps(config))
        config_path.chmod(0o600)
        build_english_index(source, private_dir / "english-index.json")
    temporary = config_dir / ".init-selection-translator.tmp"
    temporary.write_text(updated)
    temporary.chmod(init.stat().st_mode & 0o777 if init.exists() else 0o600)
    temporary.replace(init)
    print(json.dumps({"installed": True, "backup": str(backup), "changed_files": [str(p) for p in targets]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--config-dir", type=Path, default=Path.home() / ".hammerspoon")
    parser.add_argument("--english-root", type=Path, default=Path.home() / "Documents/kaoyan-english")
    args = parser.parse_args()
    install(args.config_dir, args.apply, args.english_root)
