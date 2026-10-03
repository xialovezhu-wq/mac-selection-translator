#!/usr/bin/env python3
import argparse
from pathlib import Path
from install import remove_block, FILES

parser = argparse.ArgumentParser()
parser.add_argument("--apply", action="store_true")
parser.add_argument("--config-dir", type=Path, default=Path.home() / ".hammerspoon")
args = parser.parse_args()
init = args.config_dir / "init.lua"
original = init.read_text() if init.exists() else ""
updated = remove_block(original)
owned = [args.config_dir / file for file in FILES]
owned += [args.config_dir / "mac-selection-translator" / file for file in
          ["dictionary-helper", "build_english_index.py", "english-source.json", "english-index.json"]]
if args.apply:
    # The live module should be stopped first using the command in README.
    if init.exists():
        init.write_text(updated)
    for file in owned:
        if file.exists():
            file.unlink()
    directory = args.config_dir / "mac-selection-translator"
    if directory.exists() and not any(directory.iterdir()):
        directory.rmdir()
    print("Removed the managed module. Other shortcuts and backups were preserved.")
else:
    print("Preview: remove the managed init.lua block and these files:")
    for file in owned:
        print(file)
    print("Use --apply to uninstall.")
