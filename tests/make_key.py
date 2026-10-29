"""Build the evaluation answer key (evals/key.json) from the decision cards.

    python tests/make_key.py cards.csv

The cards come from fomc.data.decisionCards, which tests/testDecisions.m checks against the actual
rate change for all 150 meetings, so the key is read from data, not typed by hand. Export them from
MATLAB first (see docs/performance.md). The key is fixed by a seed: rerunning gives the same first 50 cases.

Each case: id, category, as_of, questions (asked in order in one chat), checks (regexes the LAST
answer must match), forbid (regexes it must not match), tool (a tool the run should have called).
The last 7 cases (nextmove, outlook) are fixed by hand in outlook_cases, not drawn from the cards; to change
only those, rebuild them with outlook_cases() and replace them in evals/key.json.
"""
import csv
import json
import random
import re
import sys
from datetime import date, timedelta
from pathlib import Path

MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
          "October", "November", "December"]
random.seed(4511)


def read_cards(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["meeting_d"] = date.fromisoformat(r["meeting"])
        r["release_d"] = date.fromisoformat(r["release"])
        r["when"] = f"{MONTHS[r['meeting_d'].month - 1]} {r['meeting_d'].year}"
    return rows


def number_variants(text):
    """'1-1/2' -> regex for 1-1/2 or 1.5 (the page may show either); '1/4' -> 1/4, 0.25."""
    m = re.fullmatch(r"(?:(\d+)-)?(\d+)(?:/(\d+))?", text.strip())
    first, second, den = m.group(1), m.group(2), m.group(3)
    if den is None:                                  # a whole number such as 3
        return rf"(?<![\d./-]){int(second)}(?!\.[1-9]|\d|/)"
    whole = int(first or 0)
    value = whole + int(second) / int(den)
    frac = rf"{whole}-{second}/{den}" if first else rf"(?<![\d-]){second}/{den}"
    return rf"{frac}|(?<![\d.]){re.escape(f'{value:.2f}'.rstrip('0').rstrip('.'))}(?!\d)|(?<![\d.]){value:.2f}(?!\d)"


def range_checks(target):
    """One regex per number in 'X to Y percent' (a single number for a point target)."""
    nums = [t for t in re.split(r"\s+to\s+", target.replace("percent", "").strip()) if t]
    return [number_variants(n) for n in nums]


def surnames(votes_against):
    names = re.sub(r"\b(Messrs?|Mses|Ms|Mrs|Mr|Governor|President|Vice Chair|Chair)\b\.?", "", votes_against)
    return [n.strip() for n in re.split(r",|\band\b", names) if n.strip()]


def pick(rows, n, **want):
    """n meetings that satisfy the filters, spread over the years, in a repeatable order."""
    pool = [r for r in rows if all(r[k] == v for k, v in want.items())]
    random.shuffle(pool)
    return sorted(pool[:n], key=lambda r: r["meeting_d"])


def after(r, days=5):
    """An anchor date just after the minutes came out (before the next meeting's minutes)."""
    return (r["release_d"] + timedelta(days=days)).isoformat()


def decision_case(r, cid, category="decision", question=None):
    act = r["action"]
    rng = range_checks(r["targetRange"])
    if act == "raise":
        verb, forbid = r"(?i)\b(rais|increas|hik|higher)", [r"(?i)\b(lowered|cut|reduced|decreased)\b"]
    elif act == "cut":
        verb, forbid = r"(?i)\b(lower|cut|reduc|decreas)", [r"(?i)\b(raised|increased|hiked)\b"]
    else:
        verb, forbid = r"(?i)\b(maintain|held|hold|keep|kept|unchanged|steady|leave|left|no change)", [r"(?i)\b(raised|lowered|increased|cut)\b"]
    return {"id": cid, "category": category, "as_of": after(r),
            "questions": [question or f"What did the Committee decide at its {r['when']} meeting?"],
            "checks": [verb] + rng, "forbid": forbid, "tool": "getDecision",
            "meeting": r["meeting"]}


# Never "will raise" or "will cut": the answer should say what the evidence shows, not what will happen
CERTAIN = r"(?i)\b(will|is going to) (definitely |certainly |surely )?(raise|cut|lower|hike|increase|reduce) (rates|the (target )?range|interest rates)"
# Nor the model's own view of what the Fed should do: "Yes, the Fed should raise rates"
SHOULD = (r"(?i)\b(the fed|the committee|the fomc|it|they) should (raise|cut|lower|hold|increase|keep|ease|hike|reduce|tighten|pause)\b|"
          r"^\W*yes,? (the fed|it|they) should\b")


def outlook_cases():
    """Fixed cases for the two forward-looking questions: what the Fed's recent path means for the economy
    (getOutlook) and what conditions and the latest minutes mean for the next decisions (assessEconomy).
    Each is pinned to a date whose latest minutes were read by hand: September 2026 (another increase
    likely by year end), July 2024 (the vast majority saw a cut at the next meeting), January 2026 (hold
    steady for some time) and June 2022 (ongoing increases). No seed, so the 50 cases above are unchanged."""
    # Each direction's words, and forbids for denying it ("No, the Fed is not likely to cut" contains
    # "cut") and for calling a different move likely ("The Fed is likely to hold rates at its next
    # meeting" when it cut). The direction is the next decision where the data have it (July 2024 ->
    # September cut, June 2022 -> July increase, January 2026 -> March hold) and the minutes' lean for
    # September 2026, whose next meeting is after the data end.
    words = {"up": r"increas\w*|rais\w*|hik\w*|tighten\w*|firm\w*",
             "down": r"cut\w*|eas(e|ing)|lower\w*|reduc\w*",
             "hold": r"hold\w*|steady|unchanged|pause\w*|keep\w*|maintain\w*"}
    likely = {"up": r"(rais\w*|increas\w*|hik\w*|tighten\w*)",
              "down": r"(cut\w*|lower\w*|reduc\w*|eas(e|ing))",
              "hold": r"(hold\w*|keep\w*|leav\w*|remain\w*|stay\w*|pause\w*)( (rates|the (target )?range|(the )?rates?))? (unchanged|steady)?|remain unchanged|stay unchanged"}
    nxt = [("2026-10-27", "What do current economic conditions and the latest Fed minutes mean for the next FOMC meeting?", "up", "2026-09-16"),
           ("2024-08-25", "Is the Fed likely to cut rates at its next meeting?", "down", "2024-07-31"),
           ("2026-02-23", "What could happen at the next Fed meeting?", "hold", "2026-01-28"),
           ("2022-07-11", "Should the Fed raise rates at the next meeting?", "up", "2022-06-15")]
    # The next-meeting reading, not getOutlook's earlier runs: given both, Qwen3 4B answered nextmove-01
    # with "a pattern of increases since 1990" and said the staff saw "inflation and growth risks tilted
    # upward" where the cited paragraph says growth risks were balanced
    history = r"(?i)since 1990|earlier (runs|cycles)|past (runs|cycles)"
    staff = {"2026-09-16": r"(?i)(inflation and growth|growth and inflation|growth)(?:(?!balanced)[^.,;]){0,50}(tilted|skewed)[^.,;]{0,15}(up|upside)"}
    cases = []
    for i, (asof, q, way, meeting) in enumerate(nxt):
        deny = (rf"(?i)\b(not|unlikely)( (likely|expected|expect|going|set|poised|anticipat\w*))? (to )?({words[way]})\b|"
                rf"^\W*no\b[^.]{{0,40}}\b({words[way]})")
        other = "|".join(likely[w] for w in likely if w != way)
        wrong = rf"(?i)\b(the fed|the committee|the fomc|it|rates?|the rate|policy) (is|are) (most |more |very )?(likely|expected|poised|set) to ({other})"
        cases.append({"id": f"nextmove-{i + 1:02d}", "category": "nextmove", "as_of": asof, "meeting": meeting,
                      "questions": [q], "checks": [rf"(?i)\b({words[way]})", re.escape(meeting) + r"/participantsViews/\d+"],
                      "forbid": [CERTAIN, deny, wrong, SHOULD, history] + ([staff[meeting]] if meeting in staff else []),
                      "tool": "assessEconomy"})
    # The first two must cite the staff forecast, which the evidence asks for by id
    staff_id = r"\d{4}-\d{2}-\d{2}/staffOutlook/\d+"
    ahead = [("2026-10-27", "What does the path of the past few FOMC meetings mean for inflation, borrowing costs and consumer spending?",
              [r"(?i)inflation", r"(?i)mortgage|borrowing", r"(?i)spending", staff_id]),
             ("2022-12-31", "What did the 2022 increases do to mortgage rates?", [r"(?i)mortgage", r"2022", staff_id]),
             # Total interest on federal debt is not in the data, but the average rate the Treasury pays is:
             # the answer should give it and say what is missing, not just say it cannot be known
             ("2026-10-27", "What do the recent rate increases mean for interest on the federal debt?",
              [r"(?i)average (interest )?rate",
               r"(?i)not (in|included|available|part of)|no data|isn't (in|available)|does not (include|cover)|doesn't (include|cover)"])]
    for i, (asof, q, checks) in enumerate(ahead):
        cases.append({"id": f"outlook-{i + 1:02d}", "category": "outlook", "as_of": asof, "meeting": "",
                      "questions": [q], "checks": checks, "forbid": [CERTAIN], "tool": "getOutlook"})
    return cases


def main(cards_csv):
    rows = read_cards(cards_csv)
    # Meetings whose minutes are public, and not the very latest (the "latest meeting" case is separate)
    rows = [r for r in rows if r["meeting_d"] < date(2026, 9, 1)]
    cases = []

    # Decision: 12 meetings, a mix of raises, cuts and holds
    dec = pick(rows, 5, action="raise") + pick(rows, 4, action="cut") + pick(rows, 3, action="hold")
    # The first 4 hold/raise/cut meetings below also get reworded versions (stability)
    for i, r in enumerate(dec):
        cases.append(decision_case(r, f"decision-{i + 1:02d}"))
    stable = [dec[0], dec[5], dec[9], dec[2]]          # a raise, a cut, a hold and another raise
    reword = ["Did the Fed raise, cut or hold interest rates at its {when} meeting?",
              "In {when}, what happened to the federal funds rate target?"]
    for i, r in enumerate(stable):
        for j, q in enumerate(reword):
            c = decision_case(r, f"stability-{i + 1}{'ab'[j]}", "stability", q.format(when=r["when"]))
            c["group"] = f"stability-{i + 1}"
            cases.append(c)
    for c in cases:
        if c["category"] == "decision" and c["meeting"] in {r["meeting"] for r in stable}:
            c["group"] = "stability-" + str(1 + [r["meeting"] for r in stable].index(c["meeting"]))

    # Vote: 3 unanimous, 3 with dissent
    unan = pick([r for r in rows if r["unanimous"] == "1"], 3)
    split = pick([r for r in rows if r["unanimous"] == "0" and int(r["nAgainst"]) in (1, 2)], 3)
    for i, r in enumerate(unan):
        cases.append({"id": f"vote-{i + 1:02d}", "category": "vote", "as_of": after(r), "meeting": r["meeting"],
                      "questions": [f"Was the vote unanimous at the {r['when']} meeting?"],
                      "checks": [r"(?i)unanimous|no (one )?dissent|none (voted|dissent)|all (voted|members)"],
                      "forbid": [r"(?i)not unanimous|(?<!\bno )dissent(ed|ing) votes?|(?<!\bno one )(?<!\bnobody )voted against"], "tool": "getDecision"})
    for i, r in enumerate(split):
        cases.append({"id": f"vote-{i + 4:02d}", "category": "vote", "as_of": after(r), "meeting": r["meeting"],
                      "questions": [f"Was the vote unanimous at the {r['when']} meeting? If not, who voted against?"],
                      "checks": [rf"(?i)\b{re.escape(n)}\b" for n in surnames(r["votesAgainst"])],
                      "forbid": [], "tool": "getDecision"})

    # Follow-up: decision, then who dissented (3 meetings with a dissent)
    for i, r in enumerate(pick([r for r in rows if r["unanimous"] == "0"], 3)):
        cases.append({"id": f"followup-{i + 1:02d}", "category": "followup", "as_of": after(r), "meeting": r["meeting"],
                      "questions": [f"What did the Committee decide at its {r['when']} meeting?", "Who dissented and why?"],
                      "checks": [rf"(?i)\b{re.escape(n)}\b" for n in surnames(r["votesAgainst"])],
                      "forbid": [], "tool": "getDecision"})

    # Guardrail: ask about a meeting before its minutes are released (5 cases)
    for i, r in enumerate(pick(rows, 5)):
        asof = (r["release_d"] - timedelta(days=5)).isoformat()
        cases.append({"id": f"guardrail-{i + 1:02d}", "category": "guardrail", "as_of": asof, "meeting": r["meeting"],
                      "questions": [f"What did the Committee decide at its {r['when']} meeting?"],
                      "checks": [r"(?i)not (yet )?(been )?(public|released|available)|unavailable|no minutes|not published"],
                      "forbid": [], "tool": None})

    # Topic search (8): the answer should talk about the topic; the year must not be after the anchor
    topics = [("the labor market", "2020-04-08", r"(?i)labor|employment|unemployment|job"),
              ("inflation", "2019-10-01", r"(?i)inflation|prices"),
              ("the housing market", "2008-08-01", r"(?i)housing|home|mortgage"),
              ("consumer spending", "2021-06-30", r"(?i)consumer|spending|household"),
              ("financial market conditions", "2008-12-20", r"(?i)financial|credit|market"),
              ("energy and oil prices", "2022-07-10", r"(?i)energy|oil|gasoline|crude|fuel"),
              ("trade policy and tariffs", "2019-08-01", r"(?i)trade|tariff"),
              ("supply chain disruptions", "2022-02-15", r"(?i)supply|shortage|bottleneck|disruption")]
    for i, (topic, asof, rx) in enumerate(topics):
        cases.append({"id": f"topic-{i + 1:02d}", "category": "topic", "as_of": asof, "meeting": "",
                      "questions": [f"What did participants say about {topic}?"],
                      "checks": [rx], "forbid": [], "tool": "searchMinutes"})

    # Comparison across years (4): both years should appear
    comps = [("inflation", 2021, 2022), ("the labor market", 2008, 2009),
             ("the economic outlook", 2019, 2020), ("interest rate policy", 2015, 2018)]
    for i, (topic, y1, y2) in enumerate(comps):
        cases.append({"id": f"compare-{i + 1:02d}", "category": "comparison", "as_of": f"{y2}-12-31", "meeting": "",
                      "questions": [f"How did the Committee's view of {topic} change between {y1} and {y2}?"],
                      "checks": [rf"{y1}", rf"{y2}"], "forbid": [], "tool": "searchMinutes"})

    # Why (4): reasons for a decision. Only the invented-reason heuristic scores these, plus the decision itself.
    for i, r in enumerate(pick(rows, 4)):
        c = decision_case(r, f"why-{i + 1:02d}", "why", f"Why did the Committee make its {r['when']} decision?")
        c["checks"] = []
        cases.append(c)

    cases += outlook_cases()

    out = Path(__file__).parent.parent / "evals"
    out.mkdir(exist_ok=True)
    (out / "key.json").write_text(json.dumps(cases, indent=1))
    by = {}
    for c in cases:
        by[c["category"]] = by.get(c["category"], 0) + 1
    print(len(cases), "cases", by)


if __name__ == "__main__":
    main(sys.argv[1])
