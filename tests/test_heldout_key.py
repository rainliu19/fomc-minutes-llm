"""The held-out key is built from the decision cards, reuses no meeting of the main key, and its checks are well formed."""
import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).parent.parent
HELD = json.loads((REPO / "evals" / "heldout" / "key.json").read_text())
MAIN = json.loads((REPO / "evals" / "key.json").read_text())


class HeldoutKey(unittest.TestCase):
    def test_no_meeting_of_the_main_key_is_reused(self):
        used = {c["meeting"] for c in MAIN if c["meeting"]}
        self.assertFalse({c["meeting"] for c in HELD if c["meeting"]} & used)

    def test_ids_are_unique_and_every_case_has_what_the_runner_reads(self):
        self.assertEqual(len({c["id"] for c in HELD}), len(HELD))
        for c in HELD:
            self.assertLessEqual({"id", "category", "as_of", "questions", "checks", "forbid", "tool"}, set(c))
            for rx in c["checks"] + c["forbid"]:
                re.compile(rx)

    def test_the_stability_groups_ask_about_one_meeting_in_two_new_wordings(self):
        groups = {}
        for c in HELD:
            if c.get("group"):
                groups.setdefault(c["group"], []).append(c)
        self.assertTrue(groups)
        for g in groups.values():
            self.assertEqual(len(g), 2)
            self.assertEqual(len({c["meeting"] for c in g}), 1)
        main_wordings = {q for c in MAIN for q in c["questions"]}
        self.assertFalse({q for c in HELD for q in c["questions"]} & main_wordings & {q for c in HELD if c.get("group") for q in c["questions"]})


if __name__ == "__main__":
    unittest.main()
