function t = note(ctx)
%NOTE Text added to each question: the focus window and the meetings with minutes in it.
%   t = fomc.focus.note(ctx)

% Meetings inside the focus window whose minutes are already public
w = ctx.focus;
M = ctx.D.meetings;
in = M.ReleaseDate <= ctx.asOf & M.MeetingDate >= w.start & M.MeetingDate <= w.end;
dates = M.MeetingDate(in);
if isempty(dates)
    listing = "none (try a different range with startDate and endDate)";
else
    listing = strjoin(fomc.util.fmtDate(dates).', ", ");
end
% Also name the latest minutes available, so the model can say later ones are not public
R = M(M.ReleaseDate <= ctx.asOf, :);
if isempty(R)
    latest = "No minutes have been released yet.";
else
    [~, k] = max(R.MeetingDate);
    latest = "Latest minutes available: meeting ended " + fomc.util.fmtDate(R.MeetingDate(k)) + ", released " + ...
        fomc.util.fmtDate(R.ReleaseDate(k)) + ". Later meetings are not public yet; say so if asked about one.";
end
% Put it all into one bracketed note
t = "[Focus window: " + fomc.util.fmtDate(w.start) + " to " + fomc.util.fmtDate(w.end) + " (" + w.reason + ")." + ...
    " searchMinutes and listMeetings use this window unless you pass startDate and endDate. " + ...
    "Meetings with minutes in the window: " + listing + ". " + latest + "]";
end
