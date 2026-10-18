"""Live benchmark of the web app: real questions, objective checks, timing, tokens, memory.

    uv run app.py                                   # one terminal, other apps closed
    python tests/bench_live.py results.json qwen3   # another: output file, model id from models/models.json

Sends 10 questions to the app at localhost:8787 and checks each answer against facts testable by
code (decision, vote, copied figures). Prints seconds, model and tool calls, token speeds and
verified citations. Stops early on critical memory pressure. Uses the real model (about 4 minutes);
the unit tests need no model.
"""
import http.cookiejar
import json
import re
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

# Where the running app listens, and the repo folder (for the trace files)
BASE = "http://127.0.0.1:8787"
REPO = Path(__file__).parent.parent
MODEL = sys.argv[2] if len(sys.argv) > 2 else ""   # a model id; empty is the default


# Helper: send JSON to the app and return its JSON reply
# One browser: the cookie keeps every message of a session under the same owner
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


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


def trace_stats(session_id):
    """Prompt/output tokens and speeds from the model calls recorded in the session's trace."""
    path = REPO / "logs" / f"web-{session_id}.jsonl"
    # Add up tokens and times over every model call in the trace
    p_tok = o_tok = p_ms = o_ms = rounds = 0
    for line in path.read_text().splitlines():
        e = json.loads(line)
        s = e.get("stats")
        if e["type"] in ("model_response", "grounding_check") and s:
            rounds += 1
            p_tok += s["promptTokens"]; o_tok += s["outputTokens"]; p_ms += s["promptMs"]; o_ms += s["outputMs"]
    return {"model_calls": rounds, "prompt_tokens": p_tok, "output_tokens": o_tok,
            "prefill_tok_s": round(p_tok / (p_ms / 1000), 1) if p_ms else None,
            "decode_tok_s": round(o_tok / (o_ms / 1000), 1) if o_ms else None}


# (label, as_of, effort ("low" chat, "high" analysis), questions, regexes the LAST answer must match)
# Each case: a name, the anchor date, chat or analysis, the questions asked in order, and patterns the last answer must match
CASES = [
    ("decision (Mar 2020)", "2020-04-08", "low",
     ["What did the Committee decide at its most recent meeting?"],
     [r"(?i)\b(cut|lower)", r"1/4|0\.25", r"(?is)^(?!.*held steady)", r"(?is)^(?!.*not read any minutes)"]),
    ("follow-up: dissent", "2020-04-08", "low",
     ["What did the Committee decide at its most recent meeting?", "Who dissented and why?"],
     [r"Mester", r"1/2 to 3/4|0\.50|0\.5"]),
    ("topic search (labor)", "2020-04-08", "low",
     ["How did participants describe the labor market?"],
     [r"(?i)labor|employment|unemployment"]),
    ("decision (Jun 2022, public)", "2022-07-10", "low",
     ["What did the Committee decide in June 2022 and was the vote unanimous?"],
     [r"(?i)raise|increase", r"George", r"1-1/2|1\.5"]),
    ("June 2022 asked before release", "2022-07-01", "low",
     ["What did the Committee decide in June 2022?"],
     [r"(?i)not (yet )?(been )?(public|released|available)|unavailable|no minutes"]),
    ("decision (hold, Sep 2023)", "2023-10-15", "low",
     ["What did the Committee decide in September 2023?"],
     [r"(?i)maintain|held|hold|keep|unchanged|steady|leave", r"5-1/4|5\.25", r"(?is)^(?!.*\b(raised|lowered)\b)"]),
    ("topic: inflation views (2019)", "2019-10-01", "low",
     ["What did participants say about inflation?"],
     [r"(?i)inflation"]),
    ("multi-year comparison", "2022-12-31", "low",
     ["How did the Committee's view of inflation change between 2021 and 2022?"],
     [r"(?i)inflation", r"2021|2022"]),
    ("latest meeting, default anchor", "", "low",
     ["What did the Committee decide at its latest meeting?"],
     [r"(?i)raise|increase", r"(?is)^(?!.*not read any minutes)"]),
    ("analysis mode (Mar 2020)", "2020-04-08", "high",
     ["Analyze the most recent meeting: what was decided and why?"],
     [r"(?is)^(?!.*not read any minutes)"]),
]


def main():
    # Opening the page calls /info, which starts loading the model; then the user types
    # Opening the page starts loading the model; give it time, as a user typing would
    OPENER.open(BASE + "/", timeout=60).read()
    OPENER.open(BASE + "/info?model=" + MODEL, timeout=60).read()
    time.sleep(25)
    results = []
    # Run each case: stop if memory is critical, ask the questions in one session, then check the last answer
    for label, as_of, mode, questions, checks in CASES:
        free, swap = memory()
        if pressure() == 4 or swap > 3600:
            print(f"STOP before '{label}': memory critical ({free}% free, {swap:.0f} MB swap)")
            break
        sid = str(uuid.uuid4())
        total = 0.0
        answer = ""
        r = {}
        for q in questions:
            t0 = time.time()
            r = post("/chat", {"message": q, "session_id": sid, "as_of": as_of, "effort": mode, "model": MODEL})
            total = time.time() - t0               # time of the last question in the session
            answer = r["answer"]
        # Which of the patterns the answer matches
        passed = [bool(re.search(c, answer)) for c in checks]
        stats = trace_stats(sid)
        free, swap = memory()
        # Collect timing, tools used, checks passed, memory and citations for this case
        row = {"case": label, "mode": mode, "seconds": round(total), "tools": [c["name"] for c in r["tool_calls"]],
               "checks_passed": f"{sum(passed)}/{len(passed)}" if checks else "n/a", "free_pct": free,
               "swap_mb": round(swap), "citations": [(c["id"], c["ok"]) for c in r.get("citations", [])], "warning": r.get("warning", ""),
               "stats": stats, "answer": answer[:700]}
        # Analysis mode also reports whether the checks passed and which paragraphs were cited
        if mode == "high":
            st = r.get("structured") or {}
            row["grounding_ok"] = st.get("groundingOk")
            row["structured"] = {k: st.get(k) for k in ("policyStance", "summary", "groundingFailures")}
            row["evidence_ids"] = [e.get("id") for e in (st.get("evidence") or []) if isinstance(e, dict)]
        results.append(row)
        print(json.dumps({k: row[k] for k in ("case", "seconds", "tools", "checks_passed", "free_pct", "swap_mb", "stats")}))
        sys.stdout.flush()
    # Save all results to a file if a file name was given
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(json.dumps(results, indent=2))


main()
