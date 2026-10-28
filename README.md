# FOMC Minutes Analyst

Ask questions about FOMC minutes and the economy around them. The agent answers using only what was public on a date you choose, cites the exact paragraphs it used, and runs a small model on your own machine: free, and nothing leaves it. The agent is MATLAB; Python only serves the web page.

## Run it

**One-time setup**

1. MATLAB R2026b with the "Large Language Models (LLMs) with MATLAB" add-on and the Text Analytics Toolbox.
2. [Ollama](https://ollama.com/download) and [uv](https://docs.astral.sh/uv/): `brew install ollama uv`
3. The default model (about 2.5 GB): `ollama pull qwen3:4b-instruct`. The other models on the page download the same way (see `models/`); the app builds each one the first time you pick it.

**Start the chat page**

```
uv run app.py
```

Open http://localhost:8787. It starts Ollama and MATLAB, checks memory first, and stops everything on Ctrl-C.

> On an 8 GB Mac, close MATLAB and other heavy apps first. The app will not start next to an open MATLAB unless you run `matlab.engine.shareEngine` in it, in which case it reuses that session.

**Without the browser:** in MATLAB, from the repo root, run `setup` then `fomc.chat()`.

**Test it:** `buildtool test` in MATLAB (about 2 minutes, no model needed) and `uv run python -m unittest tests/test_runtime.py`.

## What it does

- **Point in time.** Pick an anchor date. The agent sees only minutes released by then, and data as it was known then (revisions included). Guardrails refuse anything later.
- **Facts from code.** Decisions, votes and dissents are read from the minutes by pattern matching and checked against the real rate changes for all 150 meetings.
- **Checkable answers.** Answers cite paragraph ids. The page shows each exact paragraph and flags anything unverified.
- **Structured FOMC scoring.** Ask the agent to score a meeting's hawkish/dovish stance across seven dimensions. It uses a documented skill, returns schema-shaped JSON, and validates its scores and evidence.
- **Fast on a small model.** Typical answers take 10 to 25 seconds on an 8 GB M1.

## Score FOMC minutes

Ask in chat, for example:

```
Score the FOMC minutes for 2020-01-29.
Compare the score for 2020-01-29 with the latest meeting.
```

The scoring skill is stored in `skills/fomc-score/`: `SKILL.md` defines the workflow,
`rubric/` contains the shared scale and one rubric per dimension, `schema.json`
defines the JSON result, and `examples/exampleOutput.json` illustrates its shape.
The seven dimensions are rate path, inflation, labor market, economic activity,
financial conditions, balance sheet, and risk balance. Scores range from -1
(dovish) to +1 (hawkish), in quarter-point increments. A dimension that is not
discussed is represented with `status: "not_discussed"` and null score and
confidence values.

The agent resolves a requested meeting against its data and session anchor, and
uses only minutes released by the meeting's release date. The dedicated scorer
supplies the complete minutes, the skill instructions, all rubric files, and
the schema to the model. It then validates the result for schema shape, score
range and confidence, exact minutes quotes of at most 40 words, rate-path
consistency with the coded decision, and future dates in rationales. Failed
checks are sent back for correction for up to three total attempts. If
validation still fails, the result is marked unvalidated with its issues and
failed dimensions; do not rely on it as verified.

For comparisons, each score object independently matches `schema.json`. The
response carries those objects in `scores`, with per-meeting validation details
in a separate `validation` field and aggregate validation status. `latest`
means the most recent meeting whose minutes release date is on or before the
session anchor. A comparison needs at least two distinct meetings.

In MATLAB, the scorer can also be called directly:

```matlab
s = fomc.newSession(fomc.latestAnchor(), fomc.config());
result = fomc.skills.scoreMeeting(s, "2020-01-29"); % omit the date for latest
result.score       % schema-shaped score object
result.ok          % whether all checks passed
result.issues      % validation issues after the final attempt
result.attempts    % one to three model attempts
```

## What each folder is

| Folder / file | What it is |
|---|---|
| `app.py` | Starts the chat page. |
| `server/` | Python helpers behind `app.py`: start Ollama and MATLAB, check memory, save chats, shut everything down. |
| `static/` | The chat page (one HTML file): chat history on the left, model and effort pickers. |
| `src/` | The agent, written in MATLAB (`src/+fomc`, below). |
| `skills/` | Model-readable skill instructions, rubrics and output schemas. |
| `pipeline/` | MATLAB scripts that download and clean the data (FRED, Yahoo, Shiller, Treasury, the minutes). Run them only to refresh data. |
| `data/` | The collected data: CSVs, and one text file per set of minutes in `data/minutes/`. The agent reads these. |
| `tests/` | Automated checks: MATLAB tests (`buildtool test`), Python tests, and the live model evaluation (`bench_live.py`, `bench_baseline.py`, `make_key.py`, `measure_memory.py`, `export_evals.py`). |
| `evals/` | The 50-question answer key and each model's saved results. The Evaluation page (`/evaluation`) reads them. |
| `docs/` | Guides: agent interface, data, performance, MATLAB gaps. |
| `models/` | The local models you can pick on the page: one folder per model with its Ollama `Modelfile`, plus `models.json`, the list the page shows. |
| `logs/` | Created when you run the agent: one trace file per session, and your saved chats in `logs/chats/` (private to each browser). Not in git. |
| `setup.m`, `buildfile.m` | MATLAB helpers: add `src/` to the path; run the checks and tests (`buildtool`). |
| `pyproject.toml`, `uv.lock` | Python dependencies for the web page. |

**Inside `src/+fomc` (the agent)**

| Folder / file | What it is |
|---|---|
| `chat.m`, `runAgent.m`, `runTurn.m`, `effort.m` | Entry points, the main loop (ask the model, run its tools, repeat), and what Low, Medium and High effort change. |
| `+tools/` | The tools the model can call: decisions, the path of rates over several meetings, where policy may go next, what recent rate moves may mean ahead, search, read minutes, data series, and `readSkill` for loading skill instructions or references. |
| `+data/` | Loads the data, works out what was known on a given date, and reads each meeting's decision, the staff's forecast revisions and participants' views on future meetings. |
| `+focus/` | Picks which minutes a question is about and looks up the first facts before the model starts, including the path of rates, how the economy compares with the Fed's goals and what the latest minutes say about future meetings, and the evidence on what the rate path may mean ahead. |
| `+retrieve/` | Finds the paragraphs that best match a question. |
| `+guard/` | The checks: no future dates, real citations, correct figures. |
| `+analysis/` | The structured analysis (the High effort level). |
| `+skills/` | Discovers and loads skill instructions and runs the validated structured scoring workflow. |
| `+llm/` | Talks to the local model (and a fake model for tests). |
| `+history/` | Keeps the conversation short enough for the model. |
| `+trace/` | Writes the log of everything the agent did. |
| `+web/` | The functions the chat page calls (one turn, session store, continuing a saved chat). |
| `+leak/` | Labels meetings by whether the model may have seen them in training. |
| `+rubric/` | Placeholder for the consumer-impact score (Aarya). |
| `+util/` | Small helpers for dates and JSON. |

## Docs

- [docs/agent_interface.md](docs/agent_interface.md): tools, trace format, plugging in the scorer and consumer agent
- [docs/data.md](docs/data.md): series, caveats, rebuilding the data
- [docs/performance.md](docs/performance.md): measured speed, memory, and the model comparison (also at `/evaluation` and in `data/model_evaluation_*.csv`)
- [docs/MATLAB_GAPS.md](docs/MATLAB_GAPS.md): what MATLAB or its LLM add-on could not do

## Limits

- The model is small: decisions and votes come from code, but check other claims against the cited paragraph.
- The model may have seen what happened after past meetings; its training cutoff is not yet verified.
- Data belongs to its providers (FRED, Yahoo Finance, Shiller, US Treasury FiscalData, federalreserve.gov); see [docs/data.md](docs/data.md).
- License: not yet chosen.
