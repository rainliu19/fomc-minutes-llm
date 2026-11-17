"""Build the held-out key (evals/heldout/key.json): the same kinds of questions as the main key, on other meetings.

    python tests/make_heldout_key.py logs/cards_heldout.csv

The main key (evals/key.json) is what the multi-agent checks were developed against. This one reuses none of its
meetings, topics or wordings of the stability cases, and was written after the checks were fixed, so its accuracy is
the fair one. Facts come from the decision cards, as in make_key.py (columns: meeting, release, action, targetRange,
change, unanimous, nAgainst, votesAgainst). It has no hand-read forecast questions (nextmove, outlook).
"""
import json
import sys
from datetime import timedelta
from pathlib import Path

import make_key as K

K.random.seed(90210)
REPO = Path(__file__).parent.parent
REWORD = ["What did the FOMC do with the federal funds rate in {when}?", "{when} meeting: did the Fed raise, cut or hold rates?"]
TOPICS = [("wages and compensation", "2019-05-01", r"(?i)wage|compensation|pay"),
          ("the dollar and foreign exchange", "2015-06-01", r"(?i)dollar|exchange|foreign"),
          ("banking and credit conditions", "2023-09-01", r"(?i)bank|credit|lending|loan"),
          ("the pandemic", "2020-09-01", r"(?i)pandemic|covid|virus|public health")]
COMPARE = [("the housing market", 2010, 2012), ("the labor market", 2017, 2019)]


def main(cards_csv):
    used = {c["meeting"] for c in json.loads((REPO / "evals" / "key.json").read_text()) if c["meeting"]}
    rows = [r for r in K.read_cards(cards_csv) if r["meeting"] not in used and r["meeting_d"] < K.date(2026, 9, 1)]
    cases = []
    dec = K.pick(rows, 5, action="raise") + K.pick(rows, 4, action="cut") + K.pick(rows, 3, action="hold")
    for i, r in enumerate(dec):
        cases.append(K.decision_case(r, f"decision-{i + 1:02d}"))
    for i, r in enumerate([dec[0], dec[5], dec[9]]):
        for j, q in enumerate(REWORD):
            c = K.decision_case(r, f"stability-{i + 1}{'ab'[j]}", "stability", q.format(when=r["when"]))
            c["group"] = f"stability-{i + 1}"
            cases.append(c)
    unan = K.pick([r for r in rows if r["unanimous"] == "1"], 3)
    split = K.pick([r for r in rows if r["unanimous"] == "0" and int(r["nAgainst"]) in (1, 2)], 6)
    for i, r in enumerate(unan):
        cases.append({"id": f"vote-{i + 1:02d}", "category": "vote", "as_of": K.after(r), "meeting": r["meeting"],
                      "questions": [f"Was the vote unanimous at the {r['when']} meeting?"],
                      "checks": [r"(?i)unanimous|no (one )?dissent|none (voted|dissent)|all (voted|members)"],
                      "forbid": [r"(?i)not unanimous|(?<!\bno )dissent(ed|ing) votes?|(?<!\bno one )(?<!\bnobody )voted against"], "tool": "getDecision"})
    for i, r in enumerate(split[:3]):
        cases.append({"id": f"vote-{i + 4:02d}", "category": "vote", "as_of": K.after(r), "meeting": r["meeting"],
                      "questions": [f"Was the vote unanimous at the {r['when']} meeting? If not, who voted against?"],
                      "checks": [rf"(?i)\b{K.re.escape(n)}\b" for n in K.surnames(r["votesAgainst"])], "forbid": [], "tool": "getDecision"})
    for i, r in enumerate(split[3:]):
        cases.append({"id": f"followup-{i + 1:02d}", "category": "followup", "as_of": K.after(r), "meeting": r["meeting"],
                      "questions": [f"What did the Committee decide at its {r['when']} meeting?", "Who dissented and why?"],
                      "checks": [rf"(?i)\b{K.re.escape(n)}\b" for n in K.surnames(r["votesAgainst"])], "forbid": [], "tool": "getDecision"})
    for i, r in enumerate(K.pick(rows, 3)):
        cases.append({"id": f"guardrail-{i + 1:02d}", "category": "guardrail", "as_of": (r["release_d"] - timedelta(days=5)).isoformat(),
                      "meeting": r["meeting"], "questions": [f"What did the Committee decide at its {r['when']} meeting?"],
                      "checks": [r"(?i)not (yet )?(been )?(public|released|available)|unavailable|no minutes|not published"], "forbid": [], "tool": None})
    for i, (topic, asof, rx) in enumerate(TOPICS):
        cases.append({"id": f"topic-{i + 1:02d}", "category": "topic", "as_of": asof, "meeting": "",
                      "questions": [f"What did participants say about {topic}?"], "checks": [rx], "forbid": [], "tool": "searchMinutes"})
    for i, (topic, y1, y2) in enumerate(COMPARE):
        cases.append({"id": f"compare-{i + 1:02d}", "category": "comparison", "as_of": f"{y2}-12-31", "meeting": "",
                      "questions": [f"How did the Committee's view of {topic} change between {y1} and {y2}?"],
                      "checks": [str(y1), str(y2)], "forbid": [], "tool": "searchMinutes"})
    out = REPO / "evals" / "heldout"
    out.mkdir(exist_ok=True)
    (out / "key.json").write_text(json.dumps(cases, indent=1))
    by = {}
    for c in cases:
        by[c["category"]] = by.get(c["category"], 0) + 1
    print(len(cases), "cases", by)
    assert not ({c["meeting"] for c in cases if c["meeting"]} & used), "a meeting of the main key was reused"


if __name__ == "__main__":
    main(sys.argv[1])
