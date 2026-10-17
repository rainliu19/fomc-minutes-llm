function r = checkToolInput(ctx, ~, args)
%CHECKTOOLINPUT Refuse tool arguments that reach past the anchor date.
%   r = fomc.guard.checkToolInput(ctx, name, args)   (name is unused)
%   r.ok false means do not run; r.message says why, in words the model can act on.
%   Plain code, so it cannot be argued with. Checks meetingDate, startDate and endDate
%   (YYYY-MM-DD). A meetingDate is also refused if that meeting's minutes were not public
%   on the anchor date.

% Allowed unless a check below says otherwise
r = struct("ok", true, "message", "");
anchor = fomc.util.fmtDate(ctx.asOf);

if ~isstruct(args) || ~isscalar(args)
    r = refuse("Tool arguments must be a single JSON object.");
    return
end

% Check each date argument: it must be a real date, not after the anchor, and (for meetingDate) a released meeting
for f = ["meetingDate", "startDate", "endDate"]
    if ~isfield(args, f) || isBlank(args.(f))
        continue
    end
    raw = args.(f);
    d = fomc.util.parseDate(raw);
    if isnat(d)
        shown = "that value";
        if ischar(raw) || isstring(raw)
            shown = "'" + string(raw) + "'";
        end
        r = refuse("'" + f + "' must be a date written YYYY-MM-DD, but got " + shown + ".");
        return
    end
    if d > ctx.asOf
        r = refuse("Refused: " + f + " " + fomc.util.fmtDate(d) + " is after the anchor date " + ...
            anchor + ". This session only has information that was public on or before " + ...
            anchor + ". Use a date on or before it.");
        return
    end
    if f == "meetingDate"
        M = ctx.D.meetings;
        k = M.MeetingDate == d;
        if any(k) && M.ReleaseDate(k) > ctx.asOf
            r = refuse("The minutes of the meeting ending " + fomc.util.fmtDate(d) + ...
                " were not public on " + anchor + ", so they are not available in this session. " + ...
                "Call listMeetings to see which minutes are available.");
            return
        end
    end
end
end

function tf = isBlank(v)
% An absent optional argument may arrive as [], '' or "".
tf = isempty(v) || ((ischar(v) || isstring(v)) && all(strlength(strtrim(string(v))) == 0));
end

function r = refuse(msg)
r = struct("ok", false, "message", string(msg));
end
