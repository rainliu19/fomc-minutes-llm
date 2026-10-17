function brief = dataBrief(ctx)
%DATABRIEF Compact text of the key data as known on the anchor date.
%   brief = fomc.dataBrief(ctx)
%   Run by the harness before the first model call, through dispatch (so guardrails and
%   trace apply). Shows only the series marked brief in fomc.data.coreGroups: every line
%   is read again at the start of each session.

% Ask for the snapshot through the normal tool path
[json, rec] = fomc.tools.dispatch(ctx, "getSnapshot", struct("group", "all"));
if ~rec.ok
    brief = "(The data snapshot could not be built: " + json + ")";
    return
end
r = jsondecode(json);
rows = r.series;
if isempty(rows)
    brief = "(No data was known on this date.)";
    return
end
if isstruct(rows)
    rows = num2cell(rows);
end

% Keep only the key series, one line each
G = fomc.data.coreGroups();
names = fomc.data.plainNames();
show = G.series_id(G.brief);
lines = strings(0, 1);
for i = 1:numel(rows)
    s = rows{i};
    if ~any(string(s.seriesId) == show)
        continue
    end
    % Add the year-over-year change when the snapshot has one
    yoy = "";
    if isfield(s, "yoyPct") && ~isempty(s.yoyPct)
        yoy = sprintf(", %+.1f%% y/y", s.yoyPct);
    end
    lines(end+1, 1) = sprintf("- %s (%s): %s%s [%s]", plainName(names, s.seriesId, s.label), s.seriesId, ...
        fmtNumber(s.value), yoy, s.date); %#ok<AGROW>
end
% Join the lines into one block of text
if isempty(lines)
    brief = "(No key series were known on this date.)";
else
    brief = strjoin(lines, newline);
end
end

function s = fmtNumber(v)
if abs(v) >= 1000
    s = sprintf("%.0f", v);
else
    s = sprintf("%.4g", v);
end
end

function n = plainName(names, id, fallback)
% The everyday name of a series (the dictionary label if there is none).
k = find(names.series_id == string(id), 1);
if isempty(k)
    n = fallback;
else
    n = regexprep(names.name(k), "^the ", "");
end
end
