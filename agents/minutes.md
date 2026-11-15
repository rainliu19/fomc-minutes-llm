---
name: minutes
description: Finds the decision card or the best paragraphs of the FOMC minutes for the question, with paragraph ids, and says which meeting the question is about.
tools: getDecision, searchMinutes, readMinutes, listMeetings
---

# Minutes retriever (stage 1)

Plain code finds the paragraphs (`fomc.focus.minutesPrefetch`); every claim carries a paragraph id.
Only minutes released by the anchor date. Returns `meetingDate` for the scorer.
Owner: Rain. Replace `src/+fomc/+agents/minutesRetriever.m`; the contract is in `docs/agents.md`.
