import importlib.util
import tempfile
import unittest
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))
spec = importlib.util.spec_from_file_location("install", PROJECT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_preserves_other_modules_and_updates_idempotently(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            original = 'otherModule = require("other_module")\n-- a user comment\n'
            (config / "init.lua").write_text(original)
            installer.install(config, True)
            first = (config / "init.lua").read_text()
            installer.install(config, True)
            second = (config / "init.lua").read_text()
            self.assertEqual(first, second)
            self.assertEqual(installer.remove_block(second), original)
            self.assertEqual(second.count(installer.BEGIN), 1)
            self.assertTrue((config / "mac-selection-translator/dictionary-helper").is_file())

    def test_malformed_markers_fail_before_editing(self):
        for text in [installer.BEGIN, installer.END, installer.END + installer.BEGIN,
                     installer.BEGIN + installer.END + installer.BEGIN + installer.END]:
            with self.assertRaises(ValueError):
                installer.remove_block(text)

    def test_speech_only_preserves_config_translation_and_personal_data(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            assets = config / "mac-selection-translator"
            assets.mkdir()
            preserved = {"init.lua": "-- original unrelated shortcuts\n",
                         "selection_logic.lua": "-- selection logic\n",
                         "english_lookup.lua": "-- English lookup\n",
                         "mac-selection-translator/dictionary-helper": "original binary",
                         "mac-selection-translator/english-index.json": "private fixture",
                         "mac-selection-translator/speech-preferences.json": '{"englishAccent":"en-GB"}'}
            for name, data in preserved.items(): (config / name).write_text(data)
            installer.install(config, True, speech_only=True)
            for name, data in preserved.items(): self.assertEqual((config / name).read_text(), data)
            backup = next((config / "backups").iterdir())
            import json
            paths = {row["path"] for row in json.loads((backup / "manifest.json").read_text())}
            self.assertEqual(paths, {"selection_translator.lua", "selection_speech.lua", "speech_logic.lua", "mac-selection-translator/SpeechHelper.app"})


if __name__ == "__main__":
    unittest.main()
