# Agent interface

The agent is the MATLAB package `src/+fomc`. Run `setup` once per MATLAB session (from the repo root) to put `src/` on the path.

```matlab
setup
fomc.chat()                                       % chat anchored at the latest minutes release
fomc.chat(datetime(2020,4,8))                     % anchored at another date
[answer, structured, calls] = fomc.runAgent("What did the Committee decide?", datetime(2020,4,8));
[~, st] = fomc.runAgent("Why?", datetime(2020,4,8), Format="analysis", MeetingDate=datetime(2020,3,15));
```

The web page (`uv run app.py`) calls one function, `fomc.web.turn(sessionId, message, asOf, effort, model, tracePath, seedJson)`. Settings live in `fomc.config(Name=Value)`; pass the result as `Config=`.

## Effort levels

The local model has no thinking switch, so the page's Low / Medium / High control how much work the agent does (`fomc.effort`):

| Level | What changes | Typical time |
|-------|--------------|--------------|
| Low | short answer (`maxTokens` 450), 3 passages looked up first | 10 to 25 s |
| Medium | longer answer (700), 5 passages, up to 10 tool rounds | measured below |
| High | Medium plus the structured analysis with quote and figure checks | about 1 min |

## Saved chats

The page saves each chat as `logs/chats/<id>.json` (not in git) and lists them on the left, where they can be reopened, renamed and deleted. The agent's memory lives in MATLAB and is lost on restart, so the next message in an old chat replays its last 4 questions and answers into a new session (`fomc.web.seed`), with their verified paragraph ids.

Each browser gets a random owner id in a cookie (`fomc_owner`), and every chat is stamped with it. The server only lists, opens, renames, deletes or continues chats whose owner matches, so people sharing one running copy cannot see each other's chats. This is separation, not a login: anyone using the same browser profile shares its chats, and clearing cookies orphans them. Chats saved before owners existed go to the first browser that opens the page.

## Models

`models/models.json` lists the models the page offers; each has a folder with a `Modelfile`. To add one: `ollama pull <model>`, add `models/<id>/Modelfile` (copy an existing one and change the `FROM` line) and one line in `models.json`. Run `tests/bench_live.py <out.json> <id>` first: a model must call tools and copy figures reliably.

## Anchor date

Every session has an anchor date, `asOf`; nothing dated after it may reach the model. A meeting's anchor is its minutes release date, since the minutes are not public before then (`cfg.anchorType`).

- **Minutes** are visible only if released on or before the anchor.
- **Revised series** (17) use the real-time vintage history: the value as published by the anchor. A gap in the vintage history keeps the earlier value; an observation with nothing after its window is dropped. Series with no real-time values before their first vintage (e.g. `JTSJOL` before 2010-08) say so instead of guessing.
- **Other series** become visible after the publication lag in `data/series_availability.csv`. The lags are conservative assumptions, not all checked against release calendars.
- **Enforcement:** `fomc.guard.checkToolInput` refuses a call that names a later date; `fomc.guard.checkToolOutput` withholds a result containing one.

## Focus window

Each question gets a default span of minutes: the last 3 years before the anchor, the 3 years ending in a year the question names, or the whole span if it names several. `searchMinutes` and `listMeetings` use it unless the model passes dates, and a note under the question lists the meetings in it. It is a relevance default, not a limit; the anchor rule always applies. See `cfg.focusYears` and `fomc.focus.window`.

## Tools

| Tool | Purpose |
|------|---------|
| `getDecision` | What was decided at a meeting: raise, cut or hold, target range, vote counts, dissent. Read from the text by code (`fomc.data.decisionCards`) and checked against the actual rate changes for all 150 meetings. |
| `searchMinutes` | Phrase search over released paragraphs; each hit has an id |
| `readMinutes` | Paragraphs of one section, a page at a time; each has an id |
| `listMeetings` | Released meetings and their release dates |
| `getSeries` | History of up to 5 series as known at the anchor |
| `describeSeries` | What a series is and when each value becomes public |
| `scoreConsumerImpact` | Calls the rubric scorer (a stub) |
| `readSkill` | Loads a skill's `SKILL.md` or one of its referenced files from `skills/` |

`getSnapshot` is run by the harness, not offered to the model: it puts the key series in the first message.

The harness also looks things up before the model starts, because a small model skips tools or wrongly says data is missing: the decision card or best passages for minutes questions (`fomc.focus.prefetch`), and the latest figures (with the values 3 and 12 months earlier) for any data topic in the question (`fomc.focus.dataPrefetch`, topics from `fomc.focus.dataTopics`, at most 6 series). Everything is read as known on the anchor date, and the answer is cleaned into plain words by `fomc.guard.plainEnglish`.

Paragraph ids look like `2020-03-15/policyAction/12`. The model cites them in brackets; `fomc.guard.citations` turns each into the exact paragraph and marks it verified only if its minutes were public at the anchor and a tool returned that id this session.

## Skill scoring

Scoring requests in `fomc.runTurn` and the web chat are automatically routed to the `fomc-score` skill. The dedicated structured scoring entry point is also callable directly:

