function [text, recs] = dataPrefetch(ctx, question)
%DATAPREFETCH The latest figures for the data a question is about, looked up before the model starts.
%   [text, recs] = fomc.focus.dataPrefetch(ctx, question)
%   A small model often answers "that data is not available" without looking. So the harness
%   picks the series from the question's wording (fomc.focus.dataTopics) and reads each one as
%   known on the anchor date (fomc.data.valueAsOf): the latest value, and the value 3 and 12
%   months earlier. text goes in front of the question; recs is the record for the trace and
%   the figure check. Questions about no data topic get nothing.

text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch
    return
end
ids = fomc.focus.dataTopics(question, ctx.D.dict.series_id);
if isempty(ids)
    return
end

t0 = tic;
names = fomc.data.plainNames();
G = fomc.data.coreGroups();
lines = strings(0, 1);
series = cell(0, 1);
for id = ids.'
    [T, note] = fomc.data.valueAsOf(ctx.D, id, ctx.asOf);
    name = displayName(names, id);
    if isempty(T)
        lines(end+1, 1) = "- " + name + " (" + id + "): no value was public yet on this date. " + note; %#ok<AGROW>
        continue
    end
    latest = T(end, :);
    ago12 = nearest(T, latest.date - calyears(1));
    ago3 = nearest(T, latest.date - calmonths(3));
    line = "- " + name + " (" + id + "): " + fmt(latest.value, ctx.D.dict, id) + " on " + fomc.util.fmtDate(latest.date);
    if days(ctx.asOf - latest.date) > 400
        line = line + " (an old value: this series has not been updated since)";
    end
    rows = {struct("date", fomc.util.fmtDate(latest.date), "value", latest.value)};
    if ~isempty(ago3)
        line = line + "; " + fmt(ago3.value, ctx.D.dict, id) + " three months earlier";
        rows{end+1} = struct("date", fomc.util.fmtDate(ago3.date), "value", ago3.value); %#ok<AGROW>
    end
    if ~isempty(ago12)
        line = line + "; " + fmt(ago12.value, ctx.D.dict, id) + " a year earlier";
        rows{end+1} = struct("date", fomc.util.fmtDate(ago12.date), "value", ago12.value); %#ok<AGROW>
        if any(G.series_id == id & G.yoy)
            yoy = 100 * (latest.value / ago12.value - 1);
            line = line + sprintf(" (%+.1f%% over the year)", yoy);
        end
    end
    lines(end+1, 1) = line + "."; %#ok<AGROW>
    series{end+1, 1} = struct("seriesId", id, "label", name, "rows", {rows}); %#ok<AGROW>
end

result = struct("anchorDate", fomc.util.fmtDate(ctx.asOf), "series", {series});
json = string(jsonencode(result));
check = fomc.guard.checkToolOutput(ctx, result, json);
if ~check.ok || isempty(lines)
    return
end
text = "[Latest figures found by code, as known on " + fomc.util.fmtDate(ctx.asOf) + ". Use them; call getSeries only for something not listed:" + ...
    newline + strjoin(lines, newline) + "]";
recs(end+1) = struct("name", "prefetchData", "args", struct("series", strjoin(ids, ",")), ...
    "result", json, "ok", true, "ms", round(toc(t0) * 1000));
fomc.trace.logEvent(ctx, "prefetch", struct("kind", "data", "series", strjoin(ids, ",")));
end

function n = displayName(names, id)
k = find(names.series_id == id, 1);
if isempty(k)
    n = id;
else
    n = regexprep(names.name(k), "^the ", "");
end
end

function row = nearest(T, target)
% The observation closest to a date, if it is within 45 days of it.
[d, i] = min(abs(days(T.date - target)));
if d <= 45
    row = T(i, :);
else
    row = [];
end
end

function s = fmt(v, dict, id)
% A number with its unit when the dictionary says percent.
if abs(v) >= 1000
    s = sprintf("%.0f", v);
else
    s = sprintf("%.4g", v);
end
if ismember("units", string(dict.Properties.VariableNames))
    u = string(dict.units(dict.series_id == id));
    if ~isempty(u) && ~ismissing(u(1)) && startsWith(u(1), "Percent") && ~contains(u(1), "Change", IgnoreCase=false)
        s = s + "%";
    end
end
end
