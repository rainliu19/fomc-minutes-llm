function r = getSnapshot(ctx, args)
%GETSNAPSHOT Latest value known on the anchor date for each core series.

% Pick the group of core series (or all of them)
group = string(fomc.tools.getArg(args, "group", "all"));
G = fomc.data.coreGroups();
groups = unique(G.group, "stable");
if ~any(group == [groups; "all"])
    r = fomc.tools.fail("'group' must be one of: " + strjoin([groups; "all"], ", ") + ".");
    return
end
if group ~= "all"
    G = G(G.group == group, :);
end

% Take each series' latest value known on the anchor date; set aside series with no data yet or that stopped long ago
staleDays = 400;
rows = {};
stale = strings(0, 1);
none = strings(0, 1);
for i = 1:height(G)
    id = G.series_id(i);
    [T, ~] = fomc.data.valueAsOf(ctx.D, id, ctx.asOf);
    if isempty(T)
        none(end+1, 1) = id; %#ok<AGROW>
        continue
    end
    age = days(ctx.asOf - T.date(end));
    if age > staleDays
        stale(end+1, 1) = id; %#ok<AGROW>
        continue
    end
    % Build the row for this series
    k = ctx.D.dict.series_id == id;
    row = struct("seriesId", id, "group", G.group(i), "label", string(ctx.D.dict.label(k)), ...
        "units", unitsOf(ctx.D.dict, k), "date", fomc.util.fmtDate(T.date(end)), ...
        "value", T.value(end), "availableDate", fomc.util.fmtDate(T.availableDate(end)), ...
        "ageDays", age);
    % Add the year-over-year change for series where it is meaningful
    if G.yoy(i)
        y = fomc.data.transformSeries(T, "yoy_pct");
        row.yoyPct = y(end);
    end
    rows{end+1, 1} = row; %#ok<AGROW>
end
% Report the set-aside series separately so the model does not guess
r = struct("anchorDate", fomc.util.fmtDate(ctx.asOf), "group", group, "series", {rows});
if ~isempty(none)
    r.noDataKnownYet = none;
end
if ~isempty(stale)
    r.discontinuedOrStale = stale;
end
end

function u = unitsOf(dict, k)
% Units text, or empty if the data dictionary has none
u = "";
if ismember("units", string(dict.Properties.VariableNames)) && ~ismissing(dict.units(k))
    u = string(dict.units(k));
end
end