```matlab
s = fomc.newSession(fomc.latestAnchor(), fomc.config());
out = fomc.skills.scoreMeeting(s, "2020-01-29"); % omit the date for the latest released meeting
out.score       % the decoded score object
out.ok          % true only if all score checks pass
out.issues      % validation issues after the final attempt
out.attempts    % one to three model attempts
```

Each result is checked against the skill schema, score ranges, exact minutes quotes, the coded rate decision, and dates later than the meeting's release. Validation failures are sent back to the model for up to three total attempts. If all attempts fail, `out.ok` is false and `out.failedDimensions` identifies the dimensions with reported issues; do not treat that score as validated. This entry point scores one meeting per call. In chat, a comparison such as
`Compare 2020-01-29 with latest` scores the two distinct meetings independently.
The comparison response has a `scores` array whose entries each match
`skills/fomc-score/schema.json`, plus separate `validation` metadata for each
meeting and aggregate validation status. If `latest` resolves to the same date
as an explicitly supplied date, request another distinct meeting to compare.

## Analysis mode (High effort)

`Format="analysis"` adds one call after the tool loop that returns a short JSON analysis (`fomc.analysis.schema`): meetingDate, summary, policyStance, keyDrivers, evidence (claim plus paragraph id), dataCited, caveats. The model cites ids; the harness fills in the exact quotes. `fomc.guard.checkGrounding` checks ids and figures, and `policyStance` comes from the decision card. A failure goes back to the model once; a result that still fails has `groundingOk = false`.

## Speed

A local model reads about 140 tokens/s and writes about 10 to 17, so the code keeps both small: a fixed system prompt (so the model server can reuse its work), the anchor and snapshot in the first message, short tool pages, capped answers (`cfg.maxTokens`), and old tool results replaced by a stub past `cfg.compactAtTokens`. Every model call records Ollama's token counts and timings in the trace. `tests/testBudgets.m` enforces the sizes; measurements are in [performance.md](performance.md).

## Plugging in the rubric scorer (Aarya)

Replace the body of `src/+fomc/+rubric/scoreMinutes.m`, keeping the signature `s = fomc.rubric.scoreMinutes(minutesText, meetingDate)`:

| Field | Type | Meaning |
|-------|------|---------|
| `meetingDate` | string | `YYYY-MM-DD` |
| `criteria` | struct array | `title`, `reason`, `pass` (logical), one per rubric item |
| `aggregate` | double | 0 to 1 |
| `direction` | string | `positive`, `neutral`, `negative` or `unscored` |
| `stub` | logical | `false` once the real rubric is in |

- It sees the minutes text only, not the agent's analysis, so it cannot inherit its errors.
- It makes its own model call, using `cfg.scorerModel` (separate from `cfg.model`).
- Judging minutes is subjective, so keep the structure fixed and test reliability: run the same minutes N times and compare the spread of `aggregate` and the per-criterion agreement. Validity needs a hand-labeled gold set (about 20 meetings); no labels have been invented.
- `scoreConsumerImpact(meetingDate)` already calls this function, so the real scorer plugs in with no other change.

## Plugging in the consumer agent (Rain)

Build it the same way:

1. Call `fomc.rubric.scoreMinutes` for the meeting's score.
2. Call `fomc.runAgent(question, asOf)` for the base analysis, or keep a session from `fomc.newSession` and continue with `fomc.runTurn`.
3. Add tools to `src/+fomc/+tools/registry.m` (sentiment, debt and spending series are already in the data). Keep descriptions short: the model reads them on every call.

Use the same anchor date for all three parts.

## Trace

Each run writes `logs/trace-<runId>.jsonl` (web sessions: `logs/web-<session>.jsonl`), one event per line with `time`, `runId`, `asOf` and `type`. API keys are scrubbed; `logs/` is not tracked by git.

| `type` | Extra fields |
|--------|--------------|
| `session_start` | `model`, `backend`, `briefChars`, `maxToolRounds` |
| `user_message` | `text`, `focusStart`, `focusEnd`, `focusReason` |
| `model_response` | `round`, `content`, `nToolCalls`, `thinking`, `ms`, `stats` (promptTokens, outputTokens, promptMs, outputMs, loadMs) |
| `tool_call` | `name`, `args`, `result` (JSON text), `ok`, `ms` |
| `prefetch` | `kind` (`decision` or `passages`), `meeting` or `ids` |
| `guardrail_block` | `stage`, `tool`, `args`, `message` |
| `nudge`, `compact` | `round`, or `replaced` |
| `grounding_check` | `attempt`, `ok`, `failures`, `reply`, `ms`, `stats` |
| `round_cap`, `turn_error` | `rounds`, or `identifier` and `message` |
| `final_answer` | `text`, `nToolCalls`, `finished` |

## Limits

- The model is small. It handles lookups and short summaries; decisions and votes come from code, but check other claims against the cited paragraph.
- Only meetings after the model's training cutoff are clean, and the local model's cutoff is not yet verified.
- On an 8 GB Mac, close MATLAB and heavy apps before `uv run app.py`. See [MATLAB_GAPS.md](MATLAB_GAPS.md) for MATLAB limits found along the way.
