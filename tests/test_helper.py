import json
import subprocess
import unittest
import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
HELPER = PROJECT / "build/dictionary-helper"


def query(text):
    result = subprocess.run([str(HELPER)], input=json.dumps({"text": text}),
                            text=True, capture_output=True, timeout=10, check=True)
    return json.loads(result.stdout)


class HelperTests(unittest.TestCase):
    def test_installed_bilingual_dictionary(self):
        for word in ["hello", "performance", "response", "beautiful", "mouse"]:
            with self.subTest(word=word):
                result = query(word)
                self.assertTrue(result["ok"])
                self.assertEqual(result["engine"], "apple_dictionary")
                self.assertTrue(any("\u3400" <= char <= "\u9fff" for char in result["result"]))
                self.assertIsNone(re.search("[A-Za-z]", result["result"]))

    def test_trim_preserves_identity(self):
        self.assertEqual(query("  hello\n")["result"], query("hello")["result"])

    def test_empty_null_and_oversize_are_rejected(self):
        for text in ["", " \n\t", "hello\x00", "x" * 2049, "😀" * 1025]:
            with self.subTest(length=len(text)):
                result = query(text)
                self.assertFalse(result["ok"])
                self.assertEqual(result["error"], "invalid_selection")

    def test_sentence_does_not_return_first_words_definition(self):
        result = query("A beautiful mouse reads the newspaper.")
        if result["ok"]:
            self.assertEqual(result["engine"], "apple_translation")
        else:
            self.assertIn(result["error"], ["language_pack_missing", "dictionary_miss", "translation_failed"])

    def test_dictionary_cannot_merge_distinct_words(self):
        result = query("look up")
        if result["ok"]:
            self.assertEqual(result["engine"], "apple_translation")

    def test_selected_commands_are_inert(self):
        sentinel = PROJECT / "tests/SHELL_MUST_NOT_RUN"
        self.assertFalse(sentinel.exists())
        query(f'"; $(touch {sentinel}); echo "')
        self.assertFalse(sentinel.exists())

    def test_malformed_json(self):
        p = subprocess.run([str(HELPER)], input="{broken", text=True,
                           capture_output=True, timeout=10, check=True)
        self.assertEqual(json.loads(p.stdout)["error"], "invalid_request")


if __name__ == "__main__":
    unittest.main()
