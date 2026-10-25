"""Write the saved evaluations (evals/<modelId>.json) to two CSV files in data/.

    python tests/export_evals.py

data/model_evaluation_summary.csv: one row per model with Model, Params, Correct, Baseline,
                                   Median Latency and Memory. Baseline is the same model asked bare.
data/model_evaluation_cases.csv:   one row per question asked, with the answer.
Needs no model; run it after tests/bench_live.py and tests/bench_baseline.py finish.
"""
import csv
import json
from pathlib import Path

REPO = Path(__file__).parent.parent


def pct_text(s):
    """'42/46 (91%)' for a run's scored questions."""
    return f"{s['correct']}/{s['n_scored']} ({round(100 * s['correct'] / s['n_scored'])}%)"


def summary_rows(runs):
    """One row per model: with-app score, bare-model score (if it was run), latency and memory."""
    bare = {r["summary"]["model"].removesuffix("-baseline"): r["summary"] for r in runs if r["summary"].get("baseline")}
    rows = []
    for r in runs:
        s = r["summary"]
        if s.get("baseline"):
            continue
        mem = s.get("model_memory_mb")
        rows.append({"Model": s["label"].split(": ")[-1], "Params": f"{s['params_b']}B", "Correct": pct_text(s),
                     "Baseline": pct_text(bare[s["model"]]) if s["model"] in bare else "not run",
                     "Median Latency": f"{s['seconds_median']:.2f} s",
                     "Memory": f"{mem / 1024:.2f} GB ({round(s['model_memory_pct_of_8gb'])}%)" if mem else "not measured"})
    return rows


def main():
    runs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((REPO / "evals").glob("*.json")) if p.name != "key.json"]
    # Best first, as on the Evaluation page: accuracy, then the same model's bare-model accuracy, then speed.
    # A bare-model run sorts right after its model.
    by_model = {r["summary"]["model"]: r["summary"] for r in runs}        # a list being sorted cannot be read, so look up in this
    def order(r):
        s = r["summary"]; app = s["model"].removesuffix("-baseline")
        a, bare = by_model[app], by_model.get(app + "-baseline")
        return (-a["accuracy"], -(bare["accuracy"] if bare else -1), a["seconds_median"], s.get("baseline", False))
    runs.sort(key=order)
    out = REPO / "data"
    # One row per model
    rows = summary_rows(runs)
    with open(out / "model_evaluation_summary.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    # One row per question asked
    cases = []
    for r in runs:
        s = r["summary"]
        for c in r["cases"]:
            cases.append({"model_id": s["model"], "label": s["label"].split(": ")[-1], "params_b": s["params_b"], "case_id": c["id"], "category": c["category"],
                          "effort": c["effort"], "correct": "" if c["passed"] is None else c["passed"], "right_tool": "" if c["tool_ok"] is None else c["tool_ok"],
                          "seconds": c["seconds"], "tools": " ".join(c["tools"]), "verified_citations": c["citations_ok"], "citations": c["citations_total"],
                          "possible_invented_reason": "" if c["invented_reason"] is None else c["invented_reason"], "warning": c["warning"],
                          "swap_mb": c.get("swap_mb", ""), "answer": c["answer"].replace("\n", " ")})
    with open(out / "model_evaluation_cases.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(cases[0]))
        w.writeheader()
        w.writerows(cases)
    print(f"{len(rows)} models -> data/model_evaluation_summary.csv, {len(cases)} answers -> data/model_evaluation_cases.csv")


main()
