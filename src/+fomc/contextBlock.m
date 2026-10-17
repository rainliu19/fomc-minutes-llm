function t = contextBlock(ctx, brief)
%CONTEXTBLOCK Anchor date and data snapshot, put in front of a session's first question
%   (fomc.runTurn), not in the system prompt, so the system prompt stays reusable.
%   t = fomc.contextBlock(ctx, brief)

anchor = fomc.util.fmtDate(ctx.asOf);
t = strjoin([
    "ANCHOR DATE: " + anchor + ". Treat it as today."
    "DATA AS KNOWN ON " + anchor + " (observation dates in brackets):"
    brief
    ], newline);
end
