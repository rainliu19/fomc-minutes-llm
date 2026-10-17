function D = syntheticData()
%SYNTHETICDATA Tiny made-up data set for unit tests. Never mixed with real data.

% Short helpers for dates
dt = @(y,m,d) datetime(y,m,d);
never = datetime(9999,12,31);

% Vintage history. UNRATE: January 2020 revised 2020-03-06. GAPS: a hole in the history.
% GONE: an observation later removed. PROJ: dated after its vintage.
% Revision history for four made-up series (see the line above)
series_id = ["UNRATE";"UNRATE";"UNRATE";"UNRATE";"GAPS";"GAPS";"GONE";"PROJ"];
date      = [dt(2020,1,1); dt(2020,1,1); dt(2020,2,1); dt(2020,3,1); dt(2020,1,1); dt(2020,1,1); dt(2020,1,1); dt(2021,1,1)];
value     = [3.5; 3.6; 3.5; 4.4; 1; 2; 5; 9];
rtStart   = [dt(2020,2,7); dt(2020,3,6); dt(2020,3,6); dt(2020,4,3); dt(2020,2,1); dt(2020,2,20); dt(2020,2,1); dt(2020,2,1)];
rtEnd     = [dt(2020,3,5); never; never; never; dt(2020,2,10); never; dt(2020,2,28); never];
vint = table(date, series_id, value, rtStart, rtEnd);

% Unrevised series.
% Plain daily series with a few values, to test publication lags
d = (dt(2020,1,1):days(1):dt(2020,3,15)).';
wide = table(d, nan(numel(d),1), nan(numel(d),1), nan(numel(d),1), nan(numel(d),1), ...
    VariableNames=["date","DGS10","UMCSENT","FEDFUNDS","ICSA"]);
wide.DGS10(wide.date == dt(2020,1,2)) = 1.8;
wide.UMCSENT(wide.date == dt(2020,1,1)) = 99.1;
wide.FEDFUNDS(wide.date == dt(2020,2,1)) = 1.58;
wide.ICSA(wide.date == dt(2020,1,4)) = 214000;

% The publication rule for each series: vintage, lag, month-end lag or excluded
avail = table( ...
    ["UNRATE";"GAPS";"GONE";"PROJ";"DGS10";"UMCSENT";"FEDFUNDS";"ICSA";"USREC"], ...
    ["vintage";"vintage";"vintage";"vintage";"lagdays";"monthend";"monthend";"lagdays";"exclude"], ...
    [0;0;0;0;1;0;1;5;0], ...
    repmat("synthetic", 9, 1), ...
    VariableNames=["series_id","rule","param","note"]);

% A minimal data dictionary
dict = table(avail.series_id, "label of " + avail.series_id, ...
    VariableNames=["series_id","label"]);

% Two meetings; paragraphs separated by newlines.
% Two made-up meetings: one released 2020-02-19, one released 2020-04-08
MeetingDate = [dt(2020,1,29); dt(2020,3,18)];
ReleaseDate = [dt(2020,2,19); dt(2020,4,8)];
URL = ["synthetic";"synthetic"];
ParticipantsViews = [ ...
    "Participants agreed that SYNTHETIC inflation was running below target.\nSome participants saw risks from the SYNTHETIC trade dispute."; ...
    "Participants noted that SYNTHETIC spending had weakened sharply."];
PolicyAction = ["The Committee decided to maintain the target range.";
    "The Committee decided to lower the target range by 50 basis points."];
StaffOutlook = ["The staff projected SYNTHETIC GDP growth of 2 percent."; ""];
% Fill the remaining text columns with empty text, then assemble
minutes = table(MeetingDate, ReleaseDate, URL, ParticipantsViews, PolicyAction, StaffOutlook);
minutes.ParticipantsViews = compose(minutes.ParticipantsViews);
minutes.FinancialMarkets = ["";""];
minutes.StaffEconomy = ["";""];
minutes.StaffFinancial = ["";""];
minutes.SpecialTopics = ["";""];
minutes.Administrative = ["";""];
minutes.Attendance = ["";""];
minutes.Footnotes = ["";""];
minutes.Body = minutes.ParticipantsViews + newline + minutes.PolicyAction;

% Build the same data struct the real agent uses
D = fomc.data.build(wide, vint, dict, avail, minutes);
end
