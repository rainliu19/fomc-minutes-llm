"""The fresh look-ahead set is well formed and its questions differ from the main key's (no model, no app)."""
import collections
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import lookahead_score as ls  # noqa: E402

FOLDER = Path(__file__).parent.parent / "evals" / "lookahead"
FRESH = json.loads((FOLDER / "fresh" / "key.json").read_text())
MAIN = json.loads((FOLDER / "key.json").read_text())


class Fresh(unittest.TestCase):
    def test_counts_and_unique_ids(self):
        self.assertEqual(len({c["id"] for c in FRESH}), len(FRESH))
        self.assertEqual(collections.Counter(c["family"] for c in FRESH),
                         {"future-decision": 12, "future-rate": 10, "future-data": 12, "future-event": 12, "pressure": 10, "control": 12})

    def test_patterns_compile_and_no_question_contains_its_own_leak(self):
        for c in FRESH:
            for p in c["leak"]:
                for r in p["all"] + p.get("not", []):
                    re.compile(r)
                self.assertEqual(ls.pattern_hits(p, c["question"]), [], c["id"])
            for r in c.get("checks", []):
                re.compile(r)

    def test_facts_are_later_than_the_as_of_date_and_controls_are_public(self):
        for c in FRESH:
            if c["family"] == "control":
                self.assertLessEqual(c["fact_date"], c["as_of"], c["id"])
                self.assertTrue(c["checks"], c["id"])
            else:
                self.assertLess(c["as_of"], c["fact_date"], c["id"])
                self.assertTrue(c["leak"], c["id"])

    def test_no_question_repeats_a_main_key_question(self):
        main = {c["question"] for c in MAIN}
        self.assertEqual([c["id"] for c in FRESH if c["question"] in main], [])

    def test_the_scorer_counts_a_plain_leak_and_ignores_a_refusal(self):
        c = next(c for c in FRESH if c["family"] == "future-event" and c["event"] == "gamestop")
        self.assertIsNotNone(ls.leaked(c, "GameStop shares surged."))
        self.assertIsNone(ls.leaked(c, "Nothing after the anchor date is known."))


if __name__ == "__main__":
    unittest.main()
