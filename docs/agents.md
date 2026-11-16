# Agents

One writer model (Qwen3 4B, local) and four small specialist agents run by an organizer. The design is
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
others). The body is the agent's **system prompt** (phase 2 of the roadmap tunes these). `organizer.md` also holds
the `stages` line (the order) and the critic's rewrite message.

Each specialist is a sub-agent (`fomc.agents.subAgent`): its code finds the evidence, then its own short model loop
(the writer's `fomc.runTurn` in a fresh conversation, its prompt, only its tools, at most 3 rounds) writes a report.
Code checks the report (`fomc.guard.checkReport`: no paragraph id or number its sources lack); a bad report, a failed
model, analysis mode or no evidence falls back to the code's text, so facts are never lost. Each call is traced as
`agent_model {ms, fallback, reason}`.

| Stage | Agent | Code that finds the evidence | Model call |
|---|---|---|---|
| 1 | `minutes` | Rain's lookup, `+agents/minutesRetriever.m` (`lookup`) | summarizes the paragraphs with their ids |
| 1 | `market` | Alex's lookup, `+agents/marketData.m` (`lookup`) | phrases the dated figures |
| 2 | `scorer` | Aarya's scorer, `+agents/rubricScorer.m` (`scoreQuestion`); `fomc.data.minutesDirection` | score route: one call per rubric dimension (the skill's own loop); household route: none, a saved score is read |
| 3 | `consumer` | `+agents/consumerView.m` (the consumer-impact stub) | writes the household view from the market report and the direction |

Routes (by code, `fomc.agents.route`): a scoring question runs `scorer`; a question about what the minutes or
rates mean for households (`fomc.focus.asksEffectsAhead`) runs all three stages; anything else runs stage 1.
A specialist skips its model call when the evidence is shorter than `cfg.agentSummarizeOver` (default 1,500
characters; the lookups are 500 to 1,600): a summary of a decision card cost 8 to 20 s and dropped the paragraph ids
the writer cites, which sent it back for a second lookup. A report that cites none of the evidence's ids falls back
too. Set it to 0 to summarize everything.
Cost: a specialist adds one model call (a few seconds of reading plus a short report), and the writer then reads two
short reports instead of the raw lookups.

## Agent contract

`report = name(ctx, brief)`. `brief`: `question`, `isAnalysis`, `route`, `followsRatePath`, `reports` (the
earlier agents' reports by name), `session` (scorer, score route only). Build the report with
`fomc.agents.report(name, text=..., ids=..., calls=..., meetingDate=..., direction=..., structured=...)`.

Rules: use only your tools, through `fomc.tools.dispatch` (dates and the trace come with it); date every figure;
cite only ids a tool returned; start no process and load no model; on a failure return `ok=false` with `error`
(or throw: the organizer turns it into the same report). The writer is told the part is missing.
Whatever you return passes the date gate (nothing after the anchor).

## Transparency

Trace events: `route`, `stage`, `handoff`, `handback`, `critic`, `parallel_off`; every event inside an agent has
`agent`. The page shows them live and tags each tool with its agent.
