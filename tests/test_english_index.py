import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("english_index", ROOT / "scripts/build_english_index.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EnglishIndexTests(unittest.TestCase):
    def test_exact_context_lookup_preserves_personal_meanings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "bank.csv", root / "private/english-index.json"
            rows = [
                {"id": "SYNTHETIC-001", "item": "Response", "type": "单词", "meaning": "反馈",
                 "source_sentence": "Thank you for your response.", "usage": "例句中的回应。", "last_seen": "2026-10-01"},
                {"id": "SYNTHETIC-002", "item": "response", "type": "熟词僻义", "meaning": "应对措施",
                 "source_sentence": "This is our response to the problem.", "last_seen": "2026-10-03"},
                {"id": "SYNTHETIC-003", "item": "as ... as", "type": "句型", "meaning": "同样"},
            ]
            with source.open("w", newline="", encoding="utf-8-sig") as file:
                writer = csv.DictWriter(file, fieldnames=module.FIELDS)
                writer.writeheader(); writer.writerows(rows)
            before = source.read_bytes()
            metadata = module.build(source, output)
            index = json.loads(output.read_text())
            self.assertEqual(metadata, {"rows": 3, "keys": 1})
            self.assertEqual(index["entries"]["response"][0]["meaning"], "应对措施")
            self.assertEqual(index["entries"]["response"][1]["source_sentence"], "Thank you for your response.")
            self.assertNotIn("sponse", index["entries"])
            self.assertEqual(before, source.read_bytes())
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_changed_source_rebuilds_and_removed_word_disappears(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "bank.csv", root / "index.json"
            def write(word, meaning):
                with source.open("w", newline="") as file:
                    writer = csv.DictWriter(file, fieldnames=module.FIELDS)
                    writer.writeheader(); writer.writerow({"id":"SYNTHETIC", "item":word, "type":"单词", "meaning":meaning})
            write("hello", "你好"); module.build(source, output)
            write("world", "世界"); module.build(source, output)
            index = json.loads(output.read_text())
            self.assertNotIn("hello", index["entries"])
            self.assertEqual(index["entries"]["world"][0]["meaning"], "世界")

    def test_invalid_schema_fails_without_replacing_the_index(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "bank.csv", root / "index.json"
            source.write_text("wrong,columns\n1,2\n")
            output.write_text("old index")
            with self.assertRaises(ValueError): module.build(source, output)
            self.assertEqual(output.read_text(), "old index")

    def test_normalization_does_not_stem_or_substring_match(self):
        self.assertEqual(module.normalize("  RESPONSE \n"), "response")
        self.assertNotEqual(module.normalize("responses"), "response")


if __name__ == "__main__":
    unittest.main()
