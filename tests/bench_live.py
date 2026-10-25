"""Live evaluation of one model through the web app: 50 answer-key cases, timing, memory, stability.

    uv run app.py                                      # one terminal, other apps closed
    python tests/bench_live.py qwen3                   # another: a model id from models/models.json
    python tests/bench_live.py qwen3 --high --limit 5  # also run the Low vs High subset; first 5 cases only

Reads evals/key.json (built from the decision cards by tests/make_key.py), sends each case to the app
at localhost:8787 and checks the LAST answer with regexes, so the key is objective. Writes
evals/<modelId>.json, which the Evaluation page (/evals) shows. Stops early on critical memory
pressure; run it again to continue where it stopped. About 10 minutes per model; the unit tests need no model.
"""
import http.cookiejar
import json
import math
import re
import statistics
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

# Where the running app listens, and the repo folder (for the trace files and the key)
BASE = "http://127.0.0.1:8787"
REPO = Path(__file__).parent.parent
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
MODEL = ARGS[0] if ARGS else ""                      # a model id; empty is the default
RUN_HIGH = "--high" in sys.argv
LIMIT = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 0
HIGH_CASES = {"decision-01", "decision-02", "decision-03", "why-01", "why-02"}   # the Low vs High subset
CAUSAL = re.compile(r"(?i)\b(because|due to|in response to|owing to|as a result of|driven by|reflect(?:ing|ed)|so as to|in order to)\b")

# One browser: the cookie keeps every message of a session under the same owner
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


# Helper: send JSON to the app and return its JSON reply
def post(path, body, timeout=900):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(OPENER.open(req, timeout=timeout))


# Helper: macOS memory pressure level (1 normal, 2 warning, 4 critical)
def pressure():
    return int(subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"], capture_output=True, text=True).stdout)


# Helper: percent of memory free and swap in use (MB)
def memory():
    out = subprocess.run(["memory_pressure"], capture_output=True, text=True).stdout
    free = int(re.search(r"free percentage:\s*(\d+)%", out).group(1))
    swap = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True).stdout
    used = float(re.search(r"used = ([\d.]+)M", swap).group(1))
    return free, used


def read_trace(session_id):
    """Token counts and speeds from the model calls in the session's trace, plus the text the tools returned."""
    path = REPO / "logs" / f"web-{session_id}.jsonl"
    # Add up tokens and times over every model call; collect what the tools returned
    p_tok = o_tok = p_ms = o_ms = rounds = 0
    tool_text = []
    for line in path.read_text().splitlines():
        e = json.loads(line)
        s = e.get("stats")
        if e["type"] in ("model_response", "grounding_check") and s:
            rounds += 1
            p_tok += s["promptTokens"]; o_tok += s["outputTokens"]; p_ms += s["promptMs"]; o_ms += s["outputMs"]
        if e["type"] == "tool_call":
            tool_text.append(json.dumps(e, ensure_ascii=False))
    stats = {"model_calls": rounds, "prompt_tokens": p_tok, "output_tokens": o_tok,
             "prefill_tok_s": round(p_tok / (p_ms / 1000), 1) if p_ms else None,
             "decode_tok_s": round(o_tok / (o_ms / 1000), 1) if o_ms else None}
    return stats, " ".join(tool_text)


def unsupported_cause(answer, tool_text):
    """Heuristic for an invented reason: a sentence with causal wording whose content words mostly
    do not appear in what the tools returned. None when the answer states no cause."""
    haystack = tool_text.lower()
    verdicts = []
    for sentence in re.split(r"(?<=[.!?])\s+", answer):
        if CAUSAL.search(sentence):
            words = {w for w in re.findall(r"[a-z]{5,}", sentence.lower())}
            if words:
                verdicts.append(sum(w in haystack for w in words) / len(words) < 0.6)
    return any(verdicts) if verdicts else None


def wilson(k, n, z=1.96):
    """95% interval for a share k of n (more honest than +/- for small n)."""
    if n == 0:
        return [None, None]
    p = k / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return [round(centre - half, 3), round(centre + half, 3)]


