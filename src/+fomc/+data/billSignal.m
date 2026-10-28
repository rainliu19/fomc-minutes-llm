function b = billSignal(D, asOf, rangeNow)
%BILLSIGNAL What the 6-month Treasury bill suggests markets expect over the next few meetings.
%   b = fomc.data.billSignal(D, asOf, rangeNow)
%   The latest 6-month bill yield (DGS6MO) known on asOf against the daily effective fed funds
%   rate (DFF) known then; rangeNow (a row of fomc.data.ratePath levels) is kept for callers
%   and used only if the effective rate is missing, against the middle of the range. b: yield,
%   date, effectiveRate, gap (bill minus the effective rate), suggests ("an increase soon", "a
%   cut soon" or "no change soon"; a move counts beyond 0.275 point) and way ("up", "down" or
%   "hold"). Empty struct when no bill yield is known. Fed funds futures, the usual measure,
%   are not in this data.
%
%   Chosen without looking at 2019 on: of five measures (the 1-, 3- and 6-month bills against
%   the effective rate, the 3- and 6-month bills against the middle of the range), each with its
%   cutoff fitted on the minutes released before the 87 meetings of 2008 to 2018, this one fitted
%   those best (93%). Then tested on the 62 meetings from 2019 on (22 moves; a hold every time
%   would be right 65%): right 84%, 14 moves caught, 2 moves called that did not happen. The
%   earlier rule, the 3-month bill against the middle of the range beyond 0.15, was right 79%
%   with 14 caught and 5 false. A 3-month yield moves only about 0.1 point for a cut at the next
%   meeting, so cuts mostly read as no change; the 6-month spans more meetings and moves more.

b = struct();
[B, ~] = fomc.data.valueAsOf(D, "DGS6MO", asOf);
B = B(~isnan(B.value), :);
if isempty(B)
    return
end
[F, ~] = fomc.data.valueAsOf(D, "DFF", asOf);
F = F(~isnan(F.value), :);
if isempty(F)
    base = (rangeNow.lower + rangeNow.upper) / 2;
    baseDate = "";
else
    base = F.value(end);
    baseDate = fomc.util.fmtDate(F.date(end));
end
gap = B.value(end) - base;
b = struct("yield", B.value(end), "date", fomc.util.fmtDate(B.date(end)), "effectiveRate", base, ...
    "effectiveDate", baseDate, "gap", gap, "suggests", "no change soon", "way", "hold");
if gap > 0.275
    b.suggests = "an increase soon";
    b.way = "up";
elseif gap < -0.275
    b.suggests = "a cut soon";
    b.way = "down";
end
end
