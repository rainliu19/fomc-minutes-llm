function r = assessEconomy(ctx, args)
%ASSESSECONOMY The economy against the Fed's goals and what the latest minutes say next (fomc.data.economyAssessment).
%   Inflation, unemployment, jobs and growth against the goals, two policy rules against the
%   target range, what Treasury yields suggest markets expect, and which way the latest
%   minutes point for future meetings (the AI's saved score, else word rules) with the staff
%   forecast, as known on the anchor date or on
%   endDate if given (an earlier date shows it as it stood then). The harness also runs it
%   before the model starts for questions about where policy is going (fomc.focus.economyPrefetch),
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
% The rate data start in 1990
if asOf < datetime(1991,1,1)
    r = fomc.tools.fail("'endDate' must be in 1991 or later: the rate data start in 1990.");
    return
end
r = fomc.data.economyAssessment(ctx.D, asOf);
end
