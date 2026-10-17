function r = listMeetings(ctx, args)
%LISTMEETINGS Meetings whose minutes were public on the anchor date, newest first.
%   Limited to the focus window unless the model passes startDate or endDate.

% Check the arguments; use the focus window when no dates were given
n = fomc.tools.getArg(args, "n", 30);
if ~isnumeric(n) || ~isscalar(n) || n < 1 || n > 50 || n ~= round(n)
    r = fomc.tools.fail("'n' must be a whole number from 1 to 50.");
    return
end
startDate = fomc.util.parseDate(fomc.tools.getArg(args, "startDate", ""));
endDate = fomc.util.parseDate(fomc.tools.getArg(args, "endDate", ""));
[startDate, endDate, isDefault] = fomc.tools.applyWindow(ctx, startDate, endDate);

% Keep meetings released by the anchor date and inside the window, newest first, at most n
M = ctx.D.meetings;
keep = M.ReleaseDate <= ctx.asOf;
if ~isnat(startDate), keep = keep & M.MeetingDate >= startDate; end
if ~isnat(endDate), keep = keep & M.MeetingDate <= endDate; end
M = sortrows(M(keep, :), "MeetingDate", "descend");
M = M(1:min(n, height(M)), :);

% Build the result
rows = cell(height(M), 1);
for i = 1:height(M)
    rows{i} = struct("meetingDate", fomc.util.fmtDate(M.MeetingDate(i)), ...
        "releaseDate", fomc.util.fmtDate(M.ReleaseDate(i)));
end
r = struct("anchorDate", fomc.util.fmtDate(ctx.asOf), "count", height(M), ...
    "window", windowInfo(startDate, endDate, isDefault), "meetings", {rows});
end

function w = windowInfo(startDate, endDate, isDefault)
w = struct("startDate", fomc.util.fmtDate(startDate), "endDate", fomc.util.fmtDate(endDate), ...
    "isDefault", isDefault);
end
