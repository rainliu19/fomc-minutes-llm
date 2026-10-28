function r = economyAssessment(D, asOf)
%ECONOMYASSESSMENT How the economy compares with the Fed's goals, and what the latest minutes say next.
%   r = fomc.data.economyAssessment(D, asOf)
%   Core PCE inflation against the 2 percent goal, unemployment against the CBO's estimate of
%   its normal level, payroll growth, real GDP growth and real GDP against the CBO's estimate
%   of potential, two policy rules (Taylor 1993 and the balanced approach, each with a
%   neutral real rate of 0.5 and 2 percent) against the actual target range, the 6-month
%   Treasury bill against the effective fed funds rate, and the 2-year yield against the middle
%   of the range. Then the latest minutes
%   public on asOf: what participants said about the rate at future meetings
%   (fomc.data.policyViews) and how the staff revised its forecast (fomc.data.forecastRevisions),
%   each cited to its paragraph. Every value is read as known on asOf (fomc.data.valueAsOf),
%   so revised series use the vintage then published. r.summary says it in plain sentences;
%   r.series holds the inputs, for the High-effort figure check. Missing inputs are said to
%   be missing, never guessed. No model.

arguments
    D (1,1) struct
    asOf (1,1) datetime
end

% The actual target range (the single target before December 2008)
[~, levels] = fomc.data.ratePath(D, asOf);
rangeNow = levels(end, :);

% Each part: its facts, its sentences, and the series it used
[infl, inflText, inflSeries] = inflationPart(D, asOf);
[unemp, unempText, unempSeries] = unemploymentPart(D, asOf);
[jobs, jobsText, jobsSeries] = payrollPart(D, asOf);
[growth, growthText, growthSeries] = growthPart(D, asOf);
[outGap, gapText, gapSeries] = outputGapPart(D, asOf);
[rules, vsRange, rulesText] = rulesPart(infl, outGap, rangeNow);
[market, marketText, twoYearText, marketSeries] = marketPart(D, asOf, rangeNow);
[minutes, minutesText] = minutesPart(D, asOf, rangeNow);
next = fomc.data.nextMeetingReading(D, asOf);
nextText = strings(1, 0);
if ~isempty(fieldnames(next))
    nextText = next.text;
end

% The next-meeting reading first, then the minutes behind it, then the economy, and the policy
% rules and the 2-year yield last, as background on the stance rather than the next step
r = struct("anchorDate", fomc.util.fmtDate(asOf));
r.summary = strjoin([nextText, minutesText, inflText, unempText, jobsText, growthText, gapText, marketText, ...
    "Background on where policy may go over the next year or two, not at the next meeting:", ...
    twoYearText, rulesText], " ");
if ~isempty(fieldnames(next))
    r.nextMeeting = rmfield(next, "text");
end
r.inflation = infl;
r.unemployment = unemp;
if ~isempty(fieldnames(jobs))
    r.payrolls = jobs;
end
if ~isempty(fieldnames(growth))
    r.gdpGrowth = growth;
end
r.outputGap = outGap;
r.targetRange = fomc.util.rangeText(rangeNow.lower, rangeNow.upper);
r.rules = rules;
r.rulesVsRange = vsRange;
if ~isempty(fieldnames(market))
    r.market = market;
end
if ~isempty(fieldnames(minutes))
    r.minutes = minutes;
end
r.series = [inflSeries; unempSeries; jobsSeries; growthSeries; gapSeries; marketSeries];
% How the minutes' direction was read: the AI's score where the minutes were scored, else code
howRead = "The lean of the minutes is read by code from their wording.";
if isfield(r, "minutes") && r.minutes.directionSource == "ai"
    howRead = "The lean of the minutes is the AI's score of their rate path, checked against the sentences it quotes.";
end
r.note = "Policy rules are rules of thumb, not forecasts: the Fed follows none of them, and the neutral real " + ...
    "rate is uncertain, so two values are shown. The CBO estimates and GDP are as published on the anchor " + ...
    "date and are revised later. Treasury yields also reflect term premia, so they are only a rough guide to " + ...
    "expected policy. " + howRead + " Quote the sentences, and " + ...
    "say what participants expected, never what the Committee will do. For the next meeting, the minutes give " + ...
    "the direction and the 6-month bill the timing: participants often expect further moves and hold first.";
end

function [jobs, text, series] = payrollPart(D, asOf)
% Payroll growth: the average monthly change over the latest three months
jobs = struct();
series = {};
text = strings(1, 0);
P = known(D, "PAYEMS", asOf);
k = find(P.date == P.date(end) - calmonths(3), 1);
if isempty(k)
    return
