function [text, recs] = pathPrefetch(ctx, question, followsRatePath)
%PATHPREFETCH The path of the rate target, looked up before the model starts.
%   [text, recs] = fomc.focus.pathPrefetch(ctx, question, followsRatePath)
%   A small model often answers a question about rates over time from the latest figures
%   alone and skips getPolicyPath. So when the wording asks how rates moved (a rate word and
%   a change-over-time word, or a rate word and a span of years), the harness runs getPolicyPath
%   itself and adds its summary to the question. followsRatePath (default false): the
%   previous answer used the rate path, so a short follow-up that only names a period ("And
%   what about in 2022?") gets it too. The span: "since 2022" (to the anchor date), the years
%   the question names (one year is that calendar year; a decade such as "the 2010s" is its ten
%   years), "the last N years/months", "this year", else the tool's default of the latest 8
%   meetings. Years are trimmed to what the rate data covers, 1990 to the anchor year; a
%   question whose years are all outside that gets nothing, rather than a different span.
%   Other questions get nothing. No model.

if nargin < 3
    followsRatePath = false;
end
text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch
    return
end
q = lower(string(question));
if ~isRateQuestion(q) && ~(followsRatePath && isPeriodFollowUp(q, question, ctx))
    return
end
[lo, hi] = yearRange(q, year(ctx.asOf));
if lo > hi
    return
end

% Run the tool through the normal path (guardrails and trace apply). Dates chosen here come
% from the question, so the tool must keep them (see its rule for a copied focus window).
args = spanArgs(q, ctx.asOf);
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

function tf = isRateQuestion(q)
% A rate word and a change-over-time word, or a rate word and a span of years ("between 2015
% and 2018", "the 2010s"). Other rates ("the
% unemployment rate rose", "the rate of inflation", "long-term interest rates") and other
% easing ("easing of supply chain pressures") do not count.
q = regexprep(q, "(unemployment|inflation|mortgage|exchange|participation|savings?|jobless|vacancy|" + ...
    "default|delinquency|quits?|layoff|tax|growth|prime|birth|death)\s+rates?", " ");
q = regexprep(q, "(long-term|longer-term|long|real|market|bond|treasury|\d+-year)\s+(interest\s+)?rates?", " ");
q = regexprep(q, "rates? of (inflation|unemployment|growth|interest on reserves)", " ");
rateWords = "fed funds|federal funds|policy rate|interest rate|target range|(?<![a-z])rates?(?![a-z])|" + ...
    "(?<![a-z])hik(e|es|ed|ing)(?![a-z])|(policy|monetary) (easing|tightening)|" + ...
    "(easing|tightening|loosening) (cycle|of (monetary )?policy)|tighten(ed|ing)? (monetary )?policy|monetary policy";
changeWords = "chang\w*|over the (past|last)|in the (past|last)|since|between|trend|cycle|path|trajectory|" + ...
    "history|evolv\w*|moved?|movement|so far|lately|recently|how (many|much|often)|sequence|series of|" + ...
    "(?<![a-z])rise|(?<![a-z])rose|risen|fall|fell|fallen|climb\w*|declin\w*|went (up|down)|gone (up|down)|" + ...
    "(?<![a-z])(this|last|past) year";
[lo, hi] = yearRange(q, Inf);
tf = ~isempty(regexp(q, rateWords, "once")) && (~isempty(regexp(q, changeWords, "once")) || hi > lo);
end

function tf = isPeriodFollowUp(q, question, ctx)
% A short follow-up that names a period and nothing else besides rates: no other data topic
% ("What about inflation in 2022?"), nothing about the minutes or what officials said ("Who
% dissented in 2022?", "What did they say in 2022?")
namesPeriod = ~isnan(yearRange(q, Inf)) || ...
    ~isempty(regexp(q, "(past|last)\s+(\d+|[a-z]+)\s+(of\s+)?(year|month)s?|(this|past|last) year", "once"));
short = numel(split(strtrim(q))) <= 10;
topics = setdiff(fomc.focus.dataTopics(question, ctx.D.dict.series_id), ["FEDFUNDS"; "DFEDTARU"; "DFEDTARL"]);
otherTopic = ~isempty(topics) || fomc.focus.aboutMinutes(question) || ...
    ~isempty(regexp(q, "(?<![a-z])(say|said|says|discuss\w*|think|thought|view\w*|expect\w*|worr\w*|concern\w*)(?![a-z])", "once"));
tf = namesPeriod && short && ~otherTopic;
end

function args = spanArgs(q, asOf)
% The dates a question names: its years (see yearRange), "the last N years/months" ("few"
% and "several" are 3, "couple" 2), "this year"; none for the tool's default
[lo, hi, openEnded] = yearRange(q, year(asOf));
words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"];
vague = ["couple", "few", "several"];
vagueN = [2, 3, 3];
back = regexp(q, "(?:past|last)\s+(\d+|" + strjoin([words, vague], "|") + ")\s+(?:of\s+)?(year|month)s?", "tokens", "once");
args = struct();
if ~isnan(lo)
    args.startDate = char(fomc.util.fmtDate(datetime(lo, 1, 1)));
    if ~openEnded
        args.endDate = char(fomc.util.fmtDate(min(asOf, datetime(hi, 12, 31))));
    end
elseif ~isempty(back)
    n = str2double(back{1});
    if isnan(n)
        n = [find(words == back{1}), vagueN(vague == back{1})];
    end
    if back{2} == "year"
        from = asOf - calyears(n);
    else
        from = asOf - calmonths(n);
    end
    args.startDate = char(fomc.util.fmtDate(from));
elseif ~isempty(regexp(q, "this year", "once"))
    args.startDate = char(fomc.util.fmtDate(datetime(year(asOf), 1, 1)));
end
end

function [lo, hi, openEnded] = yearRange(q, topYear)
% The years a question names, as one range: from the earliest year named to the latest, a
% decade ("the 2010s") to its last year, "since 2020" to topYear (openEnded). Trimmed to what
% the rate data covers: 1990 (where it starts) to topYear, the anchor year (Inf trims nothing
% at the top). NaN, NaN if the question names no year; lo > hi if none of its years have data.
lo = NaN;
hi = NaN;
openEnded = false;
years = double(string(regexp(q, "(?<!\d)(19\d\d|20\d\d)(?!\d)", "match")));
if isempty(years)
    return
end
decades = double(extractBefore(string(regexp(q, "(?<!\d)(19|20)\d0s(?![a-z])", "match")), 5));
lo = min(years);
hi = max([years, decades + 9]);
since = regexp(q, "since\s+(?:the\s+)?(19\d\d|20\d\d)(?!\d)", "tokens", "once");
if ~isempty(since)
    lo = str2double(since{1});
    hi = Inf;
    openEnded = true;
end
lo = max(lo, 1990);
hi = min(hi, topYear);
end
