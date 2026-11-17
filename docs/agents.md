# Agents

One writer model (IBM Granite 3.3 2B by default, local; the model list on the page changes it) and four small specialist agents run by an organizer. The design is
`docs/subagent_architecture.html`; the patterns are the OpenAI Agents SDK's, in MATLAB.

## How a turn runs

Every question goes through `fomc.agents.run` (the web app, `fomc.runAgent`, `fomc.chat`): route, specialists in
stages, the writer loop (`fomc.runTurn`) on their reports, then the critic.

`cfg.parallel` (default false) runs a stage's agents at the same time on thread workers (Parallel Computing
Toolbox, and only if memory allows: `fomc.util.memoryShort`; a `parallel_off` event says so). It is off because
the stage-1 lookups take about 0.1 s warm, less than the hand-off to a worker costs, and the one local model
answers one call at a time either way. Turn it on when a specialist starts doing slow work.
`cfg.criticRounds` (default 2) caps the critic: the draft is round 1, so one rewrite at most.

## The agents (`agents/*.md`, one file each)

Frontmatter: `name`, `description`, `tools` (the only tools the agent may call; `fomc.tools.dispatch` refuses
others), optional `summarizeOver`. The body is the agent's **system prompt**, a short role; topic pages in
`agents/<name>/<topic>.md` add one focused rule set (the minutes agent has `decision`, `views`, `passages`: the
lookup picks the page). They are meant to be tuned. `organizer.md` also holds the `stages` line (the order) and
the critic's rewrite message.

Each specialist is a sub-agent (`fomc.agents.subAgent`): its code finds the evidence, then its own short model loop
(the writer's `fomc.runTurn` in a fresh conversation, its prompt, only its tools, at most 3 rounds) writes a report.
Code checks the report (`fomc.guard.checkReport`: no paragraph id or number its sources lack); a bad report, a failed
model, analysis mode or no evidence falls back to the code's text, so facts are never lost. Each call is traced as
`agent_model {ms, fallback, reason}`.

| Stage | Agent | Code that finds the evidence | Model call |
|---|---|---|---|
| 1 | `minutes` | Rain's lookup, `+agents/minutesRetriever.m` (`lookup`): decision card, participants' views for next-move questions, or best paragraphs | summarizes the paragraphs with their ids |
| 1 | `market` | Alex's lookup, `+agents/marketData.m` (`lookup`) | none by default (`summarizeOver: 6000`): its text already tells the writer what to cite |
| 2 | `scorer` | Aarya's scorer, `+agents/rubricScorer.m` (`scoreQuestion`); `fomc.data.minutesDirection` | score route: one call per rubric dimension (the skill's own loop); household route: none, a saved score is read |
| 3 | `consumer` | `+agents/consumerView.m` (the consumer-impact stub): the direction and the tool's note | none while the rubric is a stub |

