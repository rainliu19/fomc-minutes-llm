"""Look-ahead bias: how often does a model answer with what happened AFTER the as-of date?

    uv run app.py                                        # for --team and --one (not for --bare)
    python tests/bench_lookahead.py fast --team --tag v0 # a model id from models/models.json
    python tests/bench_lookahead.py fast --bare --tag v0 # the model alone: "Today is <as_of>", no tools or data
    python tests/bench_lookahead.py fast --team --tag v0 --limit 6    # a dry run on 6 cases spread over the key

Asks every question of evals/lookahead/key.json (tests/make_lookahead_key.py) and scores the answer with
tests/lookahead_score.py: leaked when it states the fact that became public after the as-of date and the tools did
not return it. Writes evals/lookahead/<model>-<mode>-<tag>.json (rows are saved as they finish; run again to
continue after a memory stop). The Evaluation page shows it. The regexes catch only the facts the key lists, so the
rate is a lower bound.
"""
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bench_baseline as BL                    # the bare model's call
import bench_live as B                         # the app call, memory guard, Wilson interval
import lookahead_score as ls

TAG = sys.argv[sys.argv.index("--tag") + 1] if "--tag" in sys.argv else "v0"
MODE = "bare" if "--bare" in sys.argv else "one" if "--one" in sys.argv else "team"
OUT = B.REPO / "evals" / "lookahead"


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
    if MODE == "bare":
        t0 = time.time()
        system = f"Today is {case['as_of']}. You answer questions about Federal Open Market Committee minutes."
        text, _ = BL.ask(entry["name"], [{"role": "system", "content": system}, {"role": "user", "content": case["question"]}])
        return re.sub(r"(?s)<think>.*?</think>", "", text).strip(), "", {"model_calls": 1}, time.time() - t0, [], ""
    sid = B.uuid.uuid4().hex
    t0 = time.time()
    r = B.post("/chat", {"message": case["question"], "session_id": sid, "as_of": case["as_of"], "effort": "low",
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
        row["leak"] = ls.leaked(case, answer, tools)
        row["leaked"] = row["leak"] is not None
    return row


def summarize(rows, key, meta):
    """The numbers the Evaluation page shows: the error rate with its interval, per family, held out, controls."""
    scored = [r for r in rows if r["family"] != "control"]
    k = sum(r["leaked"] for r in scored)

    def part(rs):
        n, kk = len(rs), sum(r["leaked"] for r in rs)
        return {"n": n, "leaked": kk, "rate": round(kk / n, 3) if n else None, "ci95": B.wilson(kk, n)}

    controls = [r for r in rows if r["family"] == "control"]
    return {**meta, "n_key": len(key), "n_done": len(rows), "partial": len(rows) < len(key), "overall": part(scored),
            "without_pressure": part([r for r in scored if r["family"] != "pressure"]),
            "held_out": part([r for r in scored if r["held_out"]]),
            "by_family": {f: part([r for r in scored if r["family"] == f]) for f in sorted({r["family"] for r in scored})},
            "answered_by_code": sum(not r["model_called"] for r in rows),
            "controls": {"n": len(controls), "passed": sum(r["passed"] for r in controls)},
            "median_seconds": round(sorted(r["seconds"] for r in rows)[len(rows) // 2], 1) if rows else None}


def main():
    entry = next((m for m in json.loads((B.REPO / "models" / "models.json").read_text()) if m["id"] == B.MODEL), None)
    if entry is None:
        sys.exit(f"Unknown model id '{B.MODEL}'. Ids are in models/models.json.")
    key = json.loads((OUT / "key.json").read_text())
    if B.LIMIT:
        key = key[::max(1, len(key) // B.LIMIT)][:B.LIMIT]
    if MODE != "bare":                                   # opening the page starts loading the model
        B.OPENER.open(B.BASE + "/", timeout=60).read()
        B.OPENER.open(B.BASE + "/info?model=" + B.MODEL, timeout=60).read()
        time.sleep(25)
    path = OUT / f"{entry['id']}-{MODE}-{TAG}.json"
    rows = json.loads(path.read_text())["cases"] if path.exists() else []
    done = {r["id"] for r in rows}
    meta = {"model": entry["id"], "label": entry["label"], "ollama_name": entry["name"], "mode": MODE, "tag": TAG}
    for case in key:
        if case["id"] in done:
            continue
        free, swap = B.memory()
        if B.pressure() == 4 or swap > 3600:
            print(f"STOP before '{case['id']}': memory critical ({free}% free, {swap:.0f} MB swap)")
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
    main()
