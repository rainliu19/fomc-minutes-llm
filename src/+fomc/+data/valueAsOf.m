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

% Start with an empty result and a note that explains why, if it stays empty
T = table(datetime.empty(0,1), zeros(0,1), datetime.empty(0,1), ...
    VariableNames=["date","value","availableDate"]);
note = "";

% Look up this series' publication rule
k = D.avail.series_id == seriesId;
if ~any(k)
    note = "Unknown series '" + seriesId + "'.";
    return
end
rule = D.avail.rule(k);
param = D.avail.param(k);

% Three cases: excluded series, revised series (vintages), all other series (publication lag)
switch rule
    case "exclude"
        note = seriesId + " is excluded: " + D.avail.note(k);
        return

    case "vintage"
        v = D.vint;
        mine = v.series_id == seriesId;
        if ~any(mine)
            note = "No vintage history is stored for " + seriesId + ".";
            return
        end
        % Keep only vintage rows that existed by the anchor date
        first = min(v.rtStart(mine));
        s = v(mine & v.rtStart <= asOf & v.date <= asOf, :);
        if isempty(s)
            note = "No real-time values of " + seriesId + " exist before " + ...
                fomc.util.fmtDate(first) + ", so none are known on " + ...
                fomc.util.fmtDate(asOf) + ".";
            return
        end
        % s is sorted by date then rtStart, so the last row per date is the latest
        % For each observation keep its latest vintage (and drop observations later removed)
        [~, ia] = unique(s.date, "last");
        s = s(ia, :);
        keep = s.rtEnd >= asOf | s.hasNext;
        s = s(keep, :);
        T = table(s.date, s.value, s.rtStart, VariableNames=T.Properties.VariableNames);
        if asOf < first + years(1)
            note = "Real-time history of " + seriesId + " starts " + ...
                fomc.util.fmtDate(first) + "; earlier observations may be missing.";
        end

    otherwise
        % Other series: a value is known once its publication lag has passed
        if ~ismember(seriesId, string(D.wide.Properties.VariableNames))
            note = "No data is stored for " + seriesId + ".";
            return
        end
        col = D.wide.(seriesId);
        has = ~isnan(col);
        obs = D.wide.date(has);
        val = col(has);
        av = fomc.data.availableDate(rule, param, obs);
        keep = av <= asOf & obs <= asOf;
        T = table(obs(keep), val(keep), av(keep), VariableNames=T.Properties.VariableNames);
        if isempty(T)
            note = "No observations of " + seriesId + " were known on " + ...
                fomc.util.fmtDate(asOf) + ".";
        end
end
% Oldest first
T = sortrows(T, "date");
end
