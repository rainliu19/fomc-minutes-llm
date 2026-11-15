# Agents

One writer model (Qwen3 4B, local) and four small specialist agents run by an organizer. The design is
`docs/subagent_architecture.html`; the patterns are the OpenAI Agents SDK's, in MATLAB.

## Modes

| `cfg.agents` | What runs |
|---|---|
| `"single"` (default) | `fomc.runTurn`: the harness does the lookups, one model call loop writes the answer. |
| `"multi"` (`FOMC_AGENTS=multi` for the web app) | `fomc.agents.run`: route, specialists in stages, the same writer loop on their reports, then the critic. |

`cfg.parallel` (default false) runs a stage's agents at the same time on thread workers (Parallel Computing
Toolbox). It is off when memory is short (`fomc.util.memoryShort`; a `parallel_off` event says so). One model
call runs at a time either way, so the gain is only the code lookups (about 0.7 s).
`cfg.criticRounds` (default 2) caps the critic: the draft is round 1, so one rewrite at most.

## The agents (`agents/*.md`, one file each)

Frontmatter: `name`, `description`, `tools` (the only tools the agent may call; `fomc.tools.dispatch` refuses
others). The body is the agent's instructions (phase 2 of the roadmap tunes these). `organizer.md` also holds
the `stages` line (the order) and the critic's rewrite message.

| Stage | Agent | Today it is | Owner replaces |
|---|---|---|---|
| 1 | `minutes` | `fomc.focus.minutesPrefetch` | `+agents/minutesRetriever.m` |
| 1 | `market` | `fomc.focus.marketPrefetch` | `+agents/marketData.m` |
| 2 | `scorer` | `fomc.skills.scoreRequest`; `fomc.data.minutesDirection` | `+agents/rubricScorer.m` |
| 3 | `consumer` | the `scoreConsumerImpact` stub | `+agents/consumerView.m` |

Routes (by code, `fomc.agents.route`): a scoring question runs `scorer`; a question about what the minutes or
rates mean for households (`fomc.focus.asksEffectsAhead`) runs all three stages; anything else runs stage 1.
Stage 1 sends the writer the same text as single mode.

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
`agent`. The page shows them live and tags each tool with its agent (`FOMC_AGENTS=multi`).
