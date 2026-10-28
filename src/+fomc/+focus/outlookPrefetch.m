function [text, recs] = outlookPrefetch(ctx, question)
%OUTLOOKPREFETCH What the recent path of rates may mean ahead, looked up before the model starts.
%   [text, recs] = fomc.focus.outlookPrefetch(ctx, question)
%   For questions about what the Fed's moves mean for the economy ahead (inflation, borrowing
%   costs, spending, jobs, growth), the harness gathers the evidence (fomc.data.outlookAssessment):
%   how the Fed staff revised its forecasts, how far the rate changes have reached so far, what
%   followed earlier runs, and what markets expect. The model is also offered this as the
%   getOutlook tool, but a small model often skips tools, so the harness runs it through the
%   normal tool path (guardrails and trace apply) for questions the wording shows are about
%   effects ahead. A question that names only years before the anchor year ("What did the 2022
%   increases do to mortgage rates?") gets the evidence as it stood at the end of the latest
%   year named. A question about something the data lack (interest on federal debt, credit card
%   or car loan rates) is told so first. Other questions get nothing. No model.

text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch || ~asksWhatItMeansAhead(lower(string(question)))
    return
end

% Run the tool as known on the anchor date, or at the end of a past year the question names
% (the tool path withholds anything dated later)
[json, rec] = fomc.tools.dispatch(ctx, "getOutlook", endDateArg(lower(string(question)), ctx.asOf));
recs(end+1) = rec;
if ~rec.ok
    return
end
r = jsondecode(json);
text = "[Evidence on what the recent rate path may mean ahead, gathered by code from the minutes and data as known on " + ...
    r.anchorDate + ". It is the Fed staff's forecast, what has happened so far and earlier runs, not a prediction: " + ...
    "say what the evidence shows, never what will happen, and cite its ids:" + newline + missingFirst(lower(string(question))) + ...
    string(r.summary) + "]";
fomc.trace.logEvent(ctx, "prefetch", struct("kind", "outlook"));
end

function t = missingFirst(q)
% A question about something the data lack gets that said first, as an instruction: a small model
% skipped the same line when it was only in the result's note
t = "";
missing = ["interest on (the )?(federal|national|government|u\.s\.) debt|(federal|national|government) debt|" + ...
        "deficit|treasury'?s? interest|debt (service|servicing)", "interest on federal debt"
    "credit cards?", "credit card rates"
    "car loans?|auto(mobile)? loans?|car payments?", "car loan rates"];
named = strings(1, 0);
for i = 1:height(missing)
    if ~isempty(regexp(q, missing(i, 1), "once"))
        named(end+1) = missing(i, 2); %#ok<AGROW>
    end
end
if isempty(named)
    return
end
verb = "is";
if numel(named) > 1
    verb = "are";
end
t = "The question asks about " + strjoin(named, " and ") + ", which " + verb + " not in this data. " + ...
    "Begin the answer by saying so plainly, then give only the evidence below that bears on it." + newline;
end

function args = endDateArg(q, asOf)
% The end of the latest year the question names, if every year it names is before the anchor
% year; none otherwise (the anchor date)
args = struct();
years = double(string(regexp(q, "(?<!\d)(19\d\d|20\d\d)(?!\d)", "match")));
if ~isempty(years) && max(years) < year(asOf) && max(years) >= 1991
    args.endDate = char(fomc.util.fmtDate(datetime(max(years), 12, 31)));
end
end

function tf = asksWhatItMeansAhead(q)
% An effect or future word and something the economy does: "What do these minutes mean for
% inflation?", "How will higher rates affect consumer spending?", "What did the 2022 increases do
% to mortgage rates?", "Is now a good time to buy a house?"; or where things are headed after
% the Fed's moves
effect = "(?<![a-z])(mean|means|meant) for|(?<![a-z])(implications?|imply|implies|impact\w*|affect\w*|" + ...
    "effects? (on|of)|consequences?|pass(es|ed)? through|transmi\w*|feed\w* through)(?![a-z])|" + ...
    "(?<![a-z])(do|did|does|done) to|good time to";
headed = "where (are|is|will) (things|the economy|we|it|rates|this|inflation|prices) (\w+ )?(head\w*|going)";
if ~isempty(regexp(q, headed, "once"))
    tf = true;
    return
end
future = "future|ahead|going forward|outlook|forecast\w*|projection|" + ...
    "next (year|few|couple|\d+|six|twelve|several)|coming (months|years?|quarters?)|" + ...
    "(will|going to|expected to|likely to) (\w+ ){0,3}(rise|fall|go|be|slow|stay|come|keep|cool|pick|drop|" + ...
    "increase|decrease|decline|happen|change|look|hurt|help)";
area = "inflation|(?<![a-z])prices|cost of living|mortgage|borrow\w*|loans?(?![a-z])|credit|debt|" + ...
    "interest (costs?|payments?|expenses?)|spending|consum\w*|households?|econom\w*|growth|recession|" + ...
    "jobs?(?![a-z])|unemployment|labor market|housing|(?<![a-z])(house|homes?)(?![a-z])|wages?(?![a-z])|businesses";
tf = (~isempty(regexp(q, effect, "once")) || ~isempty(regexp(q, future, "once"))) && ...
    ~isempty(regexp(q, area, "once"));
end
