function [T, note] = valueAsOf(D, seriesId, asOf)
%VALUEASOF A series as publicly known on a date.
%   [T, note] = fomc.data.valueAsOf(D, seriesId, asOf)
%   T: date, value, availableDate, sorted by date. note: why T is empty or limited, else "".
%
%   Vintaged series: per observation, the row with the latest rtStart on or before asOf.
%   A row past its rtEnd is kept if a later row exists (a gap in the vintage history) and
%   dropped if nothing follows (observation removed). Other series: known once
%   availableDate <= asOf. Observations dated after asOf are always dropped.

arguments
    D (1,1) struct
    seriesId (1,1) string
    asOf (1,1) datetime
end

% Early exits return an empty result with a note that says why
names = ["date", "value", "availableDate"];
T = [];
note = "";

% Look up this series' publication rule (found once, in fomc.data.seriesIndex)
if ~isfield(D.series, seriesId)
    note = "Unknown series '" + seriesId + "'.";
    T = emptyResult(names);
    return
end
e = D.series.(seriesId);

% Three cases: excluded series, revised series (vintages), all other series (publication lag)
switch e.rule
    case "exclude"
        note = seriesId + " is excluded: " + e.note;
        T = emptyResult(names);
        return

    case "vintage"
        v = e.rows;
        if isempty(v)
            note = "No vintage history is stored for " + seriesId + ".";
            T = emptyResult(names);
            return
        end
        % Keep only vintage rows that existed by the anchor date
        first = min(v.rtStart);
        s = v(v.rtStart <= asOf & v.date <= asOf, :);
        if isempty(s)
            note = "No real-time values of " + seriesId + " exist before " + ...
                fomc.util.fmtDate(first) + ", so none are known on " + ...
                fomc.util.fmtDate(asOf) + ".";
            T = emptyResult(names);
            return
        end
        % s is sorted by date then rtStart, so the last row per date is the latest
        % For each observation keep its latest vintage (and drop observations later removed)
        [~, ia] = unique(s.date, "last");
        s = s(ia, :);
        keep = s.rtEnd >= asOf | s.hasNext;
        s = s(keep, :);
        T = table(s.date, s.value, s.rtStart, VariableNames=names);
        if asOf < first + years(1)
            note = "Real-time history of " + seriesId + " starts " + ...
                fomc.util.fmtDate(first) + "; earlier observations may be missing.";
        end

    otherwise
        % Other series: a value is known once its publication lag has passed
        if ~e.stored
            note = "No data is stored for " + seriesId + ".";
            T = emptyResult(names);
            return
        end
        keep = e.avail <= asOf & e.obs <= asOf;
        T = table(e.obs(keep), e.val(keep), e.avail(keep), VariableNames=names);
        if isempty(T)
            note = "No observations of " + seriesId + " were known on " + ...
                fomc.util.fmtDate(asOf) + ".";
        end
end
% T is already oldest first: the vintage rows come out of unique(date) and the other series are sorted in the index
end

function T = emptyResult(names)
T = table(datetime.empty(0,1), zeros(0,1), datetime.empty(0,1), VariableNames=names);
end
