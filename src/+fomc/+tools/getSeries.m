function r = getSeries(ctx, args)
%GETSERIES Values of up to 5 series exactly as they were known on the anchor date.

% Read the list of series ids (commas or spaces), 1 to 5 of them
raw = string(fomc.tools.getArg(args, "seriesIds", ""));
ids = split(regexprep(strjoin(raw(:), ","), "[\s;]+", ","), ",");
ids = unique(ids(ids ~= ""), "stable");
if isempty(ids) || numel(ids) > 5
    r = fomc.tools.fail("'seriesIds' must list 1 to 5 series ids separated by commas, for example 'DGS10,DGS2'.");
    return
end
% Check the transform and the dates
transform = string(fomc.tools.getArg(args, "transform", "level"));
if ~any(transform == ["level", "diff_1", "yoy_pct"])
    r = fomc.tools.fail("'transform' must be 'level', 'diff_1' or 'yoy_pct'.");
    return
end
startDate = fomc.util.parseDate(fomc.tools.getArg(args, "startDate", ""));
endDate = fomc.util.parseDate(fomc.tools.getArg(args, "endDate", ""));

% Row limits: the latest 24 by default, up to 120 when a start date is given
maxRows = 120;
defaultRows = 24;
out = cell(numel(ids), 1);
% For each series: values as known on the anchor date, transformed, then trimmed
for i = 1:numel(ids)
    id = ids(i);
    k = ctx.D.dict.series_id == id;
    % Unknown id: tell the model which ids exist
    if ~any(k)
        out{i} = struct("seriesId", id, "error", "Unknown seriesId. Valid ids: " + strjoin(ctx.D.dict.series_id, ", ") + ".");
        continue
    end
    % Point-in-time values (vintage and publication-lag rules applied)
    [T, note] = fomc.data.valueAsOf(ctx.D, id, ctx.asOf);
    s = struct("seriesId", id, "label", string(ctx.D.dict.label(k)), ...
        "units", unitsOf(ctx.D.dict, k), "transform", transform);
    if isempty(T)
        s.rows = {};
        s.note = note;
        out{i} = s;
        continue
    end
    % Apply the transform, drop empty values, keep the requested dates
    T.value = fomc.data.transformSeries(T, transform);
    T = T(~isnan(T.value), :);
    keep = true(height(T), 1);
    if ~isnat(startDate), keep = keep & T.date >= startDate; end
    if ~isnat(endDate), keep = keep & T.date <= endDate; end
    T = T(keep, :);
    % Keep only the most recent rows, up to the cap
    cap = maxRows;
    if isnat(startDate)
        cap = defaultRows;
    end
    if height(T) > cap
        T = T(end - cap + 1:end, :);
    end
    % Format each row, including the date its value became public
    rows = cell(height(T), 1);
    for j = 1:height(T)
        rows{j} = struct("date", fomc.util.fmtDate(T.date(j)), "value", T.value(j), ...
            "availableDate", fomc.util.fmtDate(T.availableDate(j)));
    end
    s.rows = rows;
    if strlength(note) > 0
        s.note = note;
    end
    out{i} = s;
end
r = struct("anchorDate", fomc.util.fmtDate(ctx.asOf), "series", {out});
end

function u = unitsOf(dict, k)
% Units text, or empty if the data dictionary has none
u = "";
if ismember("units", string(dict.Properties.VariableNames)) && ~ismissing(dict.units(k))
    u = string(dict.units(k));
end
end
