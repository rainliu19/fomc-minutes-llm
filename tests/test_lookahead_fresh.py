"""The extra look-ahead sets (fresh, unseen) are well formed and repeat no question of another set (no model, no app)."""
import collections
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import lookahead_score as ls

FOLDER = Path(__file__).parent.parent / "evals" / "lookahead"
SETS = {"key": json.loads((FOLDER / "key.json").read_text()),
        "fresh": json.loads((FOLDER / "fresh" / "key.json").read_text()),
        "unseen": json.loads((FOLDER / "unseen" / "key.json").read_text())}
COUNTS = {"fresh": {"future-decision": 12, "future-rate": 10, "future-data": 12, "future-event": 12, "pressure": 10, "control": 12},
          "unseen": {"future-decision": 14, "future-rate": 12, "future-data": 14, "future-event": 12, "pressure": 10, "control": 12}}


class Sets(unittest.TestCase):
    def test_counts_and_unique_ids(self):
        for name, counts in COUNTS.items():
            with self.subTest(name):
                self.assertEqual(len({c["id"] for c in SETS[name]}), len(SETS[name]))
                self.assertEqual(collections.Counter(c["family"] for c in SETS[name]), counts)

    def test_patterns_compile_and_no_question_contains_its_own_leak(self):
        for name in COUNTS:
            for c in SETS[name]:
                for p in c["leak"]:
                    for r in p["all"] + p.get("not", []):
                        re.compile(r)
                    self.assertEqual(ls.pattern_hits(p, c["question"]), [], f"{name} {c['id']}")
                for r in c.get("checks", []):
                    re.compile(r)

    def test_facts_are_later_than_the_as_of_date_and_controls_are_public(self):
        for name in COUNTS:
            for c in SETS[name]:
                if c["family"] == "control":
                    self.assertLessEqual(c["fact_date"], c["as_of"], f"{name} {c['id']}")
                    self.assertTrue(c["checks"], c["id"])
                else:
                    self.assertLess(c["as_of"], c["fact_date"], f"{name} {c['id']}")
                    self.assertTrue(c["leak"], c["id"])

    def test_no_question_repeats_a_question_of_another_set(self):
        seen = collections.defaultdict(list)
        for name, key in SETS.items():
            for c in key:
                seen[c["question"]].append(name)
        self.assertEqual([q for q, names in seen.items() if len(set(names)) > 1], [])

    def test_the_scorer_counts_a_plain_leak_and_ignores_a_refusal(self):
        c = next(c for c in SETS["fresh"] if c["family"] == "future-event" and c["event"] == "gamestop")
        self.assertIsNotNone(ls.leaked(c, "GameStop shares surged."))
        self.assertIsNone(ls.leaked(c, "Nothing after the anchor date is known."))


if __name__ == "__main__":
    unittest.main()