end
avg = (P.value(end) - P.value(k)) / 3;
jobs = struct("averageMonthlyChangeThousands", round(avg), "threeMonthsTo", fomc.util.fmtDate(P.date(end)));
series = {struct("seriesId", "PAYEMS", "date", jobs.threeMonthsTo, "value", P.value(end))
    struct("seriesId", "PAYEMS", "date", fomc.util.fmtDate(P.date(k)), "value", P.value(k))};
verb = "rose";
if avg < 0
    verb = "fell";
end
text = "Payrolls " + verb + " by an average of " + regexprep(string(round(abs(avg)) * 1000), "(\d)(?=(\d{3})+$)", "$1,") + ...
    " a month over the three months to " + monthName(P.date(end)) + ".";
end

function [growth, text, series] = growthPart(D, asOf)
% Real GDP growth in the latest quarter, at an annual rate
growth = struct();
series = {};
text = strings(1, 0);
G = known(D, "A191RL1Q225SBEA", asOf);
if isempty(G)
    return
end
growth = struct("quarter", quarter(G.date(end)), "annualRate", G.value(end));
series = {struct("seriesId", "A191RL1Q225SBEA", "date", fomc.util.fmtDate(G.date(end)), "value", G.value(end))};
verb = "grew";
if G.value(end) < 0
    verb = "shrank";
end
text = "Real GDP " + verb + " at a " + pct(abs(G.value(end))) + " annual rate in " + growth.quarter + ".";
end

function [infl, text, series] = inflationPart(D, asOf)
% Core PCE inflation over 12 months against the 2 percent goal, and the same measure three
% months earlier
infl = struct();
series = {};
text = "Core PCE inflation is not known on this date.";
P = known(D, "PCEPILFE", asOf);
if height(P) <= 15
    return
end
now12 = change12(P, height(P));
earlier12 = change12(P, find(P.date <= P.date(end) - calmonths(3), 1, "last"));
if isnan(now12)
    return
end
infl = struct("measure", "core PCE prices, 12-month change", "value", round(now12, 2), ...
    "date", fomc.util.fmtDate(P.date(end)), "threeMonthsEarlier", round(earlier12, 2), ...
    "goal", 2, "gap", round(now12 - 2, 2), "trend", trend(now12, earlier12));
series = {struct("seriesId", "PCEPILFE", "date", infl.date, "value", P.value(end), "yoyPct", now12)};
text = "Core PCE inflation was " + pct(now12) + " over the 12 months to " + monthName(P.date(end)) + ...
    ", " + points(now12 - 2) + aboveBelow(now12 - 2) + " the Fed's 2% goal" + trendText(infl.trend, earlier12) + ".";
end

function [unemp, text, series] = unemploymentPart(D, asOf)
% Unemployment against the CBO's estimate of its normal level for the same quarter
unemp = struct();
series = {};
text = strings(1, 0);
U = known(D, "UNRATE", asOf);
if isempty(U)
    return
end
u = U.value(end);
k3 = find(U.date <= U.date(end) - calmonths(3), 1, "last");
u3 = NaN;
if ~isempty(k3)
    u3 = U.value(k3);
end
unemp = struct("value", u, "date", fomc.util.fmtDate(U.date(end)), "threeMonthsEarlier", u3, "trend", trend(u, u3));
series = {struct("seriesId", "UNRATE", "date", unemp.date, "value", u)};
text = "Unemployment was " + pct(u) + " in " + monthName(U.date(end));
N = known(D, "NROU", asOf);
kN = find(N.date <= U.date(end), 1, "last");
if ~isempty(kN)
    unemp.normal = round(N.value(kN), 2);
    unemp.gap = round(u - N.value(kN), 2);
    series{end+1, 1} = struct("seriesId", "NROU", "date", fomc.util.fmtDate(N.date(kN)), "value", N.value(kN));
    text = text + ", " + points(unemp.gap) + aboveBelow(unemp.gap) + ...
        " the CBO's estimate of its normal level (" + pct(N.value(kN)) + ")";
end
text = text + trendText(unemp.trend, u3) + ".";
if isempty(kN)
    text = text + " The CBO's estimate of its normal level is not in this data before February 2011.";
end
end

function [outGap, text, series] = outputGapPart(D, asOf)
% Real GDP against the CBO's estimate of potential, for the latest quarter of GDP
outGap = struct();
series = {};
text = strings(1, 0);
G = known(D, "GDPC1", asOf);
Pot = known(D, "GDPPOT", asOf);
if isempty(G)
    return
