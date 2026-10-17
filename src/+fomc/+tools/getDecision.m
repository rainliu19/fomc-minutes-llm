function r = getDecision(ctx, args)
%GETDECISION What the Committee decided at one meeting: action, target range, vote, dissent.
%   From fomc.data.decisionCards; tests check them against the actual rate changes.

% Check the date argument
d = fomc.util.parseDate(fomc.tools.getArg(args, "meetingDate", ""));
if isnat(d)
    r = fomc.tools.fail("'meetingDate' is required and must be written YYYY-MM-DD. Call listMeetings for valid dates.");
    return
end
% Find the meeting, only if released by the anchor date; if not, suggest the nearest ones
M = ctx.D.meetings;
k = find(M.MeetingDate == d & M.ReleaseDate <= ctx.asOf, 1);
if isempty(k)
    R = M(M.ReleaseDate <= ctx.asOf, :);
    [~, order] = sort(abs(days(R.MeetingDate - d)));
    near = fomc.util.fmtDate(sort(R.MeetingDate(order(1:min(3, numel(order))))));
    r = fomc.tools.fail("No FOMC meeting ended on " + fomc.util.fmtDate(d) + ...
        ". The nearest available meetings ended on: " + strjoin(near, ", ") + ".");
    return
end

% The decision card for this meeting (read from the minutes by code), copied into the result piece by piece
c = ctx.D.cards(k, :);
r = struct("meetingDate", fomc.util.fmtDate(M.MeetingDate(k)), ...
    "releaseDate", fomc.util.fmtDate(M.ReleaseDate(k)), "action", c.action);
if c.targetRange ~= ""
    r.targetRange = c.targetRange;
end
if c.change ~= ""
    r.change = c.change;
end
if c.decisionText ~= ""
    r.decision = struct("text", c.decisionText, "id", c.decisionId);
end
% The vote, and the dissent when it was not unanimous
if c.voteId ~= ""
    r.vote = struct("nFor", c.nFor, "nAgainst", c.nAgainst, "for", c.votesFor, "against", c.votesAgainst, ...
        "unanimous", c.unanimous, "id", c.voteId);
    if ~c.unanimous && c.dissentText ~= ""
        r.dissent = struct("text", c.dissentText, "id", c.dissentId);
    end
end
% The card could not be read: point the model at the raw text
if c.action == "unknown"
    r.note = "The decision could not be read automatically. Use readMinutes with section policyAction.";
end
end
