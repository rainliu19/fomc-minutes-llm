function r = checkToolOutput(ctx, result, json)
%CHECKTOOLOUTPUT Backstop: withhold a result with a date past the anchor or over the size cap.
%   r = fomc.guard.checkToolOutput(ctx, result, json)
%   Tools already filter by date; this turns a tool bug into a logged refusal, not look-ahead.

r = struct("ok", true, "message", "");

% Look for any date after the anchor in the result
bad = collectLateDates(result, ctx.asOf, strings(0, 1));
if ~isempty(bad)
    shown = strjoin(unique(bad(1:min(3, numel(bad)))), ", ");
    r = struct("ok", false, "message", "Result withheld: it contained dates after the anchor date (" + ...
        shown + "). This is a bug in the tool, not something the model did.");
    return
end
% Refuse results that are too large
if strlength(json) > ctx.cfg.maxResultChars
    r = struct("ok", false, "message", "Result withheld: " + strlength(json) + ...
        " characters is over the limit of " + ctx.cfg.maxResultChars + ". Ask for less, for example a shorter date range.");
end
end

function bad = collectLateDates(x, asOf, bad)
% Look through the result (nested structs and lists) for date fields later than the anchor
dateFields = ["date", "availableDate", "meetingDate", "releaseDate", "obsDate"];
if iscell(x)
    for i = 1:numel(x)
        bad = collectLateDates(x{i}, asOf, bad);
    end
elseif isstruct(x)
    for i = 1:numel(x)
        for f = string(fieldnames(x)).'
            v = x(i).(f);
            if any(f == dateFields) && (ischar(v) || isstring(v))
                for s = string(v(:)).'
                    d = fomc.util.parseDate(s);
                    if ~isnat(d) && d > asOf
                        bad(end+1, 1) = s; %#ok<AGROW>
                    end
                end
            else
                bad = collectLateDates(v, asOf, bad);
            end
        end
    end
end
end
