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

## Model evaluation (57 questions, three structures, plus a held-out check)

Every model answers the same questions in three structures: **multi-agent** (an organizer plus minutes, market, scorer and consumer specialists and a critic, `--multi`), **one agent** (the app's tools, lookups and checks, `tests/bench_live.py`) and **baseline** (the bare model: no tools, minutes or checks, `tests/bench_baseline.py`). The order is final version, first version, baseline. All runs were made on 2026-11-16 and 17 with the same code on an 8 GB Apple M1; the multi-agent runs of three models were repeated after the critic gained a target-range check (earlier runs are in `evals/archive-2026-11-multi-v1/` and `-v2/`). The main key's scores are out of the 53 questions that have a key (the 4 "why" questions have none), so each has a 95% range of about 13 points either way.

The key (`evals/key.json`): 12 decisions, 8 reworded decisions (stability), 6 votes, 3 follow-ups, 5 "not public yet" refusals, 8 topics, 4 year comparisons, 4 "why", and 7 forward-looking cases written by hand (4 next-decision, 3 outlook). The decision answers are read from the minutes by code and checked against the actual rate change for all 150 meetings (`tests/testDecisions.m`). The multi-agent checks were built while looking at this key's mistakes, so a **held-out key** (`evals/heldout/key.json`, 36 questions, built by `tests/make_heldout_key.py` on meetings, topics and wordings the main key never uses, all scored) is the fairer test of them.

The three builds the app offers come first: **Balanced** (IBM Granite 3.3 2B, the one that works best overall), **Best quality** (Qwen3 4B, the slowest and most accurate) and **Fast** (Qwen2.5 0.5B, the least memory and the quickest). The other models follow, ordered by multi-agent accuracy.

| Model | Params | Multi-agent | One agent | Baseline | Held-out: multi | Held-out: one | Held-out: baseline | Median (s) multi / one | Memory loaded | Wrong with no warning, multi / one | Multi answers from code |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Balanced: IBM Granite 3.3 2B | 2.5B | 50/53 (94%) | 47/53 (89%) | 16/53 (30%) | 36/36 (100%) | 36/36 (100%) | 6/36 (17%) | 15.6 / 10.5 | 2.13 GB (27%) | 3 / 1 | 2 |
| Best quality: Qwen3 4B | 4.0B | 53/53 (100%) | 51/53 (96%) | 21/53 (40%) | 36/36 (100%) | 36/36 (100%) | 12/36 (33%) | 15.9 / 15.3 | 3.61 GB (45%) | 0 / 0 | 1 |
| Fast: Qwen2.5 0.5B | 0.5B | 47/53 (89%) | 34/53 (64%) | 10/53 (19%) | 36/36 (100%) | 26/36 (72%) | 5/36 (14%) | 3.8 / 2.7 | 0.54 GB (7%) | 0 / 6 | 20 |
| Qwen2.5 3B | 3.1B | 50/53 (94%) | 44/53 (83%) | 15/53 (28%) | 36/36 (100%) | 32/36 (89%) | 9/36 (25%) | 16.9 / 10.4 | 2.25 GB (28%) | 1 / 0 | 1 |
| Qwen3 0.6B (thinking build) | 0.6B | 48/53 (91%) | 42/53 (79%) | 14/53 (26%) | 36/36 (100%) | 32/36 (89%) | 9/36 (25%) | 10.1 / 9.4 | 1.26 GB (16%) | 5 / 1 | 3 |
| Qwen3 1.7B (thinking build) | 1.7B | 48/53 (91%) | 31/53 (58%) | 5/53 (9%) | 34/36 (94%) | 28/36 (78%) | 1/36 (3%) | 17.6 / 18.1 | 1.85 GB (23%) | 4 / 3 | 1 |
| Llama 3.2 3B | 3.2B | 48/53 (91%) | 47/53 (89%) | 13/53 (25%) | 35/36 (97%) | 34/36 (94%) | 10/36 (28%) | 18.5 / 14.8 | 2.90 GB (36%) | 1 / 0 | 9 |
| Qwen2.5 1.5B | 1.5B | 46/53 (87%) | 46/53 (87%) | 12/53 (23%) | 35/36 (97%) | 31/36 (86%) | 6/36 (17%) | 7.5 / 5.3 | 1.27 GB (16%) | 2 / 0 | 4 |

What the runs show:

- **The app is most of the accuracy.** The bare models score 3 to 40%; one agent lifts every model to 58 to 96% on the main key. The lookups and checks, not the model's memory, answer most questions.
- **Multi-agent is above one agent for every model on the main key except Qwen2.5 1.5B (a tie at 46/53), and above or level with it on the held-out key.** Ties on the held-out key are Granite 2B and Qwen3 4B, both at 36/36, which cannot be beaten. The gain is 0 to 17 points on the main key and 0 to 6 on the held-out key, and a team answer takes up to 60% longer.
- **How much of that comes from code.** The critic checks a draft in code against the decision card (an answer that is only a paragraph id, a vote or direction the card contradicts, a target range that is not the card's) and asks for one rewrite; if the rewrite fails it answers from the card. The last column counts those answers on the main key. For Qwen2.5 0.5B it is 20 of 57, so most of its gain (34 to 47) is the card, not the model; for the others it is 1 to 9.
- **What fixed the two small Qwen2.5 models.** The first team runs scored lower than one agent for Qwen2.5 1.5B (74% vs 87%) and 0.5B (36% vs 64%). The writer often answered with a bare paragraph id (it copied the example id in the instruction line), or contradicted the card (not unanimous when it was), or returned nothing. The example id is gone, the critic now catches those cases in code, and the card answer is the fallback.
- **Wrong with no warning** is the number a user would not be told about. Multi-agent has more of them than one agent for Qwen3 0.6B (5 vs 1), Granite 2B (3 vs 1) and Qwen3 1.7B (4 vs 3) on the main key; most are a wrong figure or direction the checks do not reach.
- **Qwen3 4B is most accurate** (100% multi-agent, 96% one agent) and the largest in memory (3.6 GB of 8 GB). Granite 2B is the best small choice (94% and 89% at 2.1 GB); Qwen2.5 0.5B, the Fast build, reaches 89% in 0.5 GB and about 4 seconds a team answer, but 20 of its 57 answers come from the decision card, so it is only as good as the card's coverage (decisions, votes, dissents); it is weak on open questions. Qwen2.5 1.5B is the alternative: 87% at 1.3 GB with a team and one agent alike, and fewer answers from code (4 of 57).
- Accuracy rises with model size overall; Qwen3 0.6B and Llama 3.2 3B sit a little off the line.
- The two Qwen3 thinking builds (0.6B, 1.7B) spend their answer budget on reasoning, so their baseline and latency are not comparable with the other rows.
- Five models' multi-agent runs were made before the range check was added (it can only replace a wrong range with the card's), so their scores are lower bounds.

**Memory** is the size Ollama reports for the loaded model with its 8,192-token context (`tests/measure_memory.py`). The hidden MATLAB adds about 1 GB. **Tokens and cost** are on the Evaluation page and in `data/model_evaluation_summary.csv` (what the same tokens would cost on a paid API, from `models/api_prices.json`). After a price change, run `python tests/bench_live.py --rescore`.

Limits: one run per model per structure, so run-to-run variation is not measured; the answer check is lenient for topics and year comparisons (a topic word or the two years); the "wrong with no warning" count is small, so its differences are rough. Runs from October 2026 on the older 50-question key and code are in `evals/archive-2026-10/`.
