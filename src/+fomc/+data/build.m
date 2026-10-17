function D = build(wide, vint, dict, avail, minutes)
%BUILD Assemble the agent's data struct from its five tables.
%   D = fomc.data.build(wide, vint, dict, avail, minutes)
%   wide: macro_market_wide.csv. vint: fred_vintages_long.csv. dict: series_dictionary.csv.
%   avail: series_availability.csv. minutes: fomc_minutes.csv.
%   Separate from fomc.data.load so tests can pass small synthetic tables.

arguments
    wide table
    vint table
    dict table
    avail table
    minutes table
end

% Sort vintage rows; hasNext flags whether a later row exists for the same observation.
vint = sortrows(vint, ["series_id","date","rtStart"]);
n = height(vint);
sameNext = false(n, 1);
sameNext(1:n-1) = vint.series_id(1:n-1) == vint.series_id(2:n) & ...
    vint.date(1:n-1) == vint.date(2:n);
vint.hasNext = sameNext;

% Order the minutes by meeting and turn missing text into empty text
minutes = sortrows(minutes, "MeetingDate");
textCols = setdiff(string(minutes.Properties.VariableNames), ["MeetingDate","ReleaseDate"]);
for c = textCols
    if isstring(minutes.(c))
        minutes.(c)(ismissing(minutes.(c))) = "";
    end
end

% Collect everything into one struct; split the minutes into numbered paragraphs
D.wide = wide;
D.vint = vint;
D.dict = dict;
D.avail = avail;
D.meetings = minutes;
D.paras = fomc.data.splitParagraphs(minutes);
% Paragraph ids like 2020-03-15/policyAction/12: the model cites them, the harness turns them back into text.
D.paras.id = fomc.util.fmtDate(minutes.MeetingDate(D.paras.meetingIdx)) + "/" + ...
    D.paras.section + "/" + D.paras.paraIdx;
% One decision card per meeting, read from the text by code
D.cards = fomc.data.decisionCards(minutes, D.paras);
end
