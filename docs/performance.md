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

## Model evaluation (50 questions)

Every model answers the same 50 questions through the app, on an 8 GB M1. The answer key is built from the decision cards (`tests/make_key.py`), which `tests/testDecisions.m` checks against the actual rate change for all 150 meetings. The 50 questions are 12 decisions, 8 reworded decisions (stability), 6 votes, 3 follow-ups, 5 "not public yet" refusals, 8 topics, 4 year comparisons and 4 "why" questions. The 4 "why" questions have no key, so 46 are scored. See them on the Evaluation page (`/evaluation`) or in `data/model_evaluation_summary.csv` and `data/model_evaluation_cases.csv`.

| Model | Params | Correct | Bare model | Wrong with no warning | Median answer (s) | Memory when loaded |
|---|---|---|---|---|---|---|
| IBM Granite 3.3 2B | 2.5B | 42/46 (91%) | 17/46 (37%) | 4 | 9.40 | 1.83 GB (23%) |
| Qwen3 4B | 4.0B | 42/46 (91%) | 20/46 (43%) | 4 | 14.60 | 3.01 GB (38%) |
| Qwen2.5 3B | 3.1B | 38/46 (83%) | 17/46 (37%) | 7 | 8.40 | 2.11 GB (26%) |
| Llama 3.2 3B | 3.2B | 38/46 (83%) | 16/46 (35%) | 5 | 13.80 | 2.43 GB (30%) |
| Qwen2.5 1.5B | 1.5B | 37/46 (80%) | 13/46 (28%) | 5 | 4.80 | 1.17 GB (15%) |
| Qwen3 0.6B (thinking build) | 0.6B | 37/46 (80%) | 12/46 (26%) | 5 | 6.90 | 0.83 GB (10%) |
| Qwen3 1.7B (thinking build) | 1.7B | 29/46 (63%) | 6/46 (13%) | 8 | 16.25 | 1.44 GB (18%) |
| Qwen2.5 0.5B | 0.5B | 24/46 (52%) | 7/46 (15%) | 5 | 2.60 | 0.50 GB (6%) |

The Qwen3 0.6B and 1.7B rows are "thinking" builds (`qwen3:0.6b`, `qwen3:1.7b`), while Qwen3 4B is the non-thinking `qwen3:4b-instruct`. Their reasoning text uses up the answer budget: 6 of 50 bare Qwen3 0.6B answers came back empty, and in the app the 1.7B writes a median of 450 tokens against 106 for the 4B. Their scores and latency are not comparable with the other rows.

With only 46 scored questions, each result has a 95% range of roughly 12 points either side, so gaps of a few points are not real differences. Granite 2B and Qwen3 4B tie. Parameter count is a weak predictor: a 0.6B model matches a 1.5B model.

**What the app adds.** Each model asked the same questions bare, with no tools, minutes, data, guardrail or citation check (`tests/bench_baseline.py`). The "Bare model" column above is that result. Decisions right, app against bare: Qwen3 4B 12 and 2 (of 12), Qwen2.5 3B 12 and 0, Granite 2B 12 and 2.

Most of the accuracy comes from the app's lookups and checks, not from what the model memorized. The topic and comparison checks are lenient (a topic word or a year), so the bare model scores well there; its decisions, votes and refusals show the real gap.

**Wrong with no warning** counts wrong answers that the page did not flag as unverified, the errors a user would not be told about. The page's warning catches none of the top two models' four mistakes each.

**Memory** is the size Ollama reports for the loaded model with its 8,192-token context (`tests/measure_memory.py`). The hidden MATLAB adds about 1 GB more.

An earlier note said a 1.5B model reached about 70%. On this key Qwen2.5 1.5B scores 80% (37 of 46).

### Found by the evaluation, not fixed here

- Reworded decision questions ("what happened to the federal funds rate target?") skip the decision card, so the model answers from general data and can state the wrong direction. This accounts for most stability misses.
- One refusal case showed an "Agent error" from the LLM add-on (`messageHistory.m`, `validateRegularAssistant`).
- The topic check passes when a topic word appears, even in "no mention of trade policy", and the comparison check only needs both years. Both are lenient.
- The "invented reason" flag is a heuristic (causal wording not found in the retrieved text), not proof.

Rerun with `tests/bench_live.py <modelId> --high` (about 10 to 15 minutes per model; the app must be running), then `tests/bench_live.py --rescore` and `tests/export_evals.py`.

## Models compared (earlier 10-question run)

The same 10 questions (`tests/bench_live.py`), 8 GB M1, after a restart:

| Model | Checks passed | Median answer | Notes |
|---|---|---|---|
| Qwen3 4B (default) | 20 of 20 | 15 s | Cites paragraph ids. Swap about 3.2 GB while loaded. |
| Qwen2.5 1.5B (dropped) | 19 of 20 | 6 s | Rarely cites ids, so the page warns "unverified". Correct on the unreleased-meeting question, but worded differently than the check expects. Swap about 1.3 GB. |
| Llama 3.2 3B (dropped) | 19 of 20 | 15 s | Never cited ids, made more tool calls, and answered the unreleased June 2022 question with May's decision. |
| Qwen2.5 0.5B (dropped) | 12 to 14 of 20 (varies run to run) | 3 s | Often wrong: gave a made-up decision for a meeting whose minutes were not public yet, and its High-effort analysis failed its own checks. Not offered. |
| Qwen2.5 3B (balanced) | 20 of 20 | 11 s | Often does not cite paragraph ids, so the page warns "unverified". Swap about 2.3 GB while loaded. |
| IBM Granite 3.3 2B (compact) | 20 of 20 | 12 s | 2.5B parameters, Apache 2.0. Not faster than Qwen2.5 3B here (decodes quicker, reads the prompt slower). Often does not cite ids, and its High-effort analysis took 70 s and failed its own checks, so use it for chat. Swap about 2.7 GB. |

The page offers Qwen3 4B (best quality), IBM Granite 3.3 2B (balanced) and Qwen2.5 1.5B (fast). After the 50-question evaluation below, Qwen2.5 3B was replaced: Granite 2B scores higher with less memory. Granite is for Low and Medium effort only, because it failed the High-effort grounding check on all 5 test questions. Questions about a meeting whose minutes are not public yet are answered by the app itself in about 1 second, without asking the model, so no model can invent a decision for them.