def run_case(case, effort):
    """Ask a case's questions in one chat; score the last answer."""
    sid = str(uuid.uuid4())
    answer, total, r = "", 0.0, {}
    for q in case["questions"]:
        t0 = time.time()
        r = post("/chat", {"message": q, "session_id": sid, "as_of": case["as_of"], "effort": effort, "model": MODEL})
        total = time.time() - t0                        # time of the last question in the chat
        answer = r["answer"]
    stats, tool_text = read_trace(sid)
    names = [c["name"] for c in r["tool_calls"]]
    cites = r.get("citations", [])
    row = {"id": case["id"], "category": case["category"], "effort": effort, "group": case.get("group"),
           "seconds": round(total, 1), "tools": names, "stats": stats,
           "citations_ok": sum(1 for c in cites if c["ok"]), "citations_total": len(cites),
           "warning": r.get("warning", ""), "invented_reason": unsupported_cause(answer, tool_text),
           "answer": answer[:700]}
    # A case passes when every check matches and no forbidden pattern does ("why" cases have no checks)
    if case["checks"]:
        row["passed"] = all(re.search(c, answer) for c in case["checks"]) and not any(re.search(f, answer) for f in case["forbid"])
    else:
        row["passed"] = None
    row["tool_ok"] = tool_used(case["tool"], names) if case["tool"] else None
    row["expected_tool"] = case["tool"]
    if effort == "high":
        st = r.get("structured") or {}
        row["grounding_ok"] = st.get("groundingOk")
    return row


# The app looks up the decision card and passages before the model starts, so those count as the tool
EQUIVALENT = {"getDecision": {"getDecision"}, "searchMinutes": {"searchMinutes", "prefetchPassages"}}


def tool_used(case_tool, tools):
    return bool(EQUIVALENT.get(case_tool, {case_tool}) & set(tools))


def share(rows, key):
    """(k, n) of rows where key is true, ignoring rows where it is None."""
    vals = [r[key] for r in rows if r.get(key) is not None]
    return sum(bool(v) for v in vals), len(vals)


def summarize(rows, meta):
    """Per-model numbers shown on the Evaluation page."""
    for r in ([] if meta.get("baseline") else rows):    # recomputed, so older saved rows follow the current rule
        if r.get("expected_tool") is None and r["category"] in ("topic", "comparison"):
            r["expected_tool"] = "searchMinutes"
        elif r.get("expected_tool") is None and r["category"] in ("decision", "stability", "vote", "followup", "why"):
            r["expected_tool"] = "getDecision"
        if r.get("expected_tool"):
            r["tool_ok"] = tool_used(r["expected_tool"], r["tools"])
    low = [r for r in rows if r["effort"] == "low"]
    scored = [r for r in low if r["passed"] is not None]
    k = sum(r["passed"] for r in scored)
    by_cat = {}
    for cat in sorted({r["category"] for r in scored}):
        kc, nc = share([r for r in scored if r["category"] == cat], "passed")
        by_cat[cat] = {"correct": kc, "n": nc}
    # Stability: a group is stable when every reworded version of the question passes (or all fail the same way)
    groups = {}
    for r in scored:
        if r["group"]:
            groups.setdefault(r["group"], []).append(r["passed"])
    stable = sum(1 for v in groups.values() if len(set(v)) == 1 and v[0])
    secs = sorted(r["seconds"] for r in low)
    decode = [r["stats"]["decode_tok_s"] for r in low if r["stats"]["decode_tok_s"]]
    cites = sum(r["citations_ok"] for r in low), sum(r["citations_total"] for r in low)
    inv_k, inv_n = share([r for r in low if r["category"] == "why"], "invented_reason")
    # Wrong answers that came with no warning on the page: the errors a user would not be told about
    silent = sum(1 for r in scored if r["passed"] is False and not r["warning"])
    tool_k, tool_n = share(low, "tool_ok")
    return {**meta, "n_cases": len(low), "correct": k, "n_scored": len(scored), "accuracy": round(k / len(scored), 3) if scored else None,
            "accuracy_ci": wilson(k, len(scored)), "by_category": by_cat,
            "silent_errors": {"count": silent, "n": len(scored), "rate": round(silent / len(scored), 3) if scored else None,
                              "ci": wilson(silent, len(scored)), "wrong": len(scored) - k,
                              "warned_wrong": sum(1 for r in scored if r["passed"] is False and r["warning"])},
            "stability": {"stable_groups": stable, "groups": len(groups)},
            "tool_accuracy": {"ok": tool_k, "n": tool_n},
            "cases_citing_verified_id": sum(1 for r in low if r["citations_ok"] > 0), "cases_with_warning": sum(1 for r in low if r["warning"]),
            "citations": {"verified": cites[0], "total": cites[1]},
            "invented_reason": {"flagged": inv_k, "n": inv_n, "note": "heuristic: causal wording not found in tool results"},
            "seconds_median": statistics.median(secs) if secs else None,
            "seconds_p90": secs[min(len(secs) - 1, int(0.9 * len(secs)))] if secs else None,
            "decode_tok_s_median": statistics.median(decode) if decode else None,
            "peak_swap_mb": max(r["swap_mb"] for r in rows) if rows else None}


