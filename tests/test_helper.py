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

    def test_inflected_words_keep_native_dictionary_canonical_entries(self):
        for selected, canonical in [("idealists", "idealist"), ("Idealists", "idealist"),
                                    ("students", "student"), ("studies", "study"), ("boxes", "box")]:
            with self.subTest(selected=selected):
                result = query(selected)
                self.assertTrue(result["ok"], result)
                self.assertEqual(result["engine"], "apple_dictionary")
                self.assertEqual(result["lookupTerm"].lower(), canonical)
                self.assertEqual(result["result"], query(canonical)["result"])
                self.assertIsNone(re.search("[A-Za-z]", result["result"]))
        self.assertIn("理想主义者", query("idealists")["result"])

    def test_dictionary_parts_of_speech_are_present(self):
        for word, expected in [("idealists", "名词"), ("beautiful", "形容词"),
                               ("quickly", "副词"), ("students", "名词")]:
            with self.subTest(word=word):
                result = query(word)
                self.assertTrue(result["ok"], result)
                self.assertIn(expected, result["partsOfSpeech"])
                self.assertEqual(result["partOfSpeechSource"], "dictionary")
                self.assertEqual(result["selectionKind"], "word")

    def test_word_edge_punctuation_keeps_inflection_and_part_of_speech(self):
        for word in ["idealists,", "“idealists”", "(idealists)"]:
            with self.subTest(word=word):
                result = query(word)
                self.assertTrue(result["ok"], result)
                self.assertEqual(result["lookupTerm"], "idealist")
                self.assertIn("名词", result["partsOfSpeech"])
                self.assertIn("理想主义者", result["result"])

    def test_installed_sentence_engine_translates_entire_multi_sentence_selection(self):
        health = json.loads(subprocess.run([str(HELPER), "--health"], text=True,
                                          capture_output=True, timeout=10, check=True).stdout)
        if health["sentenceTranslation"] != "installed":
            self.skipTest("Apple English-Chinese language packs have not been prepared")
        text = "She studies English every morning. She wants to become a teacher."
        result = query(text)
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["engine"], "apple_translation")
        self.assertEqual(result["selectionKind"], "sentence")
        self.assertIn("英语", result["result"])
        self.assertTrue("老师" in result["result"] or "教师" in result["result"])

    def test_sentence_punctuation_does_not_make_a_partial_word_definition(self):
        result = query("Idealists hope to improve the world.")
        if result["ok"]:
            self.assertEqual(result["engine"], "apple_translation")
            self.assertIn("世界", result["result"])

    def test_explicit_sentence_mode_always_uses_translation(self):
        p = subprocess.run([str(HELPER)], input=json.dumps({"text": "I love you", "forceSentence": True}),
                           text=True, capture_output=True, timeout=10, check=True)
        result = json.loads(p.stdout)
        if result["ok"]:
            self.assertEqual(result["engine"], "apple_translation")
            self.assertEqual(result["result"], "我爱你")

    def test_inflection_references_resolve_to_chinese_glosses(self):
        for selected, canonical in [("children", "child"), ("went", "go")]:
            with self.subTest(selected=selected):
                result = query(selected)
                self.assertTrue(result["ok"], result)
                self.assertEqual(result["lookupTerm"], canonical)
                self.assertEqual(result["result"], query(canonical)["result"])

    def test_hyphenated_selection_cannot_fall_back_to_its_first_part(self):
        result = query("hello-world")
        if result["ok"]:
            self.assertEqual(result["engine"], "apple_translation")

    def test_unknown_word_does_not_crash_dictionary_services(self):
        result = query("quuxnotarealword")
        self.assertFalse(result["ok"])

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
