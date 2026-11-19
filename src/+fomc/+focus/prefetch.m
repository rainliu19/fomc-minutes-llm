function [text, recs] = prefetch(ctx, question, isAnalysis, followsRatePath)
%PREFETCH Stage-1 lookups as one text: the minutes agent's, then the market agent's.
%   [text, recs] = fomc.focus.prefetch(ctx, question, isAnalysis, followsRatePath)
%   For callers that do not go through the organizer (fomc.runTurn without Lookups, tests).
%   followsRatePath (default false) is true for a follow-up that only changes the period.
%   The organizer (fomc.agents.run) runs the same two agents one by one, with the trace.

if nargin < 4
    followsRatePath = false;
end
brief = struct("question", question, "isAnalysis", isAnalysis, "followsRatePath", followsRatePath);
m = fomc.agents.minutesRetriever(ctx, brief);
k = fomc.agents.marketData(ctx, brief);
text = m.text;
if k.text ~= ""
    if text ~= ""
        text = text + newline;
    end
    text = text + k.text;
end
recs = [m.calls, k.calls];
end