end
kP = find(Pot.date == G.date(end), 1);
if isempty(kP)
    return
end
g = 100 * (G.value(end) / Pot.value(kP) - 1);
outGap = struct("quarter", quarter(G.date(end)), "value", round(g, 2));
series = {struct("seriesId", "GDPC1", "date", fomc.util.fmtDate(G.date(end)), "value", G.value(end))
    struct("seriesId", "GDPPOT", "date", fomc.util.fmtDate(Pot.date(kP)), "value", Pot.value(kP))};
text = "Real GDP was " + pct(abs(g)) + aboveBelow(g) + " the CBO's estimate of its potential in " + outGap.quarter + ".";
end

function [rules, vsRange, text] = rulesPart(infl, outGap, rangeNow)
% Policy rules: neutral real rate + inflation + 0.5 x (inflation - 2) + b x output gap,
% with b = 0.5 (Taylor 1993) or 1 (balanced approach), against the actual range
rules = {};
vsRange = "";
rangeText = fomc.util.rangeText(rangeNow.lower, rangeNow.upper);
if isempty(fieldnames(infl)) || isempty(fieldnames(outGap))
    text = "Policy rules cannot be worked out without core inflation and the output gap. " + ...
        targetIs(rangeNow) + rangeText + ".";
    return
end
names = ["Taylor (1993)", "balanced approach"];
weights = [0.5, 1];
neutral = [0.5, 2];
values = zeros(2, 2);
for i = 1:2
    for j = 1:2
        values(i, j) = neutral(j) + infl.value + 0.5 * (infl.value - 2) + weights(i) * outGap.value;
        rules{end+1, 1} = struct("rule", names(i), "neutralRealRate", neutral(j), "value", round(values(i, j), 2)); %#ok<AGROW>
    end
end
[vsRange, where] = compareWithRange(values(:), rangeNow);
text = "Policy rules put the federal funds rate at " + pct(values(1, 1)) + " (Taylor 1993) or " + ...
    pct(values(2, 1)) + " (balanced approach) with a neutral real rate of 0.5%, and " + pct(values(1, 2)) + ...
    " or " + pct(values(2, 2)) + " with 2%. " + targetIs(rangeNow) + rangeText + ", " + where + ".";
if any(values(:) < 0)
    text = text + " A rule below zero cannot be followed: the Fed cannot set the range lower than 0 to 1/4 percent.";
end
end

function [market, text, twoYearText, series] = marketPart(D, asOf, rangeNow)
% What markets expect: the 6-month bill against the effective rate (the next few meetings;
% fomc.data.billSignal) and the
% 2-year Treasury yield (the next two years) against the middle of the range. The 2-year counts
% as pointing to moves beyond 0.25 point. Its sentence is returned apart, as background.
market = struct();
series = {};
text = strings(1, 0);
twoYearText = strings(1, 0);
b = fomc.data.billSignal(D, asOf, rangeNow);
if ~isempty(fieldnames(b))
    market.sixMonthBill = b.yield;
    market.billDate = b.date;
    market.effectiveRate = b.effectiveRate;
    market.billAboveEffectiveRate = round(b.gap, 2);
    market.billSuggests = b.suggests;
    series{end+1, 1} = struct("seriesId", "DGS6MO", "date", b.date, "value", b.yield);
    if b.effectiveDate ~= ""
        series{end+1, 1} = struct("seriesId", "DFF", "date", b.effectiveDate, "value", b.effectiveRate);
    end
    text(end+1) = "The 6-month Treasury bill yield was " + pct(b.yield) + " on " + b.date + ", " + ...
        points(b.gap) + aboveBelow(b.gap) + baseWords(b) + ", which suggests markets expect " + b.suggests + ...
        " (the next few meetings).";
end
Y = known(D, "DGS2", asOf);
if isempty(Y)
    return
end
spread = Y.value(end) - (rangeNow.lower + rangeNow.upper) / 2;
reading = "little change";
if spread > 0.25
    reading = "increases";
elseif spread < -0.25
    reading = "cuts";
end
market.twoYearYield = Y.value(end);
market.date = fomc.util.fmtDate(Y.date(end));
market.aboveMiddleOfRange = round(spread, 2);
market.suggests = reading;
series{end+1, 1} = struct("seriesId", "DGS2", "date", market.date, "value", Y.value(end));
twoYearText = "The 2-year Treasury yield was " + pct(Y.value(end)) + " on " + market.date + ", " + ...
    points(spread) + aboveBelow(spread) + " the middle of the range, which suggests markets expect " + reading + ...
    " over the next two years.";
end

