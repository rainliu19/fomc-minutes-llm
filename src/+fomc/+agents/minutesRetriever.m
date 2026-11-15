function r = minutesRetriever(ctx, brief)
%MINUTESRETRIEVER The minutes retriever (stage 1): the decision card or best paragraphs, with ids.
%   r = fomc.agents.minutesRetriever(ctx, brief)
%   Today it wraps the harness's own minutes lookup (fomc.focus.minutesPrefetch): code finds
%   the paragraphs; only minutes released by the anchor date. meetingDate is the meeting whose
%   decision card was found ("" if none), for the scorer. To replace this agent keep this
%   signature and fill the report (fomc.agents.report); the contract is in docs/agents.md.

[text, recs, meeting] = fomc.focus.minutesPrefetch(ctx, brief.question, brief.isAnalysis);
date = "";
if ~isnat(meeting)
    date = fomc.util.fmtDate(meeting);
end
r = fomc.agents.report("minutes", text=text, calls=recs, meetingDate=date);
end
