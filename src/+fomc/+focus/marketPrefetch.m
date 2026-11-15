function [text, recs] = marketPrefetch(ctx, question, followsRatePath)
%MARKETPREFETCH The market and economic data lookups: figures, rate path, economy, outlook.
%   [text, recs] = fomc.focus.marketPrefetch(ctx, question, followsRatePath)
%   The data part is fomc.focus.dataPrefetch (figures for series the question is about); the
%   path part is fomc.focus.pathPrefetch (how rates moved, for questions that ask, or for a
%   follow-up when followsRatePath is true); the economy part is fomc.focus.economyPrefetch
%   (the economy against the Fed's goals, for questions about where policy should go); the
%   outlook part is fomc.focus.outlookPrefetch (what the rate path may mean ahead, for
%   questions about its effects; left out when the economy part answers a question only about
%   the next decisions; with it, the data part leaves out the series it gives). All are added
%   to the question in that order: data, path, economy, outlook. This is the market and econ
%   data agent's lookup (fomc.agents.marketData); fomc.focus.prefetch adds the minutes part.

[pathText, pathRecs] = fomc.focus.pathPrefetch(ctx, question, followsRatePath);
[economyText, economyRecs] = fomc.focus.economyPrefetch(ctx, question);
% A question about the next decisions gets the economy part alone, unless it also names an effect on
% households: given both, Qwen3 4B blended them, answering "What do current economic conditions and
% the latest Fed minutes mean for the next FOMC meeting?" with earlier runs since 1990 and the
% 2-year yield in place of the next-meeting reading
outlookText = "";
outlookRecs = pathRecs([]);
if economyText == "" || ~onlyAboutDecisions(lower(string(question)))
    [outlookText, outlookRecs] = fomc.focus.outlookPrefetch(ctx, question);
end
% With the outlook evidence, the data part leaves out the series it already gives (and real GDP's
% level): given both, Qwen3 4B quoted spending as raw index levels (16530 to 16955) and called it faster
skip = strings(0, 1);
if outlookText ~= ""
    skip = ["DGS2"; "DGS10"; "MORTGAGE30US"; "BAA10Y"; "PCEC96"; "PCEPILFE"; "MICH"; "TREASURY_AVG_RATE"; "GDPC1"];
end
[text, recs] = fomc.focus.dataPrefetch(ctx, question, skip);
[text, recs] = addLookup(text, recs, pathText, pathRecs);
[text, recs] = addLookup(text, recs, economyText, economyRecs);
[text, recs] = addLookup(text, recs, outlookText, outlookRecs);
end

function tf = onlyAboutDecisions(q)
% The next or future Fed decisions, with no effect on borrowing, spending or prices named
decisions = "(next|future|upcoming|coming) (fomc |fed )?(meetings?|decisions?|moves?|steps?)|" + ...
    "(should|will|would|could|might) the (fed|fomc|committee) (raise|cut|lower|hike|hold|increase|tighten|ease|pause|keep|change|do)|" + ...
    "what (should|will|would|could|might) the (fed|fomc|committee) do";
effects = "mortgage|borrow\w*|loans?(?![a-z])|credit|debt|spending|consum\w*|households?|housing|" + ...
    "(?<![a-z])(house|homes?)(?![a-z])|inflation|(?<![a-z])prices|cost of living|wages?(?![a-z])|jobs?(?![a-z])|unemployment";
tf = ~isempty(regexp(q, decisions, "once")) && isempty(regexp(q, effects, "once"));
end

function [text, recs] = addLookup(text, recs, more, moreRecs)
% Append one lookup's text (on its own line) and its records, if it found anything
if more == ""
    return
end
if text == ""
    text = more;
else
    text = text + newline + more;
end
recs = [recs, moreRecs];
end
