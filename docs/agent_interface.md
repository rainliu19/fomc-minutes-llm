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
| `assessEconomy` | Where policy may go next: the economy against the Fed's goals, policy rules, what Treasury yields suggest markets expect, and which way the latest minutes point for future meetings (the AI's saved score, else word rules) with the staff forecast. Optional `endDate` for an earlier view. See below. |
| `getOutlook` | Evidence on what recent rate moves may mean ahead: how the Fed staff revised its forecasts, how far the moves have reached borrowing costs, spending and prices, earlier runs, and what markets expect. Optional `endDate` for an earlier view. See below. |
| `getPolicyPath` | How the rate target moved over several meetings (the latest 8 by default, or `startDate`/`endDate`): current range, last change and whether it reversed direction, runs of increases or cuts, holds, net change, and which way dissenters wanted the rate to go. See below. |
| `searchMinutes` | Phrase search over released paragraphs; each hit has an id |
| `readMinutes` | Paragraphs of one section, a page at a time; each has an id |
| `listMeetings` | Released meetings and their release dates |
| `getSeries` | History of up to 5 series as known at the anchor |
| `describeSeries` | What a series is and when each value becomes public |
| `scoreConsumerImpact` | Calls the rubric scorer (a stub) |
| `readSkill` | Loads a skill's `SKILL.md` or one of its referenced files from `skills/` |

`getSnapshot` is run by the harness, not offered to the model: it puts the key series in the first message.

The harness also looks things up before the model starts, because a small model skips tools or wrongly says data is missing: the decision card or best passages for minutes questions (`fomc.focus.prefetch`), the latest figures (with the values 3 and 12 months earlier) for any data topic in the question (`fomc.focus.dataPrefetch`, topics from `fomc.focus.dataTopics`, at most 6 series), the `getPolicyPath` summary for questions about how rates moved (`fomc.focus.pathPrefetch`: a rate word plus a change-over-time word such as "changed", "since" or "between", or a span of years), the `assessEconomy` result for questions about where policy should go (`fomc.focus.economyPrefetch`; see below), and the `getOutlook` evidence for questions about what the rate path may mean ahead (`fomc.focus.outlookPrefetch`; see below). Everything is read as known on the anchor date, and the answer is cleaned into plain words by `fomc.guard.plainEnglish`. Some lookups run a tool through the normal tool path (`getDecision`, `getPolicyPath`, `assessEconomy`, `getOutlook`), so the turn records how many of its calls were lookups (`s.lastLookups`, set by `fomc.runTurn`), and the page lists those as "automatic lookup", apart from the tools the model chose.

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

### `assessEconomy` (a tool, and a lookup)

