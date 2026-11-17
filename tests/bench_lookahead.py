"""Look-ahead bias: how often does a model answer with what happened AFTER the as-of date?

    uv run app.py
    python tests/bench_lookahead.py fast --team --tag v0 # a model id from models/models.json
    python tests/bench_lookahead.py fast --open --tag baseline # the baseline: the app with the data cutoff off (the tools see everything)
    python tests/bench_lookahead.py fast --team --tag v0 --limit 6    # a dry run on 6 cases spread over the key

Asks every question of evals/lookahead/key.json (tests/make_lookahead_key.py) and scores the answer with
tests/lookahead_score.py: an error when the answer presents something after the as-of date as known. Writes evals/lookahead/<model>-<mode>-<tag>.json (rows are saved as they finish; run again to
continue after a memory stop). The Evaluation page shows it. The regexes catch only the facts the key lists, so the
rate is a lower bound.
"""
import json
import sys
import time
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bench_live as B                         # the app call, memory guard, Wilson interval
import lookahead_score as ls

TAG = sys.argv[sys.argv.index("--tag") + 1] if "--tag" in sys.argv else "v0"
MODE = "open" if "--open" in sys.argv else "one" if "--one" in sys.argv else "team"
OUT = B.REPO / "evals" / "lookahead"
if "--key" in sys.argv:                                  # another key (for example "fresh"): its own folder of runs
    OUT = OUT / sys.argv[sys.argv.index("--key") + 1]


def tool_text(session_id):
    """What the model was shown by code: tool results and the messages that carry lookups and reports."""
    out = []
    for line in (B.REPO / "logs" / f"web-{session_id}.jsonl").read_text().splitlines():
        e = json.loads(line)
        if e["type"] == "tool_call":
            out.append(str(e.get("result", "")))
        elif e["type"] == "message" and e.get("role") in ("user", "tool"):
            out.append(str(e.get("text", "")))
    return "\n".join(out)


def ask(case, entry):
    """The answer, the text the tools returned, the app's reply stats and seconds."""
    sid = B.uuid.uuid4().hex
    t0 = time.time()
    open_ = MODE == "open"                               # no cutoff: anchored today, the as-of date only said in the question
    message = f"Assume today is {case['as_of']}. {case['question']}" if open_ else case["question"]
    r = B.post("/chat", {"message": message, "session_id": sid, "as_of": date.today().isoformat() if open_ else case["as_of"], "effort": "low",
                         "model": B.MODEL, "agents": "one" if MODE == "one" else "team"})
    seconds = time.time() - t0
    stats, _ = B.read_trace(sid)
    return r["answer"], tool_text(sid), stats, seconds, [c["name"] for c in r["tool_calls"]], r.get("warning", "")


def run_case(case, entry):
    answer, tools, stats, seconds, names, warning = ask(case, entry)
    row = {"id": case["id"], "family": case["family"], "held_out": case["held_out"], "as_of": case["as_of"],
           "question": case["question"], "seconds": round(seconds, 1), "model_called": stats.get("model_calls", 0) > 0,
           "tools": names, "warning": warning, "answer": answer[:1200]}
    if case["family"] == "control":
        row["passed"] = ls.control_passed(case, answer)
    else:
        row["leak"] = ls.leaked(case, answer, "" if MODE == "open" else tools)   # open: a fact the tools gave counts too
        row["leaked"] = row["leak"] is not None
        row["answerable"] = ls.answerable(case)
    return row


def summarize(rows, key, meta):
    """The numbers the Evaluation page shows: the lookahead error rate with its interval, per family, held out, controls."""
    for r in rows:
        if r["family"] != "control":
            r["error"] = ls.is_error(r)
    scored = [r for r in rows if r["family"] != "control"]

    def part(rs):
        n, k = len(rs), sum(ls.is_error(r) for r in rs)
        return {"n": n, "errors": k, "rate": round(k / n, 3) if n else None, "ci95": B.wilson(k, n)}

    controls = [r for r in rows if r["family"] == "control"]
    return {**meta, "n_key": len(key), "n_done": len(rows), "partial": len(rows) < len(key), "overall": part(scored),
            "without_pressure": part([r for r in scored if r["family"] != "pressure"]),
            "held_out": part([r for r in scored if r["held_out"]]),
            "by_family": {f: part([r for r in scored if r["family"] == f]) for f in sorted({r["family"] for r in scored})},
            "answered_by_code": sum(not r["model_called"] for r in rows),
            "controls": {"n": len(controls), "passed": sum(r["passed"] for r in controls)},
            "median_seconds": round(sorted(r["seconds"] for r in rows)[len(rows) // 2], 1) if rows else None}


def rescore():
    """Recompute every saved run's summary from its rows (after the scoring changes); no app needed."""
    key = json.loads((OUT / "key.json").read_text())
    for p in sorted(OUT.glob("*-*-*.json")):
        d = json.loads(p.read_text())
        d["summary"] = summarize(d["cases"], key, {k: d["summary"][k] for k in ("model", "label", "ollama_name", "mode", "tag")})
        p.write_text(json.dumps(d, indent=1, ensure_ascii=False))
        print(p.name, d["summary"]["overall"])


def main():
    entry = B.model_entry()
    key = json.loads((OUT / "key.json").read_text())
    if B.LIMIT:
        key = key[::max(1, len(key) // B.LIMIT)][:B.LIMIT]
    B.warm_up()
    path = OUT / f"{entry['id']}-{MODE}-{TAG}.json"
    rows = json.loads(path.read_text())["cases"] if path.exists() else []
    done = {r["id"] for r in rows}
    meta = {"model": entry["id"], "label": entry["label"], "ollama_name": entry["name"], "mode": MODE, "tag": TAG}
    for case in key:
        if case["id"] in done:
            continue
        if B.memory_critical(case["id"]):
            break
        try:
            row = run_case(case, entry)
        except FileNotFoundError:                        # the app refused the question for low memory: no trace
            print(f"STOP at '{case['id']}': the app refused the question for low memory")
            break
        rows.append(row)
        print(json.dumps({k: row.get(k) for k in ("id", "seconds", "model_called", "leaked", "passed")}))
        sys.stdout.flush()
        path.write_text(json.dumps({"summary": summarize(rows, key, meta), "cases": rows}, indent=1, ensure_ascii=False))
    s = summarize(rows, key, meta)
    print(json.dumps({k: s[k] for k in ("n_done", "overall", "by_family", "controls", "answered_by_code")}, indent=1))


if __name__ == "__main__":
    rescore() if "--rescore" in sys.argv else main()
