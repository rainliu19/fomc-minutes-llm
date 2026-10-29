function r = outlookAssessment(D, asOf)
%OUTLOOKASSESSMENT What the recent path of rates may mean ahead, from evidence known on a date.
%   r = fomc.data.outlookAssessment(D, asOf)
%   No forecast of its own. Three kinds of evidence, each as known on asOf:
%   - The Fed staff's forecast: whether the inflation and growth forecasts were revised up or
%     down at each of the last 4 meetings with public minutes, and the risks the staff saw at
%     the latest (fomc.data.forecastRevisions), with the paragraph behind each.
%   - How far the rate changes have reached so far: each step from market rates to borrowing
%     costs to spending and inflation, and the average rate the Treasury pays on its debt, at
%     the anchor date, just before the first change of the current run of increases or cuts,
%     and six months before it (markets often move ahead of the Fed). A monthly reading from
%     before the first change cannot show its effect.
%   - What followed earlier runs in the same direction since 1990: a year and two years
%     after their first change (the Treasury's average rate from 2001).
%   Plus what markets expect: the 2-year Treasury yield against the middle of the range.
%   r.summary says it in plain sentences, citing paragraph ids; r.series holds the figures
%   cited, for the High-effort figure check. No model.

arguments
    D (1,1) struct
    asOf (1,1) datetime
end

% The current run of increases or cuts, and every earlier run
[moves, levels] = fomc.data.ratePath(D, asOf);
runId = cumsum([1; diff(sign(moves.change)) ~= 0]);
firstOfRun = [true; diff(runId) ~= 0];
starts = moves(firstOfRun, :);
starts.runId = runId(firstOfRun);
rangeNow = levels(end, :);

r = struct("anchorDate", fomc.util.fmtDate(asOf));
r.targetRange = fomc.util.rangeText(rangeNow.lower, rangeNow.upper);
[r.staffForecast, forecastText] = forecastPart(D, asOf);
if isempty(starts)
    r.summary = forecastText;
    r.series = {};
    return
end
current = starts(end, :);
r.currentRun = struct("direction", directionWord(current.change), "firstChange", fomc.util.fmtDate(current.date), ...
    "changes", sum(runId == current.runId), "totalChange", round(sum(moves.change(runId == current.runId)), 4));
[r.soFar, soFarText, series] = soFarPart(D, asOf, current.date, r.currentRun);
[r.earlierRuns, earlierText] = earlierPart(D, asOf, starts(2:end-1, :), r.currentRun.direction);
[market, marketText, marketSeries] = marketPart(D, asOf, rangeNow);
if ~isempty(fieldnames(market))
    r.market = market;
end

r.summary = strjoin([forecastText, soFarText, earlierText, marketText], " ");
r.series = [series; marketSeries];
r.note = "No one can know these effects in advance: the staff forecast is the Fed's own view, the data show " + ...
    "only what has happened so far, and earlier runs are history, not a rule. Say what the evidence shows " + ...
    "(the staff expects, so far, in earlier runs), never what will happen. For federal debt the data have " + ...
    "the average rate the Treasury pays and Treasury yields, not total interest payments; credit card and " + ...
    "car loan rates are not in this data.";
end

function [part, text] = forecastPart(D, asOf)
% The staff's inflation and growth forecasts at the last 4 meetings with public minutes: how
% each was revised, and the risks the staff saw at the latest
M = D.meetings;
k = find(M.ReleaseDate <= asOf);
k = k(max(1, end - 3):end);
part = struct();
if isempty(k)
    text = "No minutes were public on this date, so there is no staff forecast to report.";
    return
end
F = fomc.data.forecastRevisions(D, k);
part.meetings = F.meetingDate.';
words = struct("inflation", ["higher", "lower"], "activity", ["stronger", "weaker"]);
subjects = struct("inflation", "inflation", "activity", "growth and spending");
text = "Fed staff forecasts at the last " + count(numel(k), "meeting") + " with public minutes (" + ...
    F.meetingDate(1) + " to " + F.meetingDate(end) + ", each against the meeting before): ";
pieces = strings(1, 0);
for t = ["inflation", "activity"]
    said = F.(t);
    w = said;
    w(said == "higher") = words.(t)(1);
    w(said == "lower") = words.(t)(2);
    part.(t) = struct("revisions", w.', "ids", F.(t + "Id").');
    pieces(end+1) = subjects.(t) + " " + tally(w, F.(t + "Id")); %#ok<AGROW>
end
text = text + strjoin(pieces, "; ") + ".";
% The risks, from the latest meeting that states them
last = F(end, :);
risks = strings(1, 0);
names = struct("inflation", "inflation", "activity", "growth and jobs");
for t = ["inflation", "activity"]
    if last.(t + "Risk") ~= ""
        part.(t).risks = last.(t + "Risk");
        risks(end+1) = names.(t) + " " + riskWords(last.(t + "Risk")) + cite(last.(t + "RiskId")); %#ok<AGROW>
    end
end
if ~isempty(risks)
    text = text + " The staff's latest view of the risks: " + strjoin(risks, "; ") + ".";
end
end

function t = tally(w, ids)
% "revised higher at 3 [id] and about the same at 1 [id]", citing the latest meeting for each
% answer; meetings whose minutes make no comparison are counted as such
order = unique([setdiff(w(w ~= ""), "about the same", "stable"); w(w == "about the same")], "stable");
parts = strings(1, 0);
for i = 1:numel(order)
    j = find(w == order(i), 1, "last");
    phrase = "revised " + order(i);
    if order(i) == "about the same"
        phrase = order(i);
    elseif order(i) == "mixed"
        phrase = "revised both ways";
    end
    parts(end+1) = phrase + " at " + sum(w == order(i)) + cite(ids(j)); %#ok<AGROW>
end
none = sum(w == "");
if none > 0
    parts(end+1) = "not compared at " + none;
end
t = strjoin(parts, ", ");
end

function [part, text, series] = soFarPart(D, asOf, firstDate, run)
% Each step from market rates to inflation: now, just before the first change of the run, and
% six months before it
steps = [
    "DGS2",         "the 2-year Treasury yield",      "level"
    "DGS10",        "the 10-year Treasury yield",     "level"
    "MORTGAGE30US", "the 30-year mortgage rate",      "level"
    "BAA10Y",       "the corporate bond spread (Baa)", "level"
    "PCEC96",       "real consumer spending growth",  "yoy"
    "PCEPILFE",     "core PCE inflation",             "yoy"
    "MICH",         "consumers' expected inflation",  "level"
    "TREASURY_AVG_RATE", "the Treasury's average rate on its debt", "level"];
part = {};
series = {};
fast = strings(1, 0);
slow = strings(1, 0);
notYet = strings(1, 0);
debt = "";
for i = 1:height(steps)
    [s, rows] = stepValues(D, asOf, steps(i, 1), steps(i, 3), firstDate);
    if isempty(fieldnames(s))
        continue
    end
    s.name = steps(i, 2);
    part{end+1, 1} = s; %#ok<AGROW>
    series = [series; rows]; %#ok<AGROW>
    daily = steps(i, 3) == "level" && steps(i, 1) ~= "MICH";
    phrase = steps(i, 2) + " " + pct(s.now, daily) + " (" + s.nowDate;
    if isfield(s, "before")
        phrase = phrase + "; just before: " + pct(s.before, daily);
        if isfield(s, "sixMonthsBefore")
            phrase = phrase + "; six months before: " + pct(s.sixMonthsBefore, daily);
        end
    end
    phrase = phrase + ")";
    if steps(i, 1) == "TREASURY_AVG_RATE"
        debt = phrase;
        if ~s.sinceFirstChange
            debt = debt + ", a reading from before the " + run.direction;
        end
    elseif daily
        fast(end+1) = phrase; %#ok<AGROW>
    elseif s.sinceFirstChange
        slow(end+1) = phrase; %#ok<AGROW>
    else
        notYet(end+1) = steps(i, 2) + " " + pct(s.now, false) + " (" + s.nowDate + ")"; %#ok<AGROW>
    end
end
dirWord = run.direction;
text = "The current run began with " + article(dirWord) + dirWord + " on " + run.firstChange;
if run.changes > 1
    text = text + " (" + count(run.changes, dirWord) + ", " + signed(run.totalChange) + " percentage point" + ...
        plural(run.totalChange) + " in all)";
end
text = text + ".";
if ~isempty(fast)
    text = text + " Rates: " + strjoin(fast, "; ") + ".";
end
if ~isempty(slow)
    text = text + " Spending and prices: " + strjoin(slow, "; ") + ".";
end
if debt ~= ""
    text = text + " Federal debt: " + debt + ".";
end
if ~isempty(notYet)
    text = text + " Too early to show the " + dirWord + ": " + strjoin(notYet, ", ") + ...
        " are readings from before it.";
end
end

function [s, rows] = stepValues(D, asOf, id, kind, firstDate)
% One series now, just before firstDate and six months before it. For a 12-month change, the
% value is the change and the rows list the index too. sinceFirstChange: the latest reading
% covers time after firstDate.
s = struct();
rows = {};
T = known(D, id, asOf);
if isempty(T)
    return
end
monthly = D.dict.frequency(D.dict.series_id == id) == "monthly";
periodEnd = T.date;
if monthly
    periodEnd = T.date + calmonths(1) - caldays(1);
end
idx = [height(T), lastBefore(periodEnd, firstDate), lastBefore(periodEnd, firstDate - calmonths(6))];
v = nan(1, 3);
for j = 1:numel(idx)
    if j > 1 && (isnan(idx(j)) || idx(j) == idx(1))
        break
    end
    v(j) = valueAt(T, idx(j), kind);
end
if isnan(v(1))
    return
end
s = struct("seriesId", id, "now", round(v(1), 2), "nowDate", dateWords(T.date(idx(1)), monthly), ...
    "sinceFirstChange", periodEnd(idx(1)) >= firstDate);
rows = {row(T, idx(1), id, kind)};
names = ["", "before", "sixMonthsBefore"];
for j = 2:3
    if ~isnan(v(j))
        s.(names(j)) = round(v(j), 2);
        s.(names(j) + "Date") = fomc.util.fmtDate(T.date(idx(j)));
        rows{end+1, 1} = row(T, idx(j), id, kind); %#ok<AGROW>
    end
end
rows = rows(:);
end

function i = lastBefore(periodEnd, d)
% The last row whose period ended before d; NaN if none
i = find(periodEnd < d, 1, "last");
if isempty(i)
    i = NaN;
end
end

function v = valueAt(T, i, kind)
% A level, or the percent change over the 12 months to row i (NaN if that month is missing)
v = T.value(i);
if kind == "yoy"
    k = find(T.date == T.date(i) - calmonths(12), 1);
    v = NaN;
    if ~isempty(k)
        v = 100 * (T.value(i) / T.value(k) - 1);
    end
end
end

function x = row(T, i, id, kind)
% A figure as the figure check reads it: series, date, value (and the 12-month change)
x = struct("seriesId", id, "date", fomc.util.fmtDate(T.date(i)), "value", T.value(i));
if kind == "yoy"
    x.yoyPct = valueAt(T, i, kind);
end
end

function [part, text] = earlierPart(D, asOf, starts, direction)
% Earlier runs in the same direction since 1990 (the first run in the data is left out: it
% began before the data do), a year and two years after their first change
part = {};
text = "";
same = starts(sign(starts.change) == sign(directionSign(direction)), :);
same = same(same.date + calyears(1) <= asOf, :);
if isempty(same)
    return
end
M = known(D, "MORTGAGE30US", asOf);
C = known(D, "PCEC96", asOf);
P = known(D, "PCEPILFE", asOf);
G = known(D, "TREASURY_AVG_RATE", asOf);
out = struct("mortgage", nan(height(same), 2), "spending", nan(height(same), 2), "inflation", nan(height(same), 2), ...
    "debtRate", nan(height(same), 2));
for i = 1:height(same)
    d = same.date(i);
    entry = struct("firstChange", fomc.util.fmtDate(d));
    for h = 1:2
        later = d + calyears(h);
        if later > asOf
            continue
        end
        out.mortgage(i, h) = levelChange(M, d, later);
        out.spending(i, h) = yoyChange(C, d, later);
        out.inflation(i, h) = yoyChange(P, d, later);
        out.debtRate(i, h) = levelChange(G, d, later);
    end
    entry.mortgageChange = round(out.mortgage(i, :), 2);
    entry.spendingGrowthChange = round(out.spending(i, :), 2);
    entry.coreInflationChange = round(out.inflation(i, :), 2);
    entry.treasuryAverageRateChange = round(out.debtRate(i, :), 2);
    part{end+1, 1} = entry; %#ok<AGROW>
end
dates = strjoin(fomc.util.fmtDate(same.date), ", ");
text = "Earlier runs of " + direction + "s since 1990 (first " + direction + " on " + dates + "), " + ...
    "a year after the first " + direction + ": " + ...
    cycleText(out.mortgage(:, 1), "mortgage rate", "higher", "lower") + "; " + ...
    cycleText(out.spending(:, 1), "real spending growth", "faster", "slower") + "; " + ...
    cycleText(out.inflation(:, 1), "core inflation", "higher", "lower");
if any(~isnan(out.debtRate(:, 1)))
    text = text + "; " + cycleText(out.debtRate(:, 1), "the Treasury's average rate (from 2001)", "higher", "lower");
end
text = text + ".";
if any(~isnan(out.inflation(:, 2)))
    text = text + " Two years after: " + cycleText(out.inflation(:, 2), "core inflation", "higher", "lower") + ".";
end
end

function t = cycleText(x, name, up, down)
% "mortgage rate higher in 4 of 6 (median +0.4 point)"; runs without data are left out
x = x(~isnan(x));
if isempty(x)
    t = name + ": no data";
    return
end
nUp = sum(x > 0);
nDown = sum(x < 0);
if nUp >= nDown
    t = name + " " + up + " in " + nUp + " of " + numel(x);
else
    t = name + " " + down + " in " + nDown + " of " + numel(x);
end
m = round(median(x), 1);
t = t + " (median " + signed(m) + " point" + plural(m) + ")";
end

function c = levelChange(T, from, to)
% Change in a level from just before 'from' to just before 'to'
c = NaN;
a = find(T.date < from, 1, "last");
b = find(T.date < to, 1, "last");
if ~isempty(a) && ~isempty(b) && b > a
    c = T.value(b) - T.value(a);
end
end

function c = yoyChange(T, from, to)
% Change in the 12-month growth rate from the last month that ended before 'from' to the last
% month that ended before 'to'
c = NaN;
if isempty(T)
    return
end
ended = T.date + calmonths(1) - caldays(1);
a = find(ended < from, 1, "last");
b = find(ended < to, 1, "last");
if isempty(a) || isempty(b)
    return
end
c = valueAt(T, b, "yoy") - valueAt(T, a, "yoy");
end

function [market, text, series] = marketPart(D, asOf, rangeNow)
% What markets expect: the 2-year Treasury yield against the middle of the range
market = struct();
series = {};
text = strings(1, 0);
Y = known(D, "DGS2", asOf);
if isempty(Y)
    return
end
spread = Y.value(end) - (rangeNow.lower + rangeNow.upper) / 2;
reading = "little change in the federal funds rate";
if spread > 0.25
    reading = "further increases";
elseif spread < -0.25
    reading = "cuts";
end
market = struct("twoYearYield", Y.value(end), "date", fomc.util.fmtDate(Y.date(end)), ...
    "aboveMiddleOfRange", round(spread, 2), "suggests", reading);
series = {struct("seriesId", "DGS2", "date", market.date, "value", Y.value(end))};
where = string(sprintf("%.1f", abs(spread))) + " point" + plural(spread) + aboveBelow(spread) + " the middle of";
if round(abs(spread), 1) == 0
    where = "at the middle of";
end
text = "Markets: the 2-year yield is " + where + " the target range (" + ...
    fomc.util.rangeText(rangeNow.lower, rangeNow.upper) + "), which suggests markets expect " + reading + ...
    " over the next two years.";
end

function T = known(D, id, asOf)
% A series as known on the anchor date; empty if none is
[T, ~] = fomc.data.valueAsOf(D, id, asOf);
end

function t = dateWords(d, monthly)
% "August 2026" for a monthly reading, else the date
if monthly
    t = string(d, "MMMM yyyy");
else
    t = fomc.util.fmtDate(d);
end
end

function t = riskWords(side)
% "tilted to the upside", "tilted to the downside", "balanced"
t = side;
if side ~= "balanced"
    t = "tilted to the " + side;
end
end

function t = cite(id)
% " [2026-09-16/staffOutlook/1]", or nothing when there is no paragraph to cite
t = "";
if id ~= ""
    t = " [" + id + "]";
end
end

function t = pct(x, twoDecimals)
% 3.012 -> "3.0%", or "3.01%" for market rates, which move by hundredths
if nargin > 1 && twoDecimals
    t = string(sprintf("%.2f%%", x));
else
    t = string(sprintf("%.1f%%", x));
end
end

function t = signed(x)
% +1.2, -0.5, 0
if x > 0
    t = "+" + string(x);
elseif x < 0
    t = "-" + string(abs(x));
else
    t = "0";
end
end

function t = plural(x)
% "s" unless the size rounds to 1 or less
t = "";
if round(abs(x), 1) > 1
    t = "s";
end
end

function t = aboveBelow(x)
% " above" for zero or more, " below" otherwise
if x >= 0
    t = " above";
else
    t = " below";
end
end

function t = count(n, noun)
% "1 meeting", "5 meetings"
t = n + " " + noun;
if n ~= 1
    t = t + "s";
end
end

function w = directionWord(change)
% "increase" or "cut"
if change > 0
    w = "increase";
else
    w = "cut";
end
end

function s = directionSign(direction)
% +1 for increases, -1 for cuts
s = 1;
if direction == "cut"
    s = -1;
end
end

function a = article(word)
% "an increase", "a cut"
a = "a ";
if startsWith(word, ["a", "e", "i", "o", "u"])
    a = "an ";
end
end
