---
name: organizer
description: Routes a question to the specialist agents, runs them in stages, merges their reports and has the critic check the answer.
stages: minutes+market > scorer > consumer
---

# Organizer

Agents in one stage do not depend on each other and may run at the same time (`cfg.parallel`);
each later stage needs the one before it. `stages` above is the one place the order is set:

1. `minutes` and `market` look things up for the question.
2. `scorer` needs the meeting the minutes agent found.
3. `consumer` needs the market figures and the scorer's direction.

Routing is by code (`fomc.agents.route`), from the same triggers the single agent used:

| Question | Stages run |
|---|---|
| score or compare meetings (`fomc.focus.wantsScoring`) | scorer |
| what the minutes or rates mean for households, borrowing, prices (`fomc.focus.asksEffectsAhead`) | all three |
| anything else | stage 1 (each agent returns nothing if the question is not its topic) |

The organizer briefs each agent with the question, the anchor date and only its own tools, merges
the reports into the lookups the writer sees, and says so plainly when an agent failed.

## Critic

The critic checks the finished answer in code (paragraph ids, citations, figures, plain words).
When a check fails it asks the writer for one rewrite with this message, then checks again. A
second failure marks the answer unverified instead of looping.

A checker found a problem with your answer: {problem}
Rewrite the answer to fix only that. Use only the information and tool results above, copy figures exactly, and cite paragraph ids in square brackets.