The model is offered `assessEconomy` (with an optional `endDate` for an earlier view), and for questions about where policy should go (the next or future decisions, whether policy is too tight or too loose, the Fed's goals, what markets expect, whether rates will go up or down), `fomc.focus.economyPrefetch` also runs it before the model starts, through the normal tool path. Both return what `fomc.data.economyAssessment` works out, everything as known on the anchor date (or `endDate`):

- **Core PCE inflation** (`PCEPILFE`, 12-month change) against the 2 percent goal, and whether it is rising, falling or steady against three months earlier (a 0.1 point band).
- **Unemployment** (`UNRATE`) against the CBO's estimate of its normal level (`NROU`) for the same quarter. `NROU` vintages start in February 2011, so earlier dates say it is not available.
- **Jobs and growth:** the average monthly change in payrolls (`PAYEMS`) over the latest three months, and real GDP growth at an annual rate (`A191RL1Q225SBEA`) in the latest quarter.
- **Output gap:** real GDP (`GDPC1`) against the CBO's estimate of potential (`GDPPOT`) for the latest quarter of GDP.
- **Policy rules**, as in the Fed's Monetary Policy Report: neutral real rate + inflation + 0.5 × (inflation − 2) + b × output gap, with b = 0.5 (Taylor 1993) or 1 (balanced approach), each with a neutral real rate of 0.5 and 2 percent, against the actual target range ("above", "below", "within" or "mixed"). A rule below zero is said to be impossible to follow. Before core PCE data (2000) there are no rules.
- **Markets:** the 6-month Treasury bill (`DGS6MO`) against the daily effective fed funds rate (`DFF`), for the next few meetings, and the 2-year yield (`DGS2`, the next two years) against the middle of the range. The bill counts as pointing to a move when it is more than 0.275 point away, the 2-year more than 0.25.
- **The latest minutes public on the anchor date:** which way they point for future meetings (`fomc.data.minutesDirection`, below): the AI's rate-path score where the minutes have been scored, with up to two of the sentences it cited, else the lean of participants' views read by `fomc.data.policyViews`, with up to two sentences quoted and cited (the most widely held view, and the leading view in another direction); how the staff revised its inflation and growth forecasts at that meeting (`fomc.data.forecastRevisions`, see `getOutlook` below); and, if a later meeting has been held, that its minutes are not public yet. Near zero (a range of 0 to 1/4 percent), a lean to cuts is said as more support for the economy by means other than the rate.
- **The next-meeting reading, first** (`fomc.data.nextMeetingReading`): the minutes give the direction of future moves and the 6-month bill against the effective rate (`fomc.data.billSignal`) the timing, put in one sentence ("participants expected further cuts over coming meetings, but the 6-month bill suggests markets do not expect one over the next few meetings"), followed by how often the next meeting raised, held or cut after earlier minutes with the same pattern, counting only meetings held by the anchor date. The reading says whether the direction is the AI's score or the word rules'. The policy rules and the 2-year yield come last, labelled as background on the next year or two, not the next meeting. The closing line tells the model to answer a question about the next meeting from this reading and say what it rests on.

Why: over the 149 pairs of minutes and the next meeting, as known the day each set of minutes came out, the next meeting held 77% of the time. The word rules' lean of the minutes alone was right about the next decision 69% of the time (82 of the 119 it makes a call on), worse than always guessing a hold, because participants often expect further moves and hold first; the 2-year yield was right 52%, and the policy rules 25%, since they say where the rate might be, not the next step. Of the 35 next meetings that moved, though, the minutes pointed the right way 29 times. So the reading gives both signals rather than a single call.

The market signal was chosen without looking at the meetings it is tested on. `DGS1MO`, `DGS6MO` and `DFF` were added from FRED's public CSV download for this (`pipeline/macroeconomic_data.m` lists them for a full pull). Five measures were compared: the 1-, 3- and 6-month bills against the effective rate, and the 3- and 6-month bills against the middle of the range, each with its cutoff fitted on the minutes released before the 87 meetings of 2008 to 2018 (13 moves). The 6-month bill against the effective rate fitted best (93%, cutoff 0.275) and was chosen. Tested on the 62 meetings from 2019 on (22 moves; a hold every time would be right 65%), it was right 84%, caught 14 moves and called 2 that did not happen. The earlier rule, the 3-month bill against the middle of the range beyond 0.15, was right 79% there, with 14 caught and 5 false, and read the August 2024 run-up to the September cut as no change (0.09 below the middle); the 6-month bill was 0.41 below the effective rate. The 6-month bill against the middle of the range did slightly better on the test (87%) but fitted the earlier meetings less well, so it was not chosen after the fact. The 1-month bill was the worst (60%, no moves caught): it often sat above the effective rate. Fed funds futures, the usual measure, are not on FRED.

**The minutes' direction: the AI's score, else the word rules** (`fomc.data.minutesDirection`). Where the minutes have a saved score (below, `pipeline/score_minutes.m`) that passed its checks, their direction is the AI's rate-path score: "up" at +0.5 or above, "down" at -0.5 or below (a hold at a range of 0 to 1/4 percent), else "hold". The reading says so ("The minutes' direction is the AI's reading: it scored their rate path +0.75, from -1 (dovish) to +1 (hawkish)"), and quotes the sentences the AI cited, which are cut to the skill's 40 words and marked "..." where a sentence goes on. Without a score, or with one that failed its checks, it is the word rules' lean, as before; the result keeps the word rules' lean and direction (`ruleLean`, `ruleWay`) either way as the baseline.

The cutoff was chosen on the minutes released before the 87 meetings of 2008 to 2018 (13 moves) and then tested, unchanged, on the 62 meetings from 2019 on (22 moves), with Qwen3 4B's scores of the rate path (each set of minutes scored once; 8 of the earlier minutes have no score that passed its checks and use the word rules). Each is right about the next decision when it names it (a move up or down, or a hold):

| | 2008 to 2018 (87) | 2019 on (62) |
|---|---|---|
| AI score, else word rules | 86% (9 moves caught, 8 false) | 81% (14 caught, 4 false) |
| Word rules | 71% (11 caught, 23 false) | 76% (18 caught, 11 false) |
| 6-month bill against the effective rate | 93% (8 caught, 1 false) | 84% (14 caught, 2 false) |
| A hold every time | 85% | 65% |

So the AI reads the minutes' direction better than the word rules, mostly by calling far fewer moves that did not happen, though it misses more of the moves that did (the July 2024 minutes, before the September cut, it scored 0.00: a hold; with that reading Qwen3 4B answered the eval case nextmove-02, "Is the Fed likely to cut rates at its next meeting?" in August 2024, with "No", where it had answered from the word rules' lean to cuts correctly). The bill is still the better guide to the very next meeting, which is why the reading takes the direction from the minutes and the timing from the bill. Combining the two in one call did not beat the bill on 2019 on: a move only when both point the same way was right 81% (11 caught, 1 false), and the bill, with the AI where the bill says hold, 84% (17 caught, 5 false). Two cautions: the model may know from its training what the Fed did next, which would flatter its scores of older minutes; and the skill's rate-path check makes the score of a meeting that raised at least +0.25 and of one that cut negative, so the score mixes the decision at the meeting with what participants expected next.

