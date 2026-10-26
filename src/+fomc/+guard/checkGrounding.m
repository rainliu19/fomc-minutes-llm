function r = checkGrounding(structured, ctx, calls, knownIds)
%CHECKGROUNDING Check a structured analysis against what the tools returned.
%   r = fomc.guard.checkGrounding(structured, ctx, calls, knownIds)
%   r.ok, r.failures (in words the model can act on). knownIds: ids from earlier turns.
%
%   evidence: each cited id must exist, belong to minutes public on the anchor date, and
%   have been returned by a tool this session; the harness then supplies the exact quote.
%   dataCited: each figure must match a tool result or the snapshot, within rounding. A
%   getPolicyPath result counts for the rate target on any day it covers.
%   Cannot catch: a real paragraph cited for a claim it does not support.

failures = strings(0, 1);

% Evidence: each cited id must be a real paragraph, public on the anchor date, that a tool
% returned this session (so it cannot be made up).
% Count the evidence items
ev = fomc.util.asCell(fieldOr(structured, "evidence"));
if isempty(ev)
    failures(end+1, 1) = "No evidence was given. Cite at least one paragraph id from a tool result.";
elseif numel(ev) > 6
    failures(end+1, 1) = "Too many evidence items (" + numel(ev) + "). Give at most 4.";
end
% Ids the model may cite: those in this turn's tool results plus earlier turns
known = strings(0, 1);
if ~isempty(calls)
    known = fomc.guard.idsIn(string({calls.result}));
end
if nargin > 3
    known = union(known, knownIds(:));
end
% Check each cited id: present, real, public on the anchor date, and returned by a tool
for i = 1:numel(ev)
    id = string(fieldOr(ev{i}, "id"));
    if isempty(id) || strlength(id) == 0
        failures(end+1, 1) = "Evidence item " + i + " has no paragraph id."; %#ok<AGROW>
        continue
    end
    r = fomc.guard.resolveId(ctx, id);
    if ~r.ok
        failures(end+1, 1) = "Evidence item " + i + " cites '" + id + "' but " + r.reason + ...
            ". Cite ids exactly as getDecision, searchMinutes or readMinutes returned them."; %#ok<AGROW>
    elseif ~any(known == id)
        failures(end+1, 1) = "Evidence item " + i + " cites '" + id + "', which no tool returned in this session. " + ...
            "Cite only ids from tool results."; %#ok<AGROW>
    end
end

% Cited figures
% Check the figures: every (series, date, value) must match what the model was shown
known = knownValues(ctx, calls);
dc = fomc.util.asCell(fieldOr(structured, "dataCited"));
if numel(dc) > 6
    failures(end+1, 1) = "Too many data items (" + numel(dc) + "). List at most 6, only those the summary relies on.";
end
% One data item at a time: needs a number, a known series and date, and a close-enough value
for i = 1:numel(dc)
    c = dc{i};
    id = string(fieldOr(c, "series"));
    date = string(fieldOr(c, "date"));
    value = fieldOr(c, "value");
    if ~isnumeric(value) || isempty(value)
        failures(end+1, 1) = "Data item " + i + " (" + id + ") has no numeric value."; %#ok<AGROW>
        continue
    end
    hit = known.series == id & known.date == date;
    if ~any(hit)
        failures(end+1, 1) = "Data item " + i + ": no " + id + " value for " + date + ...
            " was returned by a tool or is in the snapshot. Call getSeries first, or cite a value you were given."; %#ok<AGROW>
    else
        % Allow for rounding
        tol = max(0.051, 0.001 * abs(value));
        if ~any(abs(known.value(hit) - value) <= tol)
            failures(end+1, 1) = "Data item " + i + ": " + id + " on " + date + " was " + ...
                strjoin(string(unique(known.value(hit))), " or ") + ", not " + value + "."; %#ok<AGROW>
        end
    end
end

% Report: ok only if nothing failed
r = struct("ok", isempty(failures), "failures", failures);
end

function known = knownValues(ctx, calls)
% (series, date, value) triples the model was shown: the snapshot and tool results.
% Start with the snapshot values (and their year-over-year changes)
series = strings(0, 1); date = strings(0, 1); value = zeros(0, 1);

snap = fomc.tools.getSnapshot(ctx, struct("group", "all"));
for i = 1:numel(snap.series)
    s = snap.series{i};
    series(end+1, 1) = s.seriesId; date(end+1, 1) = s.date; value(end+1, 1) = s.value; %#ok<AGROW>
    if isfield(s, "yoyPct") && ~isnan(s.yoyPct)
        series(end+1, 1) = s.seriesId; date(end+1, 1) = s.date; value(end+1, 1) = s.yoyPct; %#ok<AGROW>
    end
end

% Then add the values from every successful getSeries or getSnapshot call
for c = calls(:).'
    if ~any(c.name == ["getSeries", "getSnapshot", "prefetchData"]) || ~c.ok
        continue
    end
    try
        r = jsondecode(c.result);
    catch
        continue
    end
    for s = fomc.util.asCell(r.series).'
        s = s{1}; %#ok<FXSET>
        if isfield(s, "rows")
            for row = fomc.util.asCell(s.rows).'
                row = row{1}; %#ok<FXSET>
                series(end+1, 1) = string(s.seriesId); date(end+1, 1) = string(row.date); %#ok<AGROW>
                value(end+1, 1) = row.value; %#ok<AGROW>
            end
        elseif isfield(s, "value")
            series(end+1, 1) = string(s.seriesId); date(end+1, 1) = string(s.date); value(end+1, 1) = s.value; %#ok<AGROW>
            if isfield(s, "yoyPct") && ~isempty(s.yoyPct)
                series(end+1, 1) = string(s.seriesId); date(end+1, 1) = string(s.date); value(end+1, 1) = s.yoyPct; %#ok<AGROW>
            end
        end
    end
end
% Then the rate target on every day a getPolicyPath call covered
for c = calls(:).'
    if c.name == "getPolicyPath" && c.ok
        [s, d, v] = pathValues(ctx, c.result);
        series = [series; s]; date = [date; d]; value = [value; v]; %#ok<AGROW>
    end
end
known = struct("series", series, "date", date, "value", value);
end

function [series, date, value] = pathValues(ctx, result)
% A rate path states the target on every day it covers (it only changes on the dates listed),
% so the target counts as shown from the day before the earliest date it mentions to the day
% after its end (a change from a meeting on its last day takes effect the next day).
% DFEDTAR before the range began in December 2008, DFEDTARU and DFEDTARL after.
series = strings(0, 1); date = strings(0, 1); value = zeros(0, 1);
try
    r = jsondecode(result);
catch
    return
end
from = datetime(r.span.startDate);
for f = ["currentRun", "previousRun"]
    if isfield(r, f)
        from = min(from, datetime(r.(f).startDate));
    end
end
[~, levels] = fomc.data.ratePath(ctx.D, ctx.asOf);
L = levels(levels.date >= from - caldays(1) & levels.date <= datetime(r.span.endDate) + caldays(1), :);
oneTarget = L.date < datetime(2008,12,16);
R = L(~oneTarget, :);
series = [repmat("DFEDTAR", sum(oneTarget), 1); repmat("DFEDTARU", height(R), 1); repmat("DFEDTARL", height(R), 1)];
date = [fomc.util.fmtDate(L.date(oneTarget)); fomc.util.fmtDate(R.date); fomc.util.fmtDate(R.date)];
value = [L.upper(oneTarget); R.upper; R.lower];
end

function v = fieldOr(s, name)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = [];
end
end
