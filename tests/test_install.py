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


if __name__ == "__main__":
    unittest.main()