def main():
    entry = next((m for m in json.loads((REPO / "models" / "models.json").read_text()) if m["id"] == MODEL), None)
    if entry is None:
        sys.exit(f"Unknown model id '{MODEL}'. Ids are in models/models.json.")
    key = json.loads((REPO / "evals" / "key.json").read_text())
    if LIMIT:
        key = key[:LIMIT]
    # Opening the page starts loading the model; give it time, as a user typing would
    OPENER.open(BASE + "/", timeout=60).read()
    OPENER.open(BASE + "/info?model=" + MODEL, timeout=60).read()
    time.sleep(25)
    path = REPO / "evals" / f"{entry['id']}.json"
    # A run that stopped early (memory) is continued: finished cases are kept, only the rest are asked
    rows = json.loads(path.read_text())["cases"] if path.exists() else []
    done = {(r["id"], r["effort"]) for r in rows}
    # Each case at Low effort, then (with --high) the small subset again at High effort
    todo = [(c, "low") for c in key] + ([(c, "high") for c in key if c["id"] in HIGH_CASES] if RUN_HIGH else [])
    for case, effort in todo:
        if (case["id"], effort) in done:
            continue
        free, swap = memory()
        if pressure() == 4 or swap > 3600:
            print(f"STOP before '{case['id']}': memory critical ({free}% free, {swap:.0f} MB swap)")
            break
        try:
            row = run_case(case, effort)
        except FileNotFoundError:                        # the app refused the question (low memory): no trace was written
            print(f"STOP at '{case['id']}': the app refused the question for low memory")
            break
        free, swap = memory()
        row.update({"free_pct": free, "swap_mb": round(swap)})
        rows.append(row)
        print(json.dumps({k: row[k] for k in ("id", "effort", "seconds", "passed", "tool_ok", "swap_mb")}))
        sys.stdout.flush()
    meta = {"model": entry["id"], "label": entry["label"], "params_b": entry.get("params_b"), "ollama_name": entry["name"],
            "date": time.strftime("%Y-%m-%d"), "complete": len([r for r in rows if r["effort"] == "low"]) == len(key)
            and (not RUN_HIGH or len([r for r in rows if r["effort"] == "high"]) == len([c for c in key if c["id"] in HIGH_CASES]))}
    out = {"summary": summarize(rows, meta), "cases": rows}
    high = [r for r in rows if r["effort"] == "high"]
    if high:
        out["summary"]["high_effort"] = {"n": len(high), "median_seconds": statistics.median(r["seconds"] for r in high),
                                         "grounding_ok": share(high, "grounding_ok")}
    path.write_text(json.dumps(out, indent=1))
    print(json.dumps(out["summary"]["by_category"]), "accuracy", out["summary"]["accuracy"], "->", path)


def rescore():
    """Rebuild each evals/<id>.json summary from its saved cases, after a scoring rule changed. Needs no model."""
    for path in sorted((REPO / "evals").glob("*.json")):
        if path.name == "key.json":
            continue
        d = json.loads(path.read_text())
        old = d["summary"]
        meta = {k: old[k] for k in ("model", "label", "params_b", "ollama_name", "date", "complete") if k in old}
        # Labels come from models/models.json, so renaming a model there renames its saved results too
        label = next((e["label"] for e in json.loads((REPO / "models" / "models.json").read_text()) if e["id"] == path.stem.replace("-baseline", "")), None)
        if label:
            meta["label"] = label.split(": ")[-1] + ", bare model" if old.get("baseline") else label
        if old.get("baseline"):
            meta["baseline"] = True
        d["summary"] = summarize(d["cases"], meta)
        for extra in ("high_effort", "model_memory_mb", "model_memory_pct_of_8gb"):    # measured separately; keep them
            if extra in old:
                d["summary"][extra] = old[extra]
        base = path.with_name(path.name.replace("-baseline", ""))          # a bare-model row has the same model's memory
        if old.get("baseline") and base.exists() and "model_memory_mb" not in d["summary"]:
            app = json.loads(base.read_text())["summary"]
            for extra in ("model_memory_mb", "model_memory_pct_of_8gb"):
                if extra in app:
                    d["summary"][extra] = app[extra]
        path.write_text(json.dumps(d, indent=1))
        print("rescored", path.name, d["summary"]["accuracy"], d["summary"]["silent_errors"])


if __name__ == "__main__":
    rescore() if "--rescore" in sys.argv else main()
