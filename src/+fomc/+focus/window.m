function w = window(question, asOf, cfg)
%WINDOW Default span of minutes for a question. A default, not a limit.
%   w = fomc.focus.window(question, asOf, cfg), with w: start, end, years, reason, and
%   fromQuestion (true if the question named a year, false for the default span).
%
%   From years in the question (2008 or later, not after the anchor year):
%     none          the last cfg.focusYears years up to the anchor date
%     one (2012)    the cfg.focusYears years ending 2012-12-31
%     several       January 1 of the earliest to December 31 of the latest
%   Never later than the anchor. Searches use it unless the model passes dates; the
%   anchor-date rule always applies.

arguments
    question (1,1) string
    asOf (1,1) datetime
    cfg (1,1) struct
end

% Years named in the question (2008 or later, not after the anchor year)
found = regexp(question, "(?<!\d)(20[0-2]\d)(?!\d)", "match");
years = unique(double(string(found)));
years = years(years >= 2008 & years <= year(asOf));

% No year: the last few years. One year: the few years ending then. Several: the whole span
if isempty(years)
    endDate = asOf;
    startDate = endDate - calyears(cfg.focusYears) + days(1);
    reason = "no year in the question, so the most recent " + cfg.focusYears + " years";
elseif isscalar(years)
    endDate = min(asOf, datetime(years, 12, 31));
    startDate = endDate - calyears(cfg.focusYears) + days(1);
    reason = "the question mentions " + years + ", so the " + cfg.focusYears + " years ending then";
else
    endDate = min(asOf, datetime(max(years), 12, 31));
    startDate = datetime(min(years), 1, 1);
    reason = "the question mentions " + strjoin(string(years), ", ") + ", so that whole span";
end
w = struct("start", dateshift(startDate, "start", "day"), "end", dateshift(endDate, "start", "day"), ...
    "years", cfg.focusYears, "reason", reason, "fromQuestion", ~isempty(years));
end
