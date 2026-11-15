function [text, recs] = prefetch(ctx, question, isAnalysis, followsRatePath)
%PREFETCH Lookups the harness does before the model starts: minutes, data, rate path, economy, outlook.
%   [text, recs] = fomc.focus.prefetch(ctx, question, isAnalysis, followsRatePath)
%   The minutes part is fomc.focus.minutesPrefetch and the market part is
%   fomc.focus.marketPrefetch (data, rate path, economy, outlook); followsRatePath (default
%   false) is true for a follow-up that only changes the period. Both are added to the
%   question, minutes first. The multi-agent organizer runs the two parts as two agents
%   (fomc.agents.run); this is the single-agent version.

if nargin < 4
    followsRatePath = false;
end
[text, recs] = fomc.focus.minutesPrefetch(ctx, question, isAnalysis);
[marketText, marketRecs] = fomc.focus.marketPrefetch(ctx, question, followsRatePath);
if marketText ~= ""
    if text ~= ""
        text = text + newline;
    end
    text = text + marketText;
    recs = [recs, marketRecs];
end
end
