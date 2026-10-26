function [text, recs] = pathPrefetch(ctx, question)
%PATHPREFETCH The path of the rate target, looked up before the model starts.
%   [text, recs] = fomc.focus.pathPrefetch(ctx, question)
%   A small model often answers a question about rates over time from the latest figures
%   alone and skips getPolicyPath. So when the wording asks how rates moved (a rate word and
%   a change-over-time word, or a rate word and two years), the harness runs getPolicyPath
%   itself and adds its summary to the question. The span: "since 2022" (to the anchor date),
%   the years the question names (one year is that calendar year), or "the last N
%   years/months", else the tool's default of the latest 8 meetings. Other questions get
%   nothing. No model.

text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch
    return
end

% Other rates ("the unemployment rate rose", "the rate of inflation", "long-term interest
% rates") and other easing ("easing of supply chain pressures") do not count
q = lower(string(question));
q = regexprep(q, "(unemployment|inflation|mortgage|exchange|participation|savings?|jobless|vacancy|" + ...
    "default|delinquency|quits?|layoff|tax|growth|prime|birth|death)\s+rates?", " ");
q = regexprep(q, "(long-term|longer-term|long|real|market|bond|treasury|\d+-year)\s+(interest\s+)?rates?", " ");
q = regexprep(q, "rates? of (inflation|unemployment|growth|interest on reserves)", " ");
rateWords = "fed funds|federal funds|policy rate|interest rate|target range|(?<![a-z])rates?(?![a-z])|" + ...
    "(?<![a-z])hik(e|es|ed|ing)(?![a-z])|(policy|monetary) (easing|tightening)|" + ...
    "(easing|tightening|loosening) (cycle|of (monetary )?policy)|tighten(ed|ing)? (monetary )?policy|monetary policy";
changeWords = "chang\w*|over the (past|last)|in the (past|last)|since|between|trend|cycle|path|trajectory|" + ...
    "history|evolv\w*|moved?|movement|so far|lately|recently|how (many|much|often)|sequence|series of|" + ...
    "(?<![a-z])rise|(?<![a-z])rose|risen|fall|fell|fallen|climb\w*|declin\w*|went (up|down)|gone (up|down)";
years = unique(double(string(regexp(q, "(?<!\d)(20[0-2]\d)(?!\d)", "match"))));
isRate = ~isempty(regexp(q, rateWords, "once"));
isChange = ~isempty(regexp(q, changeWords, "once")) || numel(years) >= 2;
if ~isRate || ~isChange
    return
end

% The span: "since 2022" (to the anchor date), the years named, or "the last N years/months",
% else the tool's default
args = struct();
years = years(years >= 2008 & years <= year(ctx.asOf));
words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];
back = regexp(q, "(?:past|last)\s+(\d+|" + strjoin(words, "|") + ")\s+(year|month)s?", "tokens", "once");
since = regexp(q, "since\s+(20[0-2]\d)(?!\d)", "tokens", "once");
if isscalar(years) && ~isempty(since)
    args.startDate = char(fomc.util.fmtDate(datetime(years, 1, 1)));
elseif ~isempty(years)
    args.startDate = char(fomc.util.fmtDate(datetime(min(years), 1, 1)));
    args.endDate = char(fomc.util.fmtDate(min(ctx.asOf, datetime(max(years), 12, 31))));
elseif ~isempty(back)
    n = str2double(back{1});
    if isnan(n)
        n = find(words == back{1});
    end
    if back{2} == "year"
        from = ctx.asOf - calyears(n);
    else
        from = ctx.asOf - calmonths(n);
    end
    args.startDate = char(fomc.util.fmtDate(from));
end

% Run the tool through the normal path (guardrails and trace apply). Dates chosen here come
% from the question, so the tool must keep them (see its rule for a copied focus window).
if isfield(args, "startDate")
    args.datesFromQuestion = true;
end
[json, rec] = fomc.tools.dispatch(ctx, "getPolicyPath", args);
recs(end+1) = rec;
if ~rec.ok
    return
end
r = jsondecode(json);
text = "[Rate path worked out by code from the rate data and the minutes. Use it for how rates moved, " + ...
    "and cite its ids:" + newline + string(r.summary) + "]";
fomc.trace.logEvent(ctx, "prefetch", struct("kind", "path", "startDate", r.span.startDate, "endDate", r.span.endDate));
end
