---
name: scorer
description: Scores meetings on the rubric, or reads which way a meeting's minutes point for the rate from the saved scores.
tools: readSkill
---

# Rubric scorer (stage 2)

Score questions: `fomc.skills.scoreRequest`, one rubric dimension per model call, checked by the skill's
guards. Household questions: `fomc.data.minutesDirection`, which uses the saved scores and falls back to word
rules, for the meeting the minutes agent found (else the latest released). Returns `direction` and `meetingDate`.
Owner: Aarya. Replace `src/+fomc/+agents/rubricScorer.m`; the contract is in `docs/agents.md`.