**Against a reading by hand.** Of the 22 meetings read by hand for the word rules (every 2022 meeting and every meeting since January 2025), 18 have one direction (the other four are "depends on the data" or "divided"). The AI agrees on 16; it read November 2022 (+0.25) as a hold where "ongoing increases" were expected, and June 2025 (+0.25) as a hold, and slightly hawkish, where most participants expected some reduction that year. The word rules match all 22, but they were written against these meetings.

**Run to run.** The model samples at temperature 0.2, so a score can differ when the minutes are scored again. 15 meetings scored three times (the saved score and two more) gave the same score every time for 9; the other 6 moved by 0.25, which changed the direction for 3 that sit at the cutoff (July 2019, November 2022, June 2026). The July 2024 hold was the same all three times. Scoring each set of minutes three times and taking the middle score would steady this, at three times the scoring time.

**Failed scores.** 8 of the 150 saved scores failed the skill's checks and use the word rules: four said "not discussed" while giving a score, one gave no quotes, and three (March, June and August 2012) gave a rationale that named 2014, which the check reads as a date after the release. Those minutes themselves gave "late 2014" as the date in the Committee's guidance, so that check needs to allow years the minutes themselves name.

`tests/testMinutesDirection.m` checks every saved score again against the skill's checks, that a score counts only once its minutes are public, the agreement with the reading by hand, the backtest counts above, the cutoff, the fallback to the word rules, and the memory guard.

