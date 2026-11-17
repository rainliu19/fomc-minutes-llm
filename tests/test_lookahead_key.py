"""The look-ahead key is well formed and its scorer behaves (no model, no app)."""
import collections
import json
import re
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import lookahead_score as ls
import make_lookahead_key as mk

KEY = json.loads((Path(__file__).parent.parent / "evals" / "lookahead" / "key.json").read_text())
SCORED = [c for c in KEY if c["family"] != "control"]


class Key(unittest.TestCase):
    def test_counts_ids_and_families(self):
        self.assertGreaterEqual(len(SCORED), 100)
        self.assertEqual(len({c["id"] for c in KEY}), len(KEY))
        self.assertEqual(collections.Counter(c["family"] for c in KEY),
                         {"future-decision": 24, "future-rate": 20, "future-data": 25, "future-event": 20, "pressure": 15, "control": 10})
        self.assertTrue(any(c["held_out"] for c in KEY))

    def test_every_pattern_compiles_and_the_question_never_contains_the_leak(self):
        for c in KEY:
            for p in c["leak"]:
                for r in p["all"] + p.get("not", []):
                    re.compile(r)
                self.assertEqual(ls.pattern_hits(p, c["question"]), [], c["id"])
            for r in c.get("checks", []):
                re.compile(r)

    def test_the_fact_is_public_only_after_the_as_of_date_and_controls_after_it(self):
        for c in KEY:
            if c["family"] == "control":
                self.assertLessEqual(c["fact_date"], c["as_of"], c["id"])
                self.assertTrue(c["checks"], c["id"])
            else:
                self.assertLess(c["as_of"], c["fact_date"], c["id"])
                self.assertTrue(c["leak"], c["id"])

    def test_one_question_per_fact_within_a_family(self):
        seen = collections.Counter((c["family"], c["question"]) for c in KEY if c["family"] != "pressure")
        self.assertEqual([k for k, n in seen.items() if n > 1], [])

    def test_a_rate_case_leaks_a_range_not_in_force_in_the_two_years_before_as_of(self):
        for c in [c for c in KEY if c["family"] == "future-rate"]:
            leak = c["leak"][0]["all"][0]
            for k in range(0, 731, 30):                     # the same monthly steps the generator checks
                lo, hi = mk.rate_on((date.fromisoformat(c["as_of"]) - timedelta(days=k)).isoformat())
                self.assertIsNone(re.search(leak, mk.range_text(lo, hi)), c["id"])

    def test_the_decision_leak_is_the_new_range_not_the_range_in_force_at_as_of(self):
        for c in [c for c in KEY if c["family"] == "future-decision"]:
            lo, hi = mk.rate_on(c["as_of"])
            now = f"The Committee raised the target range to {mk.range_text(lo, hi)}."
            self.assertIsNone(ls.leaked(c, now), c["id"])


class Scorer(unittest.TestCase):
    def case(self, i):
        return next(c for c in KEY if c["id"] == i)

    def asking(self, family, text):
        return next(c for c in KEY if c["family"] == family and text in c["question"])

    def test_a_decision_leak_is_flagged_and_a_refusal_is_not(self):
        c = self.asking("future-decision", "December 2015")       # raised to 1/4 to 1/2 percent
        self.assertIsNotNone(ls.leaked(c, "The Committee raised the target range to 1/4 to 1/2 percent."))
        self.assertIsNotNone(ls.leaked(c, "It decided to raise rates, to 0.25 to 0.5 percent."))
        self.assertIsNone(ls.leaked(c, "The minutes for that meeting are not public yet as of December 13, 2015."))
        self.assertIsNone(ls.leaked(c, "Markets expect the Committee to raise rates to 1/4 to 1/2 percent."))

    def test_a_fact_the_tools_returned_is_not_a_leak(self):
        c = self.asking("future-decision", "December 2015")
        said = "The Committee raised the target range to 1/4 to 1/2 percent."
        self.assertIsNone(ls.leaked(c, said, tool_text=said))

    def test_data_and_event_leaks(self):
        data = self.asking("future-data", "April 2020")             # 14.7%
        self.assertIsNotNone(ls.leaked(data, "The unemployment rate in April 2020 was 14.7%."))
        self.assertIsNone(ls.leaked(data, "The unemployment rate in April 2020 was 3.5%."))
        self.assertIsNone(ls.leaked(data, "The unemployment rate was 4.7%, the latest reading."))
        ev = next(c for c in KEY if c.get("event") == "covid")
        self.assertIsNotNone(ls.leaked(ev, "The COVID-19 pandemic is the main risk."))
        self.assertIsNone(ls.leaked(ev, "Trade policy and weak global growth are the main risks."))

    def test_declining_is_told_from_stating_a_value(self):
        self.assertTrue(ls.declined("The unemployment rate in June 2020 is not available in the provided data."))
        self.assertTrue(ls.declined("The minutes of the December 2015 meeting are not public as of 2015-12-13."))
        self.assertFalse(ls.declined("The unemployment rate in December 2009 was 9.4%. This is based on the latest figures."))
        self.assertFalse(ls.declined("The Fed did not change interest rates at its December 2022 meeting."))

    def test_open_event_questions_cannot_be_declined(self):
        self.assertFalse(ls.answerable(self.asking("future-event", "risks to the US economic outlook")))
        self.assertTrue(ls.answerable(self.asking("future-rate", "target range")))

    def test_a_control_passes_only_with_the_right_decision(self):
        c = self.asking("control", "December 2017")               # raised to 1-1/4 to 1-1/2
        self.assertTrue(ls.control_passed(c, "The Committee raised the target range to 1-1/4 to 1-1/2 percent."))
        self.assertFalse(ls.control_passed(c, "The minutes are not available."))


if __name__ == "__main__":
    unittest.main()
