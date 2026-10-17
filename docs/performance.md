# Performance and memory

Measured on an 8 GB Apple M1 with `qwen3:4b-instruct` through Ollama and a hidden MATLAB, other apps closed. Reproduce with `tests/bench_live.py` while `uv run app.py` runs.

## Speed

| | Before | After |
|---|---|---|
| Chat question about a decision | 140 s (once a wrong answer) | 10 to 24 s, median 12 s |
| Structured analysis | 18 minutes | about 52 s |
| Fixed prompt, first turn | about 3,000 tokens | about 1,800 tokens |
| First question of a session | model load plus a long prompt | model loads while you type |

The model reads 330 to 2,200 tokens/s (fast when it reuses earlier work) and writes about 17 tokens/s, so time is mostly the length of what it writes. What helped:

- Decision, vote and dissent (with counts) come from a decision card read by code, not from the model reading 3,000 tokens of minutes.
- The harness fetches the decision card or the best passages before the model starts.
- Tool results are short pages of whole paragraphs with ids, not whole sections.
- Answers are capped, the system prompt never changes between sessions, and old tool results become stubs as the conversation grows.
- In analysis mode the model cites paragraph ids instead of copying quotes, and writes no draft.

## Accuracy (last live run)

20 of 20 objective checks passed over 10 questions: right decision and target range, dissenter and preference, vote counts, an honest "not public yet" for a meeting released after the anchor, and a correctly copied rate range. Every cited id was verified. The decision cards match the actual rate change for all 150 meetings (`tests/testDecisions.m`).

## Still weak

- An analysis summary can state a reason no cited paragraph gives (last run: "in response to labor market and inflation data" for March 2020). The checks cover ids, quotes and figures, not causes: treat the "why" as unverified.
- The 4B model can ignore a passage or misstate a number in free text. The page warns when an answer cites nothing verified or has a rate range not in its sources.
- A bigger model, or one on another machine, would improve quality and speed.

## Memory

On 8 GB the model (about 3 GB), the hidden MATLAB (about 1 GB) and macOS leave little room.

| Signal | During a run |
|---|---|
| macOS memory pressure | normal, sometimes warning, never critical |
| Free memory | 7 to 10% (normal with a loaded model; not a stop signal) |
| Swap in use | 1.6 GB at start, up to 2.8 GB |
| Load average | up to 6.4 (11 to 15 when apps crashed earlier) |

The app checks memory at start (refusing if low), before each question, and every 5 s during one; it stops the model it started only if pressure is critical or swap passes 3.8 GB. The model unloads 3 minutes after the last answer. An open MATLAB shared with `matlab.engine.shareEngine` is reused, saving about 1 GB. Starting MATLAB with `-nojvm` saved nothing (968 against 960 MB).

## Models compared

The same 10 questions (`tests/bench_live.py`), 8 GB M1, after a restart:

| Model | Checks passed | Median answer | Notes |
|---|---|---|---|
| Qwen3 4B (default) | 20 of 20 | 15 s | Cites paragraph ids. Swap about 3.2 GB while loaded. |
| Qwen2.5 1.5B (quick) | 19 of 20 | 6 s | Rarely cites ids, so the page warns "unverified". Correct on the unreleased-meeting question, but worded differently than the check expects. Swap about 1.3 GB. |
| Llama 3.2 3B (dropped) | 19 of 20 | 15 s | Never cited ids, made more tool calls, and answered the unreleased June 2022 question with May's decision. |