Routes (by code, `fomc.agents.route`): a scoring question runs `scorer`; a question about what the minutes or
rates mean for households (`fomc.focus.asksEffectsAhead`) runs all three stages; anything else runs stage 1.
A specialist skips its model call when its evidence is short (`cfg.agentSummarizeOver`; config.m says why), and its
report falls back to the evidence if it cites none of the evidence's ids. Set the limit to 0 to summarize everything.
The market agent's model call is off because summarizing its text dropped the writer's instructions in it ("cite the
staff forecast with its ids", "do not answer yes or no"): the writer then cited nothing or answered yes. The organizer
ends the lookups with one line naming the reports' first ids to cite. The critic also asks for one rewrite when a
next-move answer says yes or no or what the Fed should do, or an effects answer cites nothing although ids were given.

## Measured (qwen3 4B, 57 cases, one run each)

| | One agent (main) | Team |
|---|---|---|
| Correct | 48/53 (90.6%) | 53/53 (100%, 95% CI 93.2 to 100) |
| Citations verified | 77/81 | 113/113 |
| Silent errors, warnings | 5, 1 | 0, 0 |
| Median / p90 seconds | 18.0 / 28.9 | 15.5 / 36.1 |

Three of the five cases won are lookup fixes (rate-target questions that name a meeting) that the one agent could use
too; the rest come from the guard and the critic. Household questions are slower (about 37 s against 29 s). Small
sample, one run: read the gain as "no worse, probably better", not as proof.

## Agent contract

`report = name(ctx, brief)`. `brief`: `question`, `isAnalysis`, `route`, `followsRatePath`, `reports` (the
earlier agents' reports by name), `session` (scorer, score route only). Build the report with
`fomc.agents.report(name, text=..., ids=..., calls=..., meetingDate=..., direction=..., structured=...)`.

Rules: use only your tools, through `fomc.tools.dispatch` (dates and the trace come with it); date every figure;
cite only ids a tool returned; start no process and load no model; on a failure return `ok=false` with `error`
(or throw: the organizer turns it into the same report). The writer is told the part is missing.
Whatever you return passes the date gate (nothing after the anchor).

## Transparency

The page's side panel ("How the agents worked", `static/agents-panel.js`, after the course demo's context panel) draws
the trace as a timeline: a column per agent (organizer, minutes, market, scorer, consumer, writer, critic), a row per
step. It fills while the model works and reopens per answer ("See how the agents worked"; the reply carries the trace's
line range, saved with the chat).

Trace events: `route` (with the question), `stage`, `handoff` (`reads`: whose reports the agent is briefed with),
`handback` (the report), `agent_model` (`skipped` and why, or ms and fallback), `critic`, `parallel_off`, and per model
call `message` (what the model was sent: role, text, `from` = the agents whose output it carries) and one
`model_response` (`fomc.trace.llmCall` wraps all five model call sites, so every call is counted once, tokens included).
Every event inside an agent has `agent`; the writer's are "writer", one-agent mode's are "agent". Strings in the log
are capped at 20,000 characters.

## Switch and default model

"Agents: Team | One" next to Effort (`agents` in `/chat`, default team; locked with the model once a chat starts, saved
with it). One runs `fomc.runTurn` alone with the harness's own lookups and no critic, so the switch compares the
architecture only. The default model is the first of `models/models.json`: IBM Granite 3.3 2B (`fast`), the best
accuracy for its memory. The rubric scorer stays on `cfg.scorerModel` (qwen3), the model its saved scores
(`data/scores/`) were made and validated with.

The "Measured" table above is from qwen3 and mixes two machines (the one-agent file was run on another Mac), so its
seconds do not compare; the evaluations are being rerun on one machine for all models.

## Lookahead bias

The data are cut off at the as-of date (the date gate above), but a model may have been trained on later events.
`agents/shared/asof.md` holds the point-in-time rules. It is read by `fomc.asOfRules` into the writer's system
prompt (rule 8), into every specialist's prompt (`fomc.agents.subAgent`) and, through `fomc.anchorLine`, into the
date line of each first message. It is not under `agents/*.md` or `agents/<name>/`, so the catalog does not take it
for an agent. `tests/bench_lookahead.py` measures the error rate: `--open` is the baseline with no guards, `--team --tag v0` the
guards (the app in main), `--team --tag v1` v1. v1 is v0 plus the short rules above plus a date check in code:
`fomc.focus.periodsNamed` finds the periods a question names (months in words, quarters, parts of a year,
"3 months from now"), and when every one is after what is known (`fomc.focus.dataPrefetch`: after the newest value of
the series the question is about; `minutesRetriever`: a meeting whose minutes are not public) the harness returns a
`prefetchNotice` and `fomc.runTurn` answers with it, no model call. A period any series shows, a question about
forecasts, or no period named goes to the model. Limits: a month with no year, a numeric month, a season, a bare year and
"the next meeting" are not read.

Question sets (`--key fresh|unseen` selects a set; runs go in that set's folder): `evals/lookahead/key.json` (114,
three fixed wordings), `fresh/` (68, new wordings, used to broaden the check) and `unseen/` (74, written after the
check was broadened: the headline). When v1 changes after a set's errors were seen, that set becomes a development set;
write a new unseen set with a new seed (`tests/make_lookahead_unseen.py` is the pattern). The Evaluation page's
Lookahead bias tab shows baseline, v0 and v1 on the unseen set and the other sets beside it. The version history
(prompt-only v1, the month-names-only date check) and its numbers are in `evals/lookahead/archive/README.md`.
