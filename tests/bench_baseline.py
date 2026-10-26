"""Baseline: the same 50 questions asked to the bare model, with none of our app around it.

    python tests/bench_baseline.py qwen3        # needs Ollama running (the app starts it; or `ollama serve`)

The model gets only the question and the date ("Today is <anchor>"), the same Ollama model and
context size as the app, but no tools, no decision cards, no retrieved minutes, no guardrail and no
citation check. Scored with the same key as tests/bench_live.py, so evals/<modelId>-baseline.json
shows on the Evaluation page next to the full app and the gap is what the app adds. Do not run it
while a bench_live run is going: two things loading models on 8 GB will run out of memory.
"""
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bench_live as B                         # same scoring, summary and memory helpers

OLLAMA = "http://127.0.0.1:11434"
MAX_TOKENS = 450                               # the Low effort answer cap in the app


def ask(model_name, messages):
    """One non-streaming chat call to Ollama; returns the text and its token stats."""
    body = {"model": model_name, "messages": messages, "stream": False, "options": {"num_predict": MAX_TOKENS}}
    req = urllib.request.Request(OLLAMA + "/api/chat", json.dumps(body).encode(), {"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=900))
    return r["message"]["content"], r


def run_case(entry, case):
    """Ask a case's questions in one conversation; score the last answer with the key."""
    messages = [{"role": "system", "content": f"Today is {case['as_of']}. You answer questions about Federal Open Market Committee minutes."}]
    answer, r, total = "", {}, 0.0
    for q in case["questions"]:
        messages.append({"role": "user", "content": q})
        t0 = time.time()
        answer, r = ask(entry["name"], messages)
        total = time.time() - t0
        messages.append({"role": "assistant", "content": answer})
    answer = re.sub(r"(?s)<think>.*?</think>", "", answer).strip()      # drop a thinking model's scratch text
    p_ms, o_ms = r.get("prompt_eval_duration", 0) / 1e6, r.get("eval_duration", 0) / 1e6
    stats = {"model_calls": len(case["questions"]), "prompt_tokens": r.get("prompt_eval_count", 0), "output_tokens": r.get("eval_count", 0),
             "prefill_tok_s": round(r.get("prompt_eval_count", 0) / (p_ms / 1000), 1) if p_ms else None,
             "decode_tok_s": round(r.get("eval_count", 0) / (o_ms / 1000), 1) if o_ms else None}
    row = {"id": case["id"], "category": case["category"], "effort": "low", "group": case.get("group"), "seconds": round(total, 1),
           "tools": [], "stats": stats, "citations_ok": 0, "citations_total": 0, "warning": "", "answer": answer[:700],
           "invented_reason": B.unsupported_cause(answer, ""),          # no sources at all, so any stated cause is unsupported
           "expected_tool": None, "tool_ok": None}
    row["passed"] = (all(re.search(c, answer) for c in case["checks"]) and not any(re.search(f, answer) for f in case["forbid"])) if case["checks"] else None
    return row


def main():
    entry = next((m for m in json.loads((B.REPO / "models" / "models.json").read_text()) if m["id"] == B.MODEL), None)
    if entry is None:
        sys.exit(f"Unknown model id '{B.MODEL}'. Ids are in models/models.json.")
    key = json.loads((B.REPO / "evals" / "key.json").read_text())
    if B.LIMIT:
        key = key[:B.LIMIT]
    path = B.REPO / "evals" / f"{entry['id']}-baseline.json"
    rows = json.loads(path.read_text())["cases"] if path.exists() else []         # continue a run that stopped early
    done = {r["id"] for r in rows}
    for case in key:
        if case["id"] in done:
            continue
        free, swap = B.memory()
        if B.pressure() == 4 or swap > 3600:
            print(f"STOP before '{case['id']}': memory critical ({free}% free, {swap:.0f} MB swap)")
            break
        row = run_case(entry, case)
        free, swap = B.memory()
        row.update({"free_pct": free, "swap_mb": round(swap)})
        rows.append(row)
        print(json.dumps({k: row[k] for k in ("id", "seconds", "passed", "swap_mb")}))
        sys.stdout.flush()
    meta = {"model": entry["id"] + "-baseline", "label": entry["label"].split(": ")[-1] + ", bare model", "params_b": entry.get("params_b"),
            "ollama_name": entry["name"], "date": time.strftime("%Y-%m-%d"), "baseline": True, "complete": len(rows) == len(key)}
    out = {"summary": B.summarize(rows, meta), "cases": rows}
    path.write_text(json.dumps(out, indent=1))
    print(json.dumps(out["summary"]["by_category"]), "accuracy", out["summary"]["accuracy"], "->", path)


main()