`fomc.data.policyViews` reads Participants' Views and the Committee Policy Action sentence by sentence. A sentence counts only if it names the rate (target range, federal funds rate, policy rate, firming, accommodation), a move in it, and something ahead ("further", "another", "soon", "for some time", "patient", future or upcoming meetings); in a paragraph that opens on the outlook for policy, a judgment of what "would be appropriate" is enough. It skips the decision at this meeting, dissent paragraphs and named members, the quoted statement and directive, the statement's wording, the balance sheet and the projections. Each view gets who held it (all, almost all, most, many, several, a few, one, from the first quantifier; "most of these participants" counts as several at most), a direction (increases, cuts, hold, or slower increases or cuts; a doubted move such as "did not expect it would be appropriate to reduce ... until" reads as a hold), and whether it is conditional ("if inflation were to ...", "in such scenarios"; "if the economy evolves as expected" is their baseline, not a condition). The lean is the most widely held view that is not conditional; an opposite view held by many or more and nearly as widely makes it "divided", and views that are all conditional make it "depends on the data". It was written against, and matches, a reading by hand of 22 meetings (every 2022 meeting and every meeting since January 2025); it was tuned on those, so it is less reliable elsewhere, above all before about 2015, when the minutes put the policy discussion in other words and the rate was near zero for years. 19 of the 150 meetings give no lean: 11 from 2008 to 2014, December 2019, and 7 from September 2020 to June 2021, when the outlook was stated through the statement's guidance and asset purchases.

Its tool description cost about 300 characters (91 tokens), so the budgets in `tests/testBudgets.m` were raised again, to 4,400 characters of tool descriptions and 2,025 tokens for the first-turn prompt (it is about 1,998); the `readSkill` tool raised them to 4,800 and 2,375. Its figures carry their series, dates and values, so `fomc.guard.checkGrounding` accepts them in a High-effort answer, and the paragraph ids it quotes count as returned by a tool. `tests/testEconomy.m` checks it on real data, including October 2026 (the minutes lean toward another increase, payrolls up 51,000 a month), March 2022 (the rules far above a range of 0 to 1/4 percent), 2009 (rules below zero), October 2012 (near zero, with a later meeting whose minutes are not out), the 22 meetings read by hand, and every minutes release date.

### `getOutlook` (a tool, and a lookup)

The model is offered `getOutlook`, and for questions about what the Fed's moves mean ahead `fomc.focus.outlookPrefetch` also runs it before the model starts, through the normal tool path. Both return what `fomc.data.outlookAssessment` gathers. The lookup is the part that matters in practice: in testing, Qwen3 4B did not call the tool for any of three questions the lookup's wording missed ("where are things headed?", "is now a good time to buy a house?", "what did the 2022 increases do to mortgage rates?"), even with a line naming it in the system prompt, and answered all three wrongly (it said rates had been "held steady since 2025" and that the 2022 data were not available). So the trigger was widened to those phrasings and the prompt line was not kept. The trigger is an effect or future word ("mean for", "affect", "impact", "do to", "good time to", "outlook", "will ... slow") plus something the economy does (inflation, prices, mortgages, borrowing, debt, spending, a house, jobs, growth), or "where are things headed". A question that names only years before the anchor year gets the evidence as it stood at the end of the latest year named ("the 2022 increases" is read as of 2022-12-31).

No one can know these effects in advance, so it makes no forecast of its own; it collects three kinds of evidence, all as known on the anchor date, and the prefetch text tells the model to say what the evidence shows, never what will happen:

