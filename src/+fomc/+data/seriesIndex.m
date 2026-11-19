function X = seriesIndex(wide, vint, avail)
%SERIESINDEX Each series' rows and publication dates, found once so valueAsOf only filters by date.
%   X = fomc.data.seriesIndex(wide, vint, avail)
%   X.<series id>: rule, note, and for a vintaged series its vintage rows (in file order); for any
%   other series (stored: it has a column) the dated values with the date each became public (obs, val, avail). Built with
%   the data (fomc.data.build); fomc.data.valueAsOf reads it.

X = struct();
byId = findgroups(vint.series_id);
vintIds = vint.series_id(arrayfun(@(g) find(byId == g, 1), 1:max([byId; 0])));
names = string(wide.Properties.VariableNames);
for k = 1:height(avail)
    id = avail.series_id(k);
    e = struct("rule", avail.rule(k), "note", avail.note(k), "rows", [], "stored", false, "obs", [], "val", [], "avail", []);
    if e.rule == "vintage"
        if ismember(id, vintIds)
            e.rows = vint(vint.series_id == id, :);
        end
    elseif e.rule ~= "exclude" && ismember(id, names)
        e.stored = true;
        col = wide.(id);
        has = ~isnan(col);
        [e.obs, o] = sort(wide.date(has));      % oldest first, so valueAsOf need not sort
        v = col(has);
        e.val = v(o);
        e.avail = fomc.data.availableDate(e.rule, avail.param(k), e.obs);
    end
    X.(id) = e;
end
end
