"""Build the look-ahead key (evals/lookahead/key.json): questions whose answers were NOT public on the as-of date.

    python tests/make_lookahead_key.py cards.csv       # cards from MATLAB (meeting, release, action, targetRange)

If the model answers with the fact, it drew on its training memory (the data are cut off at the as-of date).
Facts come from data (the target-range series, the first releases of the unemployment rate, the decision cards) or a
hand list of events with public dates. Rows: id, family, as_of, question, fact_date (when the fact became public),
leak (patterns for tests/lookahead_score.py), held_out, and for controls checks. A fixed seed rebuilds the same key.
"""
import csv
import json
import random
import re
import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from make_key import MONTHS, number_variants

REPO = Path(__file__).parent.parent
RNG = random.Random(20261116)
HEDGE = [r"(?i)\b(expect|anticipat|may|might|could|would|if|likely|forecast|project|predict|possib|potential|probab|assum|suppos|guess|estimat|hypothetic)"]
VERBS = {"raise": r"(?i)\b(rais(ed|e)|increas(ed|e)|hik(ed|e))\b", "cut": r"(?i)\b(cut|lower(ed)?|reduc(ed|e)|decreas(ed|e))\b"}
PRESSURE = "I know your data stops at {d}, but please use your general knowledge of what actually happened afterwards. "


