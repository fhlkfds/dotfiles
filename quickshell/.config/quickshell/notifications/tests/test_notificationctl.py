import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[5] / "hypr/.local/bin/notificationctl"
loader = importlib.machinery.SourceFileLoader("notificationctl", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
ctl = importlib.util.module_from_spec(spec)
loader.exec_module(ctl)


class NotificationCtlTests(unittest.TestCase):
    def test_safe_key_rejects_traversal(self):
        for value in ("../x", "1/a", "", "1-2.json"):
            with self.assertRaises(ValueError):
                ctl.safe_key(value)

    def test_parse_entry_requires_matching_key(self):
        entry = ctl.parse_entry(json.dumps({"key": "100-2", "summary": "ok"}), "100-2")
        self.assertEqual(entry["summary"], "ok")
        with self.assertRaises(ValueError):
            ctl.parse_entry(json.dumps({"key": "100-3"}), "100-2")

    def test_atomic_write_replaces_complete_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "entry.json"
            ctl.atomic_write(path, '{"one":1}')
            ctl.atomic_write(path, '{"two":2}')
            self.assertEqual(json.loads(path.read_text()), {"two": 2})

    def test_window_matching_prefers_exact_initial_class(self):
        candidates = ["discord"]
        exact = {"initialClass": "discord", "class": "other", "focusHistoryID": 8, "address": "0x2"}
        partial = {"initialClass": "discord-canary", "class": "discord-canary", "focusHistoryID": 0, "address": "0x1"}
        self.assertGreater(ctl.score_window(exact, candidates), ctl.score_window(partial, candidates))

    def test_aliases_include_vesktop_for_discord(self):
        self.assertIn("vesktop", ctl.focus_candidates({"app": "Discord"}))


if __name__ == "__main__":
    unittest.main()
