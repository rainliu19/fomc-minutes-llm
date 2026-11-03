function r = getOutlook(ctx, args)
%GETOUTLOOK Evidence on what the recent rate moves may mean ahead (fomc.data.outlookAssessment).
%   The Fed staff's forecast revisions, how far the rate changes have reached borrowing costs,
%   spending and prices, earlier runs, and what markets expect, as known on the anchor date or
%   on endDate if given (an earlier date shows the evidence as it stood then). The harness also
%   runs it before the model starts for questions about effects ahead (fomc.focus.outlookPrefetch),
%   so the model gets it even when it does not call the tool.

asOf = ctx.asOf;
raw = fomc.tools.getArg(args, "endDate", "");
if ~((ischar(raw) || isstring(raw)) && strlength(strtrim(string(raw))) == 0)
    d = fomc.util.parseDate(raw);
    if isnat(d)
        r = fomc.tools.fail("'endDate' must be a date written YYYY-MM-DD.");
        return
    end
    asOf = min(d, ctx.asOf);
end
% The rate data start in 1990, and a run needs a change before the date
if asOf < datetime(1991,1,1)
    r = fomc.tools.fail("'endDate' must be in 1991 or later: the rate data start in 1990.");
    return
end
r = fomc.data.outlookAssessment(ctx.D, asOf);
end