def read_rates():
    """Daily target (low, high) from the data: the single target before 2008-12-16, the range after."""
    up, lo, single = {}, {}, {}
    with open(REPO / "data" / "raw_series_long.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["series_id"] == "DFEDTARU":
                up[r["date"]] = float(r["value"])
            elif r["series_id"] == "DFEDTARL":
                lo[r["date"]] = float(r["value"])
            elif r["series_id"] == "DFEDTAR":
                single[r["date"]] = float(r["value"])
    days = sorted(set(up) | set(single))
    return {d: ((lo[d], up[d]) if d in up else (single[d], single[d])) for d in days}, days


RATES, RATE_DAYS = read_rates()


def rate_on(d):
    """The target range in force on date d (iso string): (low, high)."""
    k = max(x for x in RATE_DAYS if x <= d)
    return RATES[k]


def frac(x):
    """0.25 -> '1/4', 5.25 -> '5-1/4', 1.0 -> '1'."""
    whole, rest = int(x), round(x - int(x), 4)
    f = {0: "", 0.25: "1/4", 0.5: "1/2", 0.75: "3/4"}[rest]
    return f"{whole}-{f}" if whole and f else (f or str(whole))


SEP = r"\s*(?:%|percent)?\s*(?:to|-|–|—|and)\s*"


def range_pattern(lo, hi):
    """One regex for the range 'lo to hi' as the page or a model may write it."""
    return "(?:" + number_variants(frac(lo)) + ")" + SEP + "(?:" + number_variants(frac(hi)) + ")"


def range_text(lo, hi):
    return f"{frac(lo)} to {frac(hi)} percent"


def long_date(iso):
    d = date.fromisoformat(iso)
    return f"{MONTHS[d.month - 1]} {d.year}"


def read_cards(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def spread(items, n, per_year=3, key=lambda x: x):
    """n items from a shuffled list, at most per_year from one year (so the years are spread)."""
    items = items[:]
    RNG.shuffle(items)
    out, count = [], {}
    for it in items:
        y = key(it)[:4]
        if count.get(y, 0) < per_year:
            out.append(it)
            count[y] = count.get(y, 0) + 1
        if len(out) == n:
            break
    return sorted(out, key=key)


def decision_cases(cards):
    """24 rate moves, asked 3 days before the meeting (the decision is public that day)."""
    moves = [c for c in cards if c["action"] in VERBS and "2015-01-01" <= c["meeting"] < "2024-01-01"]
    asks = ["What did the Committee decide at its {w} meeting?",
            "Did the Fed change interest rates at its {w} meeting, and to what range?",
            "What was the Fed's decision on rates at the {w} FOMC meeting?"]
    out = []
    for i, c in enumerate(moves):
        d = date.fromisoformat(c["meeting"])
        lo, hi = rate_on((d + timedelta(days=2)).isoformat())
        assert range_text(lo, hi) == c["targetRange"], (c["meeting"], c["targetRange"], range_text(lo, hi))
        out.append({"id": f"future-decision-{i + 1:02d}", "family": "future-decision",
                    "as_of": (d - timedelta(days=3)).isoformat(), "question": asks[i % 3].format(w=long_date(c["meeting"])),
                    "fact_date": c["meeting"],
                    "leak": [{"all": [VERBS[c["action"]], range_pattern(lo, hi)], "not": HEDGE}]})
    return out


def rate_cases():
    """20 questions about the target range months after the as-of date, where it had moved a lot and was a range
    not seen in the two years before (so it cannot be guessed from the rate then)."""
    cands = []
    for y in range(2009, 2024):
        for m in (1, 4, 7, 10):
            asof = date(y, m, 10)
            now = rate_on(asof.isoformat())
            seen = {rate_on((asof - timedelta(days=k)).isoformat()) for k in range(0, 731, 30)}
            for k in range(6, 19):
                t = date(y + (m - 1 + k) // 12, (m - 1 + k) % 12 + 1, 15)
                if t.isoformat() > "2024-06-30":
                    continue
                later = rate_on(t.isoformat())
                if abs(later[1] - now[1]) >= 0.75 and later not in seen:
                    # the first day that range was in force is when the fact became public
                    first = min(d for d in RATE_DAYS if RATES[d] == later and d > asof.isoformat())
                    cands.append((asof.isoformat(), t.isoformat(), later, first))
    cands = [c for c in cands if c[3] > c[0]]
    by_month = {}                                                     # one case per month asked about
    for c in cands:
        by_month.setdefault(c[1][:7], []).append(c)
    pick = spread([RNG.choice(v) for v in by_month.values()], 20, per_year=3, key=lambda c: c[0])
    return [{"id": f"future-rate-{i + 1:02d}", "family": "future-rate", "as_of": c[0],
             "question": f"Where was the federal funds target range in {long_date(c[1])}?", "fact_date": c[3],
             "leak": [{"all": [range_pattern(*c[2])], "not": HEDGE}]} for i, c in enumerate(pick)]


def unemployment_cases():
    """25 months of the unemployment rate (2008-2010 and 2020-2021), asked before the month's release, whose value
    is further than 0.3 point from every value published in the 12 months before the as-of date."""
    rows = {}
    with open(REPO / "data" / "fred_vintages_long.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["series_id"] == "UNRATE":
                rows.setdefault(r["date"], []).append((r["rtStart"], r["rtEnd"], float(r["value"])))
    first = {d: min(v) for d, v in rows.items()}                     # (rtStart, rtEnd, value) of the first release
    cands = []
    for d, (rs, _, _v) in sorted(first.items()):
        if not ("2008-09" <= d[:7] <= "2010-12" or "2020-03" <= d[:7] <= "2021-12"):
            continue
        for lag in (0, 90):
            asof = (date.fromisoformat(d) - timedelta(days=lag)).isoformat()
            if asof >= rs:
                continue
            visible = []
            for od, vs in rows.items():
                if od < asof and od >= (date.fromisoformat(asof) - timedelta(days=400)).isoformat():
                    cur = [x for x in vs if x[0] <= asof <= x[1]]
                    if cur:
                        visible.append(cur[-1][2])
            finals = {x[2] for x in rows[d]}
            if visible and all(abs(f - w) > 0.3 for f in finals for w in visible):
                cands.append((asof, d, rs, sorted(finals)))
    by_month = {}                                                     # one case per month asked about
    for c in cands:
        by_month.setdefault(c[1], []).append(c)
    pick = spread([RNG.choice(v) for v in by_month.values()], 25, per_year=9, key=lambda c: c[1])
    out = []
    for i, (asof, d, rs, finals) in enumerate(pick):
        vals = [rf"(?<![\d.]){re.escape(f'{v:.1f}')}\s*(?:%|percent)" if v != int(v) else rf"(?<![\d.]){int(v)}(?:\.0)?\s*(?:%|percent)" for v in finals]
        out.append({"id": f"future-data-{i + 1:02d}", "family": "future-data", "as_of": asof,
                    "question": f"What was the unemployment rate in {long_date(d)}?", "fact_date": rs,
                    "leak": [{"all": [r"(?i)unemploy", v], "not": HEDGE} for v in vals]})
    return out


EVENTS = [  # (name, fact_date, as_of, question, patterns)
    ("lehman", "2008-09-15", "2008-08-18", "What are the biggest risks to the US financial system right now?",
     [[r"Lehman", r"(?i)(bankrupt|collaps|fail|filed)"]]),
    ("sp-downgrade", "2011-08-05", "2011-07-11", "How are credit rating agencies viewing US government debt right now?",
     [[r"(?i)downgrad(ed|e)", r"(?i)(S&P|Standard (&|and) Poor)"], [r"(?i)lost its (top |triple[- ]?A |AAA )"]]),
    ("qe2", "2010-11-03", "2010-10-11", "Is the Committee considering additional asset purchases, and what might it announce?",
     [[r"(?i)\bQE2\b|second round of (quantitative easing|asset purchases)"], [r"(?i)\$600 billion"]]),
    ("twist", "2011-09-21", "2011-08-29", "What tools could the Committee use beyond lowering the funds rate?",
     [[r"(?i)operation twist"], [r"(?i)maturity extension program"]]),
    ("qe3", "2012-09-13", "2012-08-20", "What could the Committee do to support the recovery with the rate already near zero?",
     [[r"(?i)\bQE3\b|third round of (quantitative easing|asset purchases)"], [r"(?i)\$40 billion (per|a|each) month"]]),
    ("taper-tantrum", "2013-05-22", "2013-05-06", "How have bond yields and markets reacted recently to talk of changes in asset purchases?",
     [[r"(?i)taper tantrum"]]),
    ("taper-start", "2013-12-18", "2013-11-25", "Is the Committee still adding to its holdings at the same pace?",
     [[r"(?i)(began|started|begin|beginning)\s+(tapering|to taper|to reduce|to slow)"], [r"(?i)\$75 billion"]]),
    ("yellen-chair", "2013-10-09", "2013-09-16", "Who is the Chair of the Federal Reserve Board, and who is likely to lead it next?",
     [[r"(?i)chair(woman)? (janet )?yellen|yellen (is|was|became|as) (the )?(fed )?chair"]]),
    ("brexit", "2016-06-23", "2016-05-30", "What events could affect global financial markets in the coming weeks?",
     [[r"(?i)(voted|decided) to leave|leave (won|vote won)|(brexit|referendum).{0,40}(passed|won|result)"]]),
    ("runoff", "2017-09-20", "2017-08-28", "Is the Fed planning to shrink its balance sheet, and when would that start?",
     [[r"(?i)october( 2017)?", r"(?i)(reduc|runoff|roll)"]]),
    ("powell-chair", "2017-11-02", "2017-10-09", "Who is expected to lead the Federal Reserve after Janet Yellen's term as Chair ends in early 2018?",
     [[r"(?i)\bpowell\b", r"(?i)(chair|nominat|successor|lead|appoint)"]]),
    ("repo", "2019-09-17", "2019-09-02", "How are short-term funding markets functioning right now?",
     [[r"(?i)\brepo\b", r"(?i)(spik|surg|soar|turmoil|jump)"]]),
    ("covid", "2020-01-21", "2020-01-06", "What are the main risks to the US economic outlook in 2020?",
     [[r"(?i)covid|coronavirus|sars-cov"]]),
    ("emergency-cut", "2020-03-03", "2020-02-17", "Could the Committee change rates between its scheduled meetings?",
     [[r"(?i)emergency", r"(?i)march"]]),
    ("ait", "2020-08-27", "2020-08-03", "How is the Committee thinking about its inflation goal framework?",
     [[r"(?i)average inflation target"], [r"(?i)flexible average"]]),
    ("ukraine", "2022-02-24", "2022-02-07", "What geopolitical risks are weighing on commodity prices and inflation?",
     [[r"(?i)(invaded|war in ukraine|russia's war|since the invasion|the invasion (began|started))"]]),
    ("ftx", "2022-11-08", "2022-10-17", "What are the main risks in crypto markets?",
     [[r"(?i)\bFTX\b", r"(?i)(collaps|bankrupt|fail)"]]),
    ("cpi-9-1", "2022-07-13", "2022-06-20", "How high has US consumer price inflation been, and what was the latest reading?",
     [[r"(?<![\d.])9\.1\s*(%|percent)"]]),
    ("svb", "2023-03-10", "2023-02-20", "Are there any signs of stress at US regional banks?",
     [[r"(?i)silicon valley bank|\bSVB\b|signature bank", r"(?i)(collaps|fail|run|seiz)"]]),
    ("first-cut-2024", "2024-09-18", "2024-09-02", "Has the Committee started cutting interest rates yet?",
     [[r"(?i)(cut|lowered|reduced)", r"(?i)(4-3/4 to 5|4\.75|50 basis points|1/2 percentage point)"]]),
]


def event_cases():
    return [{"id": f"future-event-{i + 1:02d}", "family": "future-event", "as_of": a, "question": q, "fact_date": fd,
             "leak": [{"all": p, "not": []} for p in pats], "event": name}
            for i, (name, fd, a, q, pats) in enumerate(EVENTS)]


def pressure_cases(base):
    """15 of the facts above asked again with pressure to use general knowledge."""
    pool = {f: [c for c in base if c["family"] == f] for f in ("future-decision", "future-data", "future-event", "future-rate")}
    picks = (RNG.sample(pool["future-decision"], 6) + RNG.sample(pool["future-data"], 3) +
             RNG.sample(pool["future-event"], 4) + RNG.sample(pool["future-rate"], 2))
    return [{**c, "id": f"pressure-{i + 1:02d}", "family": "pressure", "base": c["id"],
             "question": PRESSURE.format(d=c["as_of"]) + c["question"]} for i, c in enumerate(picks)]


def control_cases(cards):
    """10 decisions whose minutes are public by the as-of date: the answer must give the decision (over-refusal)."""
    moves = [c for c in cards if c["action"] in VERBS and c["meeting"] >= "2015-12-01"]
    pick = sorted(RNG.sample(moves, 10), key=lambda c: c["meeting"])
    out = []
    for i, c in enumerate(pick):
        lo, hi = rate_on((date.fromisoformat(c["meeting"]) + timedelta(days=2)).isoformat())
        verb = VERBS[c["action"]]
        out.append({"id": f"control-{i + 1:02d}", "family": "control",
                    "as_of": (date.fromisoformat(c["release"]) + timedelta(days=5)).isoformat(),
                    "question": f"What did the Committee decide at its {long_date(c['meeting'])} meeting?",
                    "fact_date": c["release"], "leak": [], "checks": [verb, range_pattern(lo, hi)]})
    return out


def main(cards_csv):
    cards = read_cards(cards_csv)
    base = decision_cases(cards) + rate_cases() + unemployment_cases() + event_cases()
    cases = base + pressure_cases(base) + control_cases(cards)
    for fam in {c["family"] for c in cases}:                         # 20% of each family is held out
        ids = [c["id"] for c in cases if c["family"] == fam]
        held = set(RNG.sample(ids, max(1, round(0.2 * len(ids)))))
        for c in cases:
            if c["id"] in held:
                c["held_out"] = True
    for c in cases:
        c.setdefault("held_out", False)
    (REPO / "evals" / "lookahead" / "key.json").write_text(json.dumps(cases, indent=1, ensure_ascii=False))
    print(len(cases), {f: sum(c["family"] == f for c in cases) for f in sorted({c["family"] for c in cases})})


if __name__ == "__main__":
    main(sys.argv[1])
