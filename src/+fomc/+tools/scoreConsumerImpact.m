function r = scoreConsumerImpact(ctx, args)
%SCORECONSUMERIMPACT Rubric score for one meeting (a stub), from the minutes text only.

% Check the date and that the meeting was released by the anchor date
d = fomc.util.parseDate(fomc.tools.getArg(args, "meetingDate", ""));
if isnat(d)
    r = fomc.tools.fail("'meetingDate' is required and must be written YYYY-MM-DD. Call listMeetings for valid dates.");
    return
end
M = ctx.D.meetings;
M = M(M.ReleaseDate <= ctx.asOf, :);
k = find(M.MeetingDate == d, 1);
if isempty(k)
    r = fomc.tools.fail("No released minutes for a meeting ending " + fomc.util.fmtDate(d) + ". Call listMeetings for valid dates.");
    return
end
% Score the minutes text (the stub for now) and report the result
s = fomc.rubric.scoreMinutes(M.Body(k), fomc.util.fmtDate(d));
r = struct("meetingDate", s.meetingDate, "criteria", {num2cell(s.criteria)}, ...
    "aggregate", s.aggregate, "direction", s.direction, "stub", s.stub);
if s.stub
    r.note = "The consumer-impact rubric is not implemented yet. Do not report a score or a direction.";
end
end
