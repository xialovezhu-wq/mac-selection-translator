import json
import queue
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "build/SpeechHelper.app/Contents/MacOS/SpeechHelper"


class SpeechProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not HELPER.exists():
            raise unittest.SkipTest("Build speech helper first")
        cls.catalog = json.loads(subprocess.check_output([str(HELPER), "--catalog"], text=True))

    def render_with_open_stdin(self, language, voice):
        if not any(v["language"] == language and v["recommended"] for v in self.catalog):
            self.skipTest("No installed reading voice for " + language)
        with tempfile.TemporaryDirectory() as directory:
            request = {"requestId": "protocol-fixture", "text": "children went responses",
                       "language": language, "voiceIdentifier": voice, "rate": 0.5,
                       "outputPath": str(Path(directory) / "sample.wav")}
            process = subprocess.Popen([str(HELPER), "--render"], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            events = queue.Queue()
            def read_events():
                for line in process.stdout:
                    events.put(json.loads(line))
            reader = threading.Thread(target=read_events, daemon=True)
            reader.start()
            try:
                process.stdin.write(json.dumps(request) + "\n")
                process.stdin.flush()
                # Deliberately keep stdin OPEN, matching the Hammerspoon stream.
                first = events.get(timeout=5)
                self.assertEqual(first["event"], "resolved")
                self.assertEqual(first["voice"]["language"], language)
                process.wait(timeout=15)
                reader.join(timeout=2)
                collected = [first]
                while not events.empty(): collected.append(events.get_nowait())
                self.assertEqual(process.returncode, 0)
                self.assertEqual(collected[-1]["event"], "finished")
                self.assertGreater(collected[-1]["frames"], 0)
                self.assertGreater(Path(request["outputPath"]).stat().st_size, 1000)
                for event in collected:
                    self.assertNotIn("text", event)
                    self.assertNotIn(request["text"], json.dumps(event))
                return first
            finally:
                if process.poll() is None:
                    process.terminate(); process.wait(timeout=3)
                process.stdin.close(); process.stdout.close()

    def test_streaming_input_starts_without_waiting_for_eof(self):
        voice = next((v for v in self.catalog if v["language"] == "en-GB" and v["recommended"]), None)
        if not voice: self.skipTest("British voice not installed")
        result = self.render_with_open_stdin("en-GB", voice["identifier"])
        self.assertEqual(result["voice"]["identifier"], voice["identifier"])
        self.assertEqual(result["rate"], .5)

    def test_missing_voice_reports_same_accent_fallback(self):
        result = self.render_with_open_stdin("en-GB", "com.apple.missing.test-fixture")
        self.assertTrue(result["fallbackReason"])
        self.assertEqual(result["requestedVoice"], "com.apple.missing.test-fixture")

    def test_american_voice_is_instantiated_in_its_own_accent(self):
        voice = next((v for v in self.catalog if v["language"] == "en-US" and v["recommended"]), None)
        if not voice: self.skipTest("American voice not installed")
        result = self.render_with_open_stdin("en-US", voice["identifier"])
        self.assertEqual(result["voice"]["identifier"], voice["identifier"])

    def test_legacy_wpm_is_rejected_instead_of_becoming_av_rate(self):
        request = {"requestId": "bad-rate", "text": "responses", "language": "en-GB", "rate": 185}
        result = subprocess.run([str(HELPER), "--speak"], input=json.dumps(request)+"\n",
                                text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["error"], "invalidRate")


if __name__ == "__main__":
    unittest.main()