- **The Fed staff's forecast** (`fomc.data.forecastRevisions`): at each of the last 4 meetings with public minutes, whether the Staff Economic Outlook revised its inflation forecast and its forecast for growth and spending up, down or not at all against the previous meeting, and the risks it saw at the latest (upside, downside, balanced), each cited to its paragraph. A clause counts only if it compares with the previous forecast ("than the one prepared for the July meeting", "revised up", "relative to January"); the reasons after "reflecting" or "because" are dropped, so "revised down ... reflecting higher energy prices" reads as lower; "prepared by the staff for the November meeting" on its own only introduces the forecast; revisions to potential output, the natural rate or the output gap are capacity estimates and are skipped. The unemployment rate is left out: its wording ("a smaller decline") is too varied to read reliably. Of the 150 meetings, 29 have no inflation comparison the code can read and 27 none for growth (mostly 2008 to 2013 and 2020); risk readings are missing for about a third, also mostly before 2014.
- **How far the rate changes have reached so far**, one step at a time: market rates (`DGS2`, `DGS10`), borrowing costs (`MORTGAGE30US`, the Baa corporate spread `BAA10Y`), then spending and prices (real consumer spending growth `PCEC96`, core PCE inflation `PCEPILFE`, consumers' expected inflation `MICH`), each now, just before the first change of the current run of increases or cuts (from `fomc.data.ratePath`), and six months before it, since markets move ahead of the Fed. A monthly reading whose month ended before the first change cannot show its effect, and the summary says so ("Too early to show the increase").
- **Earlier runs in the same direction since 1990** (the first run in the data is left out because it began before the data): a year after the first change, how many saw the mortgage rate higher, real spending growth slower and core inflation lower, with the median change; and core inflation two years after. Real spending (`PCEC96`) starts in 2007, so only the 2015 and 2022 runs of increases have it.
- **Federal debt:** the average interest rate the Treasury pays on its marketable debt (`TREASURY_AVG_RATE`, from Treasury FiscalData, monthly from 2001), at the same three points, and in the earlier runs since 2001. New borrowing pays current Treasury yields, so the average moves toward them as maturing debt is refinanced: it went from 1.44% before the 2022 increases to 2.69% by May 2023.
- **Markets:** the 2-year yield against the middle of the range, as in `assessEconomy`.

Total interest payments on federal debt and credit card and car loan rates are not in the data. A question about credit card or car loan rates is told to say so first; one about federal debt is told to say that total interest payments are missing and to answer from the Treasury's average rate and Treasury yields (Qwen3 4B had answered "cannot be determined"). The lookup's text ends by asking for the staff forecast's ids ("such as [2026-09-16/staffOutlook/1]"), for readings from before the first change to be called too early to show it, and for the earlier runs' counts as written: without this, Qwen3 4B answered a mortgage and spending question citing nothing, called August spending "resilient" when the evidence said it came before the increase, and called a slowdown seen in 2 of 2 runs "modest". A question about the next decisions that names no effect on households (mortgages, borrowing, spending, prices, jobs) gets the `assessEconomy` lookup alone: given both, Qwen3 4B answered "What do current economic conditions and the latest Fed minutes mean for the next FOMC meeting?" with the earlier runs since 1990 and the 2-year yield in place of the next-meeting reading. The tool description cost about 275 characters (83 tokens), so the budgets in `tests/testBudgets.m` were raised to 4,050 characters of tool descriptions and 1,925 tokens for the first-turn prompt (it is about 1,907). Its figures carry series, dates and values for `fomc.guard.checkGrounding`, and its paragraph ids count as returned by a tool. `tests/testOutlook.m` checks the tool (including `endDate` before the anchor, after it, and before the rate data), and the forecast reader against 20 meetings read by hand (every 2022 meeting and the latest twelve), the evidence in October 2026 (rates up, spending not yet measurable) and October 2022 (spending growth down from 6.7% to 1.8%), and every minutes release date.

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

### Scoring one dimension per call (`fomc.skills.scoreByDimension`)

A variant of `fomc.skills.scoreMeeting` for the local models, kept in its own file so Aarya's scorer, which the chat's scoring requests use, is unchanged. It uses the skill as written (`skills/fomc-score`: the scale, the rules in `SKILL.md`, the rubrics, the dimension schema) and the same checks, and returns the same score object with `out.calls` (model calls) and `out.passages` (per dimension, the paragraph ids the model read); `out.attempts` is the most attempts any dimension needed. The tools built on the scores call this one.

```matlab
out = fomc.skills.scoreByDimension(s, "2026-09-16");
```

**One dimension per call.** The skill's instructions, all seven rubrics and a full set of minutes come to about 17,000 tokens (minutes are about 46,000 characters at the median), and the local models read 8,192 (`num_ctx` in `models/*/Modelfile`); Ollama cuts a longer prompt without an error. So `fomc.skills.scoreByDimension` gives each dimension its own call: the shared scale (`rubric/00_scale.md`), the "Rules that prevent common mistakes" section of `SKILL.md`, that dimension's rubric, and the paragraphs of the minutes about it. Code ranks the paragraphs by the dimension's words (Participants' Views counting double, and the Committee Policy Action for the rate path and balance sheet), keeps the best that fit, and puts them back in the minutes' order, each after its paragraph id. A dimension no paragraph mentions is `not_discussed` without a call. The model answers with one dimension of `schema.json`; code assembles the seven and runs the checks below, counting only a dimension's own issues for its retries. A dimension with no valid answer after three attempts is reported in `out.issues`, not left as `not_discussed`.

