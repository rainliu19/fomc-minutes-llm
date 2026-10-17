function r = describeSeries(ctx, args)
%DESCRIBESERIES What a series is, its units and when each value becomes known.

% Look the series up in the data dictionary
id = string(fomc.tools.getArg(args, "seriesId", ""));
k = ctx.D.dict.series_id == id;
if ~any(k)
    r = fomc.tools.fail("Unknown seriesId '" + id + "'. Valid ids: " + strjoin(ctx.D.dict.series_id, ", ") + ".");
    return
end
% Its dictionary row, its publication rule, and the values known on the anchor date
row = ctx.D.dict(k, :);
a = ctx.D.avail(ctx.D.avail.series_id == id, :);
[T, note] = fomc.data.valueAsOf(ctx.D, id, ctx.asOf);

% Build the description
r = struct("seriesId", id, "label", text(row, "label"), "source", text(row, "source"), ...
    "frequency", text(row, "frequency"), "units", text(row, "units"), ...
    "seasonalAdjustment", text(row, "seasonal_adjustment"), ...
    "isRevised", ismember("revised", string(row.Properties.VariableNames)) && row.revised == 1, ...
    "whenKnown", describeRule(a), "notes", text(row, "notes"));
% Say how far the known data reaches
if ~isempty(T)
    r.firstObservationKnown = fomc.util.fmtDate(T.date(1));
    r.latestObservationKnown = fomc.util.fmtDate(T.date(end));
end
if strlength(note) > 0
    r.coverageNote = note;
end
end

function s = text(row, name)
% A text field of the dictionary row, or empty if missing
if ismember(name, string(row.Properties.VariableNames)) && ~ismissing(row.(name))
    s = string(row.(name));
else
    s = "";
end
end

function s = describeRule(a)
% Explain the publication rule in plain words
switch a.rule
    case "vintage"
        s = "Revised series. The value shown is the one published as of the anchor date, from the real-time vintage history.";
    case "lagdays"
        s = "Each value is treated as public " + a.param + " day(s) after its observation date.";
    case "monthend"
        s = "Each value is treated as public " + a.param + " day(s) after the end of its observation month.";
    otherwise
        s = "Not available in this agent.";
end
if strlength(a.note) > 0
    s = s + " " + a.note;
end
end
