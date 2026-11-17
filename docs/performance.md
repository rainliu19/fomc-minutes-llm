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

## Model evaluation (57 questions, three structures)

Every model answers the same 57 questions in three structures: **baseline** (the bare model: no tools, minutes or checks, `tests/bench_baseline.py`), **one agent** (the app's tools, lookups and checks, `tests/bench_live.py`) and **multi-agent** (an organizer plus minutes, market, scorer and consumer specialists, `--multi`). All 24 runs were made on 2026-11-16 and 17 with the same code and key, on an 8 GB Apple M1. Scores are out of the 53 questions with a key (the 4 "why" questions have none), so each has a 95% range of about 13 points either way.

The key (`evals/key.json`): 12 decisions, 8 reworded decisions (stability), 6 votes, 3 follow-ups, 5 "not public yet" refusals, 8 topics, 4 year comparisons, 4 "why", and 7 forward-looking cases written by hand (4 next-decision, 3 outlook). The decision answers are read from the minutes by code and checked against the actual rate change for all 150 meetings (`tests/testDecisions.m`).

| Model | Params | Baseline | One agent | Multi-agent | Median (s) one / multi | Memory loaded |
|---|---|---|---|---|---|---|
| IBM Granite 3.3 2B | 2.5B | 16/53 (30%) | 47/53 (89%) | 49/53 (92%) | 10.5 / 12.3 | 2.13 GB (27%) |
| Qwen3 4B | 4.0B | 21/53 (40%) | 51/53 (96%) | 52/53 (98%) | 15.3 / 17.2 | 3.61 GB (45%) |
| Qwen2.5 3B | 3.1B | 15/53 (28%) | 44/53 (83%) | 47/53 (89%) | 10.4 / 12.8 | 2.25 GB (28%) |
| Llama 3.2 3B | 3.2B | 13/53 (24%) | 47/53 (89%) | 47/53 (89%) | 14.8 / 21.9 | 2.90 GB (36%) |
| Qwen2.5 1.5B | 1.5B | 12/53 (23%) | 46/53 (87%) | 39/53 (74%) | 5.3 / 7.7 | 1.27 GB (16%) |
| Qwen3 0.6B (thinking build) | 0.6B | 14/53 (26%) | 42/53 (79%) | 48/53 (91%) | 9.4 / 9.6 | 1.26 GB (16%) |
| Qwen3 1.7B (thinking build) | 1.7B | 5/53 (9%) | 31/53 (58%) | 43/53 (81%) | 18.1 / 21.4 | 1.85 GB (23%) |
| Qwen2.5 0.5B | 0.5B | 10/53 (19%) | 34/53 (64%) | 19/53 (36%) | 2.7 / 2.1 | 0.54 GB (7%) |

What the runs show:

- **The app is most of the accuracy.** The bare models score 9 to 40%; one agent lifts every model to 58 to 96%. The lookups and checks, not the model's memory, answer most questions.
- **Multi-agent helps most models, by 0 to 23 points.** It is highest for Granite 2B, Qwen3 4B, Qwen2.5 3B, Qwen3 0.6B and Qwen3 1.7B, ties for Llama 3.2 3B, and usually takes 10 to 50% longer per answer.
- **It hurts the two smallest Qwen2.5 models** (1.5B: 87% to 74%; 0.5B: 64% to 36%). The 0.5B multi-agent run has 26 wrong answers with no warning (49% of the questions), against 6 for one agent: a model that small cannot follow the organizer's briefs. Use one agent below about 3B for these models.
- **Wrong with no warning** is the number a user would not be told about. One agent keeps it at 0 to 3 for every model except Qwen2.5 0.5B (6); multi-agent raises it for Qwen2.5 3B (0 to 5) and Qwen2.5 1.5B (0 to 8), because the critic's warning does not reach errors the specialists introduce.
- **Qwen3 4B is best** (98% multi-agent, 96% one agent) and also the largest in memory (3.6 GB of 8 GB). Granite 2B is the best small choice (92% and 89% at 2.1 GB).
- The two Qwen3 thinking builds (0.6B, 1.7B) spend their answer budget on reasoning, so their baseline and latency are not comparable with the other rows.
- A model's rank by one agent and by multi-agent can differ, so pick the structure per model, not once for all.

**Memory** is the size Ollama reports for the loaded model with its 8,192-token context (`tests/measure_memory.py`). The hidden MATLAB adds about 1 GB. **Tokens and cost** are on the Evaluation page and in `data/model_evaluation_summary.csv` (what the same tokens would cost on a paid API, from `models/api_prices.json`). After a price change, run `python tests/bench_live.py --rescore`.

Limits: one run per model per structure, so run-to-run variation is not measured; the answer check is lenient for topics and year comparisons (a topic word or the two years); the "wrong with no warning" count is small, so its differences are rough. Runs from October 2026 on the older 50-question key and code are in `evals/archive-2026-10/`.