**Quotes.** The model's quotes are matched to the sentence of its passages that shares the most words (twice the shared count over both lengths, at least 0.6) and replaced by that sentence, cut to 40 words, with its paragraph id. Asked to copy quotes exactly, Qwen3 4B reworded them in 4 of the 7 dimensions of the September 2026 minutes and gave the same text on each retry. Asked instead to name numbered sentences, it chose poorly (a labor market sentence for inflation) and once wrote a sentence number without end until the output limit. With matching, the September 2026 minutes scored in 8 calls (2 minutes 41 seconds), every check passing, each prompt 3,000 to 4,500 tokens: rate path +0.75, inflation +0.75, labor market +0.5, economic activity +0.75, financial conditions +0.25, risk balance +0.75, balance sheet not discussed.

`tests/testScoreByDimension.m` checks it with a stand-in model (`tests/EchoScoreModel.m`) on the synthetic minutes, and that every prompt for the September 2026 minutes fits the window.

### Saved scores (`pipeline/score_minutes.m`, `fomc.skills.scoreCache`)

The tools do not call the model to score minutes while answering. `pipeline/score_minutes.m` scores the rate path of every released set of minutes that has no saved score, with `fomc.skills.scoreByDimension(s, meeting, Dimensions="rate_path")`, and `fomc.skills.scoreCache("write", model, meeting, out)` saves each to `data/scores/<model>/<meeting>.json` (meeting, model, date scored, `ok`, issues, the dimensions scored, the score object, the paragraphs read); scoring more dimensions of a meeting later adds them to the same file. Rerun it after new minutes come out: only the new meetings are scored, about 25 seconds each. It stops before a meeting when memory is short (critical pressure, over 3.6 GB of swap with pressure above normal, or over 6 GB of swap); on an 8 GB Mac run it in chunks (`maxMeetings = 8; run("pipeline/score_minutes.m")`) and restart MATLAB and Ollama between them. `fomc.skills.scoreCache("read", ...)` and `("list", ...)` read them back; the score of a meeting counts only once its minutes are public on the anchor date, like everything else.

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
| `prefetch` | `kind` (`decision`, `passages`, `data`, `path` or `economy`), `meeting`, `ids`, `series`, or `startDate` and `endDate` |
| `guardrail_block` | `stage`, `tool`, `args`, `message` |
| `nudge`, `compact` | `round`, or `replaced` |
| `grounding_check` | `attempt`, `ok`, `failures`, `reply`, `ms`, `stats` |
| `round_cap`, `turn_error` | `rounds`, or `identifier` and `message` |
| `final_answer` | `text`, `nToolCalls`, `finished` |

## Limits

- The model is small. It handles lookups and short summaries; decisions and votes come from code, but check other claims against the cited paragraph.
- Only meetings after the model's training cutoff are clean, and the local model's cutoff is not yet verified.
- On an 8 GB Mac, close MATLAB and heavy apps before `uv run app.py`. See [MATLAB_GAPS.md](MATLAB_GAPS.md) for MATLAB limits found along the way.
