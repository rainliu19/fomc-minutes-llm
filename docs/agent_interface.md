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

Each question gets a default span of minutes: the last 3 years before the anchor, the 3 years ending in a year the question names, or the whole span if it names several. `searchMinutes` and `listMeetings` use it unless the model passes dates, and a note under the question lists the meetings in it. It is a relevance default, not a limit; the anchor rule always applies. `fromQuestion` says whether it came from years the question named. See `cfg.focusYears` and `fomc.focus.window`.

## Tools

| Tool | Purpose |
|------|---------|
| `getDecision` | What was decided at a meeting: raise, cut or hold, target range, vote counts, dissent. Read from the text by code (`fomc.data.decisionCards`) and checked against the actual rate changes for all 150 meetings. |
| `getPolicyPath` | How the rate target moved over several meetings (the latest 8 by default, or `startDate`/`endDate`): current range, last change and whether it reversed direction, runs of increases or cuts, holds, net change, and which way dissenters wanted the rate to go. See below. |
| `searchMinutes` | Phrase search over released paragraphs; each hit has an id |
| `readMinutes` | Paragraphs of one section, a page at a time; each has an id |
| `listMeetings` | Released meetings and their release dates |
| `getSeries` | History of up to 5 series as known at the anchor |
| `describeSeries` | What a series is and when each value becomes public |
| `scoreConsumerImpact` | Calls the rubric scorer (a stub) |

`getSnapshot` is run by the harness, not offered to the model: it puts the key series in the first message.

The harness also looks things up before the model starts, because a small model skips tools or wrongly says data is missing: the decision card or best passages for minutes questions (`fomc.focus.prefetch`), the latest figures (with the values 3 and 12 months earlier) for any data topic in the question (`fomc.focus.dataPrefetch`, topics from `fomc.focus.dataTopics`, at most 6 series), and the `getPolicyPath` summary for questions about how rates moved (`fomc.focus.pathPrefetch`: a rate word plus a change-over-time word such as "changed", "since" or "between", or two years named). Everything is read as known on the anchor date, and the answer is cleaned into plain words by `fomc.guard.plainEnglish`.

Paragraph ids look like `2020-03-15/policyAction/12`. The model cites them in brackets; `fomc.guard.citations` turns each into the exact paragraph and marks it verified only if its minutes were public at the anchor and a tool returned that id this session.

### `getPolicyPath`

Questions about the path of rates span many meetings, which a small model cannot look up one `getDecision` call at a time or add up reliably (in the 50-question evaluation, the 2015-to-2018 rate question was answered with the 2017 range for 2015). The tool does it in code and returns a summary sentence plus the facts behind it:

- **Levels and changes** come from the rate data (`fomc.data.ratePath`: `DFEDTAR` until December 2008, then `DFEDTARU`/`DFEDTARL`), as known on the anchor date. This includes the three changes made between scheduled meetings (2008-01-22, 2008-10-08, 2020-03-04), which no decision card has. Changes before 2008 have no meeting in the data, so they are reported by date only. Changes are measured on the top of the range.
- **Runs** are consecutive changes in one direction over the whole history: the current run, and the one before it when the last change reversed direction ("the first increase since 2023-07-26").
- **Holds** count meetings with released minutes and no change.
- **Dissents** (`fomc.data.dissentDirections`) compare the rate each dissenter preferred with the decision: `higher`, `lower`, or `other` (statement wording, asset purchases, or a preference that cannot be read). So a dissenter who wanted a 1/4 point cut when the Committee cut by 1/2 counts as `higher`. It reads the vote line and the paragraphs after it, the same ones as the decision card.
- A change whose minutes were not public yet is listed, since the rate data already shows it, and marked `minutesPublic: false`; its dissents are left out.
- **Citations** sit inside the summary, after each fact from the minutes (`… at the meeting ending 2026-09-16 [2026-09-16/policyAction/1]`), so a model that copies the summary copies them too; a run of holds cites the latest one. Changes between meetings and minutes not out yet have no paragraph, so no id.
- **High effort:** the path states the target on every day it covers, so `fomc.guard.checkGrounding` accepts a `DFEDTAR`, `DFEDTARU` or `DFEDTARL` figure for any of those days (checked against the rate data). Without this, a correct rate figure taken from the path failed the analysis check.
- **Span:** the latest 8 meetings (about a year) unless the model passes dates. Models copy the focus window from the question's note into any tool with dates; when the question named no year (the window's `fromQuestion` is false), that window is just "the last 3 years", so the tool treats those exact dates as no dates. The harness's own lookup passes `datesFromQuestion: true` (not offered to the model) so its dates are kept.
- **Run before the model starts** for questions about how rates moved (`fomc.focus.pathPrefetch`), with the span from the question: "since 2022" (to the anchor date), the years named (one year is that calendar year), "the last three years", "this year", or else the latest 8 meetings. The years named are read as one range (a decade such as "the 2010s" is its ten years; "since" runs to the anchor date) and trimmed to what the rate data covers, 1990 to the anchor year, not only years with minutes; a question whose years are all outside that gets nothing rather than a different span. In testing, Qwen3 4B answered "How did the Committee's view of interest rate policy change between 2015 and 2018?" from the passages and latest figures without calling the tool.
- **Follow-ups:** after an answer that used the rate path (`s.lastUsedRatePath`, set by `fomc.runTurn` when a turn finishes; a rolled-back turn leaves it as it was), a short follow-up that only names a period ("And what about in 2022?", "How about 2019?") gets it too, unless it names another topic (a data series, the minutes, what officials said). Without this, Qwen3 4B answered 12 of 12 such follow-ups wrongly (no data, or made-up rate changes); with it, all 12 got the rate path. A chat continued after a restart (`fomc.web.seed`) starts without it, so its first follow-up does not get the path.

`tests/testPolicyPath.m` and `tests/testPathPrefetch.m` check it on real data, including 17 dissents read by hand from the minutes.

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
| `prefetch` | `kind` (`decision`, `passages`, `data` or `path`), `meeting`, `ids`, `series`, or `startDate` and `endDate` |
| `guardrail_block` | `stage`, `tool`, `args`, `message` |
| `nudge`, `compact` | `round`, or `replaced` |
| `grounding_check` | `attempt`, `ok`, `failures`, `reply`, `ms`, `stats` |
| `round_cap`, `turn_error` | `rounds`, or `identifier` and `message` |
| `final_answer` | `text`, `nToolCalls`, `finished` |

## Limits

- The model is small. It handles lookups and short summaries; decisions and votes come from code, but check other claims against the cited paragraph.
- Only meetings after the model's training cutoff are clean, and the local model's cutoff is not yet verified.
- On an 8 GB Mac, close MATLAB and heavy apps before `uv run app.py`. See [MATLAB_GAPS.md](MATLAB_GAPS.md) for MATLAB limits found along the way.