function t = baseWords(b)
% " the effective fed funds rate (3.9%)", or the middle of the range when that rate is missing
t = " the middle of the range";
if b.effectiveDate ~= ""
    t = " the effective fed funds rate (" + pct(b.effectiveRate) + ")";
end
end

function [part, text] = minutesPart(D, asOf, rangeNow)
% The latest minutes public on the anchor date: what participants said about future rate moves,
% quoting the most widely held view and the leading one in another direction, and how the staff
% revised its forecast
part = struct();
M = D.meetings;
k = find(M.ReleaseDate <= asOf, 1, "last");
if isempty(k)
    text = "No minutes were public on this date.";
    return
end
V = fomc.data.policyViews(D, k);
F = fomc.data.forecastRevisions(D, k);
dir = fomc.data.minutesDirection(D, k, rangeNow);
part = struct("meetingDate", V.meetingDate, "releaseDate", fomc.util.fmtDate(M.ReleaseDate(k)), "lean", V.lean, ...
    "directionSource", dir.source, "aiRatePathScore", dir.score);
text = "In the minutes of the " + V.meetingDate + " meeting (released " + part.releaseDate + "), ";
if dir.source == "ai"
    % The AI read the minutes and scored the rate path; quote the sentences it cited
    text = text + "the AI scored the rate path " + string(sprintf("%+.2f", dir.score)) + ...
        " on its scale from -1 (dovish) to +1 (hawkish), " + aiWords(dir.way, rangeNow) + ".";
    quoted = cellfun(@(e) struct("share", "", "lean", dir.way, "conditional", false, ...
        "text", cutMark(string(e.quote)), "id", string(e.paragraph_ref)), dir.evidence(1:min(2, end)), UniformOutput=false);
else
    text = text + "participants' views on future meetings " + leanWords(V.lean, V.leanShare, rangeNow) + ".";
    quoted = pickViews(V.views);
end
part.views = cellfun(@(v) struct("share", v.share, "lean", v.lean, "conditional", v.conditional, ...
    "text", v.text, "id", v.id), quoted, UniformOutput=false);
for i = 1:numel(quoted)
    text = text + " """ + quoted{i}.text + """ [" + quoted{i}.id + "]";
end
% The staff's forecast at the same meeting, against the meeting before
staff = strings(1, 0);
words = struct("inflation", ["higher", "lower"], "activity", ["stronger", "weaker"]);
subjects = struct("inflation", "inflation", "activity", "growth and spending");
for t = ["inflation", "activity"]
    w = F.(t)(1);
    if w == ""
        continue
    end
    w(w == "higher") = words.(t)(1);
    w(w == "lower") = words.(t)(2);
    part.staffForecast.(t) = struct("revision", w, "id", F.(t + "Id")(1));
    if w == "about the same"
        staff(end+1) = "left its " + subjects.(t) + " forecast about the same [" + F.(t + "Id")(1) + "]"; %#ok<AGROW>
    elseif w == "mixed"
        staff(end+1) = "revised its " + subjects.(t) + " forecast both ways [" + F.(t + "Id")(1) + "]"; %#ok<AGROW>
    else
        staff(end+1) = "revised its " + subjects.(t) + " forecast " + w + " [" + F.(t + "Id")(1) + "]"; %#ok<AGROW>
    end
end
if ~isempty(staff)
    text = text + " At that meeting the Fed staff " + strjoin(staff, " and ") + " than at the meeting before.";
end
% A meeting held since then has a decision but no public minutes yet
later = find(M.MeetingDate <= asOf & M.ReleaseDate > asOf, 1, "last");
if ~isempty(later)
    part.laterMeeting = fomc.util.fmtDate(M.MeetingDate(later));
    text = text + " The " + part.laterMeeting + " meeting has been held, but its minutes are not public until " + ...
        fomc.util.fmtDate(M.ReleaseDate(later)) + ".";
end
end

function quoted = pickViews(views)
% The most widely held view, and the leading view in another direction (else the next one)
quoted = {};
if isempty(views)
    return
end
quoted = views(1);
dirs = cellfun(@(v) erase(v.lean, "slower "), views);
other = find(dirs ~= dirs(1), 1);
if isempty(other) && numel(views) > 1
    other = 2;
end
if ~isempty(other)
    quoted{2} = views{other};
end
end

function q = cutMark(q)
% The skill keeps quotes to 40 words, so a long sentence stops partway: mark where
if ~endsWith(q, [".", "?", "!", """", ")", ":", ";"])
    q = q + "...";
end
end

