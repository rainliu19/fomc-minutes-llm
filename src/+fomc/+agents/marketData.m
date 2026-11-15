function r = marketData(ctx, brief)
%MARKETDATA The market and econ data agent (stage 1): dated figures, rate path, economy, outlook.
%   r = fomc.agents.marketData(ctx, brief)
%   Code only (fomc.focus.marketPrefetch, which runs the tools through fomc.tools.dispatch, so
%   the date gates and the trace apply): MATLAB does the arithmetic and the writer only phrases
%   the result. Each figure names its series and the date it was known. A question that is not
%   about numbers gets an empty report. Contract: docs/agents.md.

[text, recs] = fomc.focus.marketPrefetch(ctx, brief.question, brief.followsRatePath);
r = fomc.agents.report("market", text=text, calls=recs);
end