function t = aiWords(way, rangeNow)
% What the AI's rate-path direction means, in words
switch way
    case "up"
        t = "a lean toward further increases";
    case "down"
        t = "a lean toward cuts";
    otherwise
        t = "a lean toward holding the rate where it is for now";
        if rangeNow.upper <= 0.25
            t = "no lean the rate itself can follow, as it is already at its lowest";
        end
end
end

function t = leanWords(lean, share, rangeNow)
% The lean of the minutes in words, and whose view gave it. Near zero, a lean to cuts means
% more support for the economy, since the range cannot go lower.
nearZero = rangeNow.upper <= 0.25;
switch lean
    case "increases"
        t = "lean toward further increases";
    case "slower increases"
        t = "lean toward further increases at a slower pace";
    case {"cuts", "slower cuts"}
        if nearZero
            t = "lean toward more support for the economy, by means other than the rate, which was already at its lowest";
        elseif lean == "cuts"
            t = "lean toward cuts";
        else
            t = "lean toward further cuts at a slower pace";
        end
    case "hold"
        t = "lean toward keeping the rate where it is for now";
    case "divided"
        t = "are divided between increases and cuts";
    case "depends on the data"
        t = "tie the next moves to the data, with no clear lean";
    otherwise
        t = "say nothing about future rate moves that the code can read";
end
% "(the view of most participants)"; "most of those" is most of a group named just before
if share == "participants"
    t = t + " (the view of participants generally)";
elseif share ~= "" && ~any(lean == ["divided", "depends on the data"])
    t = t + " (the view of " + replace(share, " of those", "") + " participants)";
end
end

function T = known(D, id, asOf)
% A series as known on the anchor date; empty if none is
[T, ~] = fomc.data.valueAsOf(D, id, asOf);
end

function c = change12(T, i)
% Percent change over the 12 months to row i of a monthly series; NaN if that month is missing
c = NaN;
if isempty(i)
    return
end
k = find(T.date == T.date(i) - calmonths(12), 1);
if ~isempty(k)
    c = 100 * (T.value(i) / T.value(k) - 1);
end
end

function w = trend(nowValue, earlier)
% "rising", "falling" or "steady" (within 0.1 point) against three months earlier; "" if
% the earlier value is missing
w = "";
if isnan(earlier)
    return
elseif nowValue - earlier > 0.1
    w = "rising";
elseif nowValue - earlier < -0.1
    w = "falling";
else
    w = "steady";
end
end

function t = trendText(w, earlier)
% ", and falling (3.2% three months earlier)", or nothing when the earlier value is missing
t = "";
if w ~= ""
    t = ", and " + w + " (" + pct(earlier) + " three months earlier)";
end
end

function [label, words] = compareWithRange(values, rangeNow)
% Where the rules sit against the range: "above", "below", "within" or "mixed", and the
% range compared with them in words
nAbove = sum(values > rangeNow.upper);
nBelow = sum(values < rangeNow.lower);
nWithin = numel(values) - nAbove - nBelow;
if nAbove == numel(values)
    label = "above";
    words = "below all four";
elseif nBelow == numel(values)
    label = "below";
    words = "above all four";
elseif nWithin == numel(values)
    label = "within";
    words = "around all four";
else
    % "with 3 rules above it and 1 within it"
    label = "mixed";
    counts = [nAbove, nWithin, nBelow];
    places = ["above it", "within it", "below it"];
    parts = counts(counts > 0) + " " + places(counts > 0);
    noun = " rules ";
    if counts(find(counts > 0, 1)) == 1
        noun = " rule ";
    end
    parts(1) = regexprep(parts(1), "^(\d+) ", "$1" + noun, "once");
    words = "with " + strjoin(parts(1:end-1), ", ") + " and " + parts(end);
end
end

function t = targetIs(rangeNow)
% "The target range is " since December 2008, "The target is " for the single target before
t = "The target range is ";
if rangeNow.lower == rangeNow.upper
    t = "The target is ";
end
end

function t = pct(x)
% 3.012 -> "3.0%"
t = string(sprintf("%.1f%%", x));
end

function t = points(x)
% The size of a difference: 1.012 -> "1.0 point", 0.19 -> "0.2 point", 2.5 -> "2.5 points"
t = string(sprintf("%.1f", abs(x)));
if round(abs(x), 1) > 1
    t = t + " points";
else
    t = t + " point";
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

function t = monthName(d)
% 2026-08-01 -> "August 2026"
t = string(d, "MMMM yyyy");
end

function t = quarter(d)
% 2026-04-01 -> "2026 Q2"
t = string(d.Year) + " Q" + string(ceil(d.Month / 3));
end
