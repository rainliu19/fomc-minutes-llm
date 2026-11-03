function r = getPolicyPath(ctx, args)
%GETPOLICYPATH How the rate target moved over several meetings, and which way dissenters leaned.
%   Default span: the latest 8 meetings whose minutes were public on the anchor date;
%   startDate and endDate pick another span. Rate levels and changes come from the rate data
%   (fomc.data.ratePath), which includes changes made between meetings; decisions and votes
%   come from the decision cards. The summary is written by code, so the model only has to
%   relay it, and it cites the paragraph behind each fact from the minutes.
%   datesFromQuestion (not offered to the model): true when the harness chose the dates from
%   the question itself (fomc.focus.pathPrefetch), so they are kept as given.

% Check the dates; the span ends on the anchor date at the latest
[startDate, endDate, msg] = readDates(ctx, args);
if msg ~= ""
    r = fomc.tools.fail(msg);
    return
end
spanEnd = ctx.asOf;
if ~isnat(endDate)
    spanEnd = min(endDate, ctx.asOf);
end
if ~isnat(startDate) && startDate > spanEnd
    r = fomc.tools.fail("'startDate' must be on or before 'endDate' and the anchor date " + ...
        fomc.util.fmtDate(ctx.asOf) + ".");
    return
end

% Every rate change known on the anchor date up to the span's end, and the span's meetings
D = ctx.D;
[moves, levels] = changesAsOf(ctx, spanEnd);
released = D.meetings.ReleaseDate <= ctx.asOf & D.meetings.MeetingDate <= spanEnd;
[k, spanStart, msg] = pickSpan(D.meetings, released, startDate, spanEnd);
if msg ~= ""
    r = fomc.tools.fail(msg);
    return
end
S = moves(moves.when >= spanStart, :);
endLevel = levelAtEnd(levels, S, spanEnd);
if isempty(endLevel)
    r = fomc.tools.fail("No federal funds rate target is on record by " + fomc.util.fmtDate(spanEnd) + ".");
    return
end

% The facts: the last change and its run, the changes in the span, the dissents, the counts
[p, cites] = describeLastChange(moves, released, levels, D);
rows = listChanges(S, D);
[dissents, tally, latest, cites] = tallyDissents(D, k, moves, levels, cites);
span = spanCounts(k, S, moves, levels, endLevel, spanStart, spanEnd);

% The result: a plain summary first, then the facts behind it
r = struct("anchorDate", fomc.util.fmtDate(ctx.asOf));
r.summary = "On " + fomc.util.fmtDate(spanEnd) + " the federal funds rate target was " + span.toRange + "." + ...
    changeText(p, cites) + spanText(span) + dissentText(span, tally, latest, cites);
r.targetRange = span.toRange;
if ~isempty(fieldnames(p.lastMove))
    r.lastChange = p.lastMove;
    r.currentRun = p.current;
    if ~isempty(fieldnames(p.previous))
        r.previousRun = p.previous;
    end
    r.meetingsHeldBeforeLastChange = p.heldBefore;
    r.meetingsHeldSinceLastChange = p.heldSince;
end
r.span = span;
r.changes = rows;
r.dissents = dissents;
r.dissentVotes = tally;
r.note = "Changes are in percentage points, measured on the top of the target range " + ...
    "(the single target before December 2008). Dissent directions compare the rate a " + ...
    "dissenter preferred with the decision; 'other' means the dissent was about something " + ...
    "else, such as statement wording or asset purchases.";
end

function [startDate, endDate, msg] = readDates(ctx, args)
% The date arguments, NaT when absent, and a message if one is not a date.
% Models copy the focus window from the question's note into any tool with dates. When the
% question named no year, that window is just "the last few years", not a span anyone chose,
% so the latest 8 meetings (about a year) answer it better.
[startDate, bad1] = dateArg(args, "startDate");
[endDate, bad2] = dateArg(args, "endDate");
msg = strtrim(strjoin([bad1, bad2], " "));
if msg ~= ""
    return
end
w = ctx.focus;
copied = ~isequal(fomc.tools.getArg(args, "datesFromQuestion", false), true) && ...
    isfield(w, "fromQuestion") && ~w.fromQuestion && ~isnat(w.start) && ...
    isequal(startDate, w.start) && (isnat(endDate) || isequal(endDate, w.end));
if copied
    startDate = NaT;
    endDate = NaT;
end
end

function [d, msg] = dateArg(args, name)
% A date argument: NaT if absent, with a message if it was given but is not a date
raw = fomc.tools.getArg(args, name, "");
d = NaT;
msg = "";
if (ischar(raw) || isstring(raw)) && strlength(strtrim(string(raw))) == 0
    return
end
d = fomc.util.parseDate(raw);
if isnat(d)
    msg = "'" + name + "' must be a date written YYYY-MM-DD.";
end
end

function [moves, levels] = changesAsOf(ctx, spanEnd)
% Every rate change known on the anchor date up to spanEnd. Adds "when" (the meeting date for
% a change that came from a meeting, else the date it took effect) and "minutesOut" (that
% meeting's minutes were public on the anchor date).
M = ctx.D.meetings;
[moves, levels] = fomc.data.ratePath(ctx.D, ctx.asOf);
moves.when = moves.date;
tied = ~isnan(moves.meetingIdx);
moves.when(tied) = M.MeetingDate(moves.meetingIdx(tied));
moves = moves(moves.when <= spanEnd, :);
tied = ~isnan(moves.meetingIdx);
moves.minutesOut = false(height(moves), 1);
moves.minutesOut(tied) = M.ReleaseDate(moves.meetingIdx(tied)) <= ctx.asOf;
end

function [k, spanStart, msg] = pickSpan(M, released, startDate, spanEnd)
% The span's meetings (rows of M; released marks those with public minutes up to spanEnd):
% the latest 8 by default, or all from startDate on. msg says why a default span has none.
msg = "";
if isnat(startDate)
    k = find(released);
    k = k(max(1, end - 7):end);
    spanStart = NaT;
    if isempty(k)
        msg = "No minutes were public by " + fomc.util.fmtDate(spanEnd) + ".";
        return
    end
    spanStart = M.MeetingDate(k(1));
else
    spanStart = startDate;
    k = find(released & M.MeetingDate >= spanStart);
end
end

function endLevel = levelAtEnd(levels, S, spanEnd)
% The target at the span's end (empty if none is on record). A change from the span's last
% meeting can take effect the day after spanEnd; it still counts.
endLevel = levels(levels.date <= spanEnd, :);
if isempty(endLevel)
    return
end
endLevel = endLevel(end, :);
if ~isempty(S) && S.date(end) > endLevel.date
    endLevel = S(end, ["date", "lower", "upper"]);
end
end

function [p, cites] = describeLastChange(moves, released, levels, D)
% The last change, the run it belongs to (consecutive changes in one direction, holds in
% between allowed), the run before it when the last change reversed direction, and the
% meetings held before and since it. cites: the paragraph ids behind those facts.
M = D.meetings;
p = struct("lastMove", struct(), "current", struct(), "previous", struct(), "heldBefore", 0, "heldSince", 0);
cites = struct("last", "", "firstSince", "", "runStart", "", "previousStart", "", ...
    "previousEnd", "", "heldBefore", "", "heldSince", "", "lower", "", "higher", "");
if isempty(moves)
    return
end
runId = cumsum([1; diff(sign(moves.change)) ~= 0]);
mine = runId == runId(end);
last = height(moves);
lastMove = struct("date", fomc.util.fmtDate(moves.date(last)), ...
    "meetingDate", meetingOf(moves, last, M), "change", moves.change(last), ...
    "targetRange", fomc.util.rangeText(moves.lower(last), moves.upper(last)));
if moves.betweenMeetings(last)
    lastMove.betweenMeetings = true;
elseif ~isnan(moves.meetingIdx(last)) && ~moves.minutesOut(last)
    lastMove.minutesPublic = false;
end
cites.last = decisionIdOf(moves, last, D);
cites.runStart = decisionIdOf(moves, find(mine, 1), D);
p.current = runInfo(moves(mine, :), M, levels);
% A change that reversed direction: describe the run it ended
if sum(mine) == 1 && runId(end) > 1
    prev = find(runId == runId(end) - 1);
    p.previous = runInfo(moves(prev, :), M, levels);
    cites.previousStart = decisionIdOf(moves, prev(1), D);
    cites.previousEnd = decisionIdOf(moves, prev(end), D);
    if runId(end) > 2
        same = find(runId == runId(end) - 2, 1, "last");
        lastMove.firstInThisDirectionSince = meetingOrDate(moves, same, M);
        cites.firstSince = decisionIdOf(moves, same, D);
    end
end
p.lastMove = lastMove;
% Meetings with released minutes and no change, before the last change and since it; the
% latest of each is cited, so the model has a real paragraph for the holds
noMove = released & ~ismember((1:height(M)).', moves.meetingIdx);
since = find(noMove & M.MeetingDate > moves.when(last));
p.heldSince = numel(since);
if ~isempty(since)
    cites.heldSince = D.cards.decisionId(since(end));
end
if last > 1
    held = find(noMove & M.MeetingDate > moves.when(last - 1) & M.MeetingDate < moves.when(last));
    p.heldBefore = numel(held);
    if ~isempty(held)
        cites.heldBefore = D.cards.decisionId(held(end));
    end
end
end

function s = runInfo(R, M, levels)
% A run of changes in one direction: how many, how much, when, and from what level to what
prior = levels(levels.date < R.date(1), :);
fromRange = "";
if ~isempty(prior)
    fromRange = fomc.util.rangeText(prior.lower(end), prior.upper(end));
end
s = struct("direction", directionWord(R.change(1)), "changes", height(R), ...
    "totalChange", round(sum(R.change), 4), ...
    "startDate", meetingOrDate(R, 1, M), "endDate", meetingOrDate(R, height(R), M), ...
    "fromRange", fromRange, "toRange", fomc.util.rangeText(R.lower(end), R.upper(end)));
end

function rows = listChanges(S, D)
% The changes in the span, newest last (at most 24 listed), each with its decision paragraph
% when its minutes are out
M = D.meetings;
rows = cell(height(S), 1);
for i = 1:height(S)
    row = struct("date", fomc.util.fmtDate(S.date(i)), "change", S.change(i), ...
        "targetRange", fomc.util.rangeText(S.lower(i), S.upper(i)), "meetingDate", meetingOf(S, i, M));
    if S.betweenMeetings(i)
        row.betweenMeetings = true;
    elseif S.minutesOut(i)
        row.decisionId = D.cards.decisionId(S.meetingIdx(i));
    elseif ~isnan(S.meetingIdx(i))
        row.minutesPublic = false;
    end
    rows{i} = row;
end
rows = rows(max(1, end - 23):end);
end

function [dissents, tally, latest, cites] = tallyDissents(D, k, moves, levels, cites)
% Dissents at the span's meetings, by the direction each dissenter wanted (at most 12 rows
% listed; the tally counts them all). Adds the latest dissent each way to cites.
M = D.meetings;
dissents = {};
tally = struct("lower", 0, "higher", 0, "other", 0);
latest = struct("lower", "", "higher", "");
fieldFor = struct("lower", "wantedLower", "higher", "wantedHigher", "other", "otherGrounds");
for j = k(:).'
    if D.cards.unanimous(j) || D.cards.voteId(j) == ""
        continue
    end
    mv = find(moves.meetingIdx == j, 1);
    change = 0;
    if ~isempty(mv)
        change = moves.change(mv);
    end
    topAfter = levels.upper(find(levels.date <= M.MeetingDate(j) + caldays(1), 1, "last"));
    o = fomc.data.dissentDirections(D, j, change, topAfter);
    row = struct("meetingDate", fomc.util.fmtDate(M.MeetingDate(j)), "id", D.cards.voteId(j));
    for dir = ["lower", "higher", "other"]
        who = [o([o.direction] == dir).name];
        if ~isempty(who)
            row.(fieldFor.(dir)) = strjoin(who, ", ");
            tally.(dir) = tally.(dir) + numel(who);
            if dir ~= "other"
                latest.(dir) = fomc.util.fmtDate(M.MeetingDate(j));
                cites.(dir) = D.cards.voteId(j);
            end
        end
    end
    dissents{end+1, 1} = row; %#ok<AGROW>
end
dissents = dissents(max(1, end - 11):end);
end

function span = spanCounts(k, S, moves, levels, endLevel, spanStart, spanEnd)
% Counts over the span. Holds are meetings with released minutes and no change; changes not
% at such a meeting (between meetings, minutes not out, before the minutes data) are counted
% in the increases and cuts and named separately.
before = levels(levels.date < spanStart, :);
fromUpper = NaN;
fromRange = "";
if ~isempty(before)
    fromUpper = before.upper(end);
    fromRange = fomc.util.rangeText(before.lower(end), before.upper(end));
end
span = struct("startDate", fomc.util.fmtDate(spanStart), "endDate", fomc.util.fmtDate(spanEnd), ...
    "meetings", numel(k), "increases", sum(S.change > 0), "cuts", sum(S.change < 0), ...
    "holds", sum(~ismember(k, moves.meetingIdx)), ...
    "changesBetweenMeetings", sum(S.betweenMeetings), ...
    "changesMinutesNotPublic", sum(~isnan(S.meetingIdx) & ~S.minutesOut), ...
    "changesBeforeMinutesData", sum(isnan(S.meetingIdx) & ~S.betweenMeetings), ...
    "netChange", round(endLevel.upper - fromUpper, 4), ...
    "fromRange", fromRange, "toRange", fomc.util.rangeText(endLevel.lower, endLevel.upper));
end

function m = meetingOf(T, i, M)
% The meeting a change came from, or "" for a change with no meeting in the data
m = "";
if ~isnan(T.meetingIdx(i))
    m = fomc.util.fmtDate(M.MeetingDate(T.meetingIdx(i)));
end
end

function d = meetingOrDate(T, i, M)
% The meeting date when a change came from a meeting, else the date it took effect
d = meetingOf(T, i, M);
if d == ""
    d = fomc.util.fmtDate(T.date(i));
end
end

function id = decisionIdOf(T, i, D)
% The decision paragraph behind a change; "" when there is none to cite (no meeting in the
% data, or minutes not out yet)
id = "";
if T.minutesOut(i)
    id = D.cards.decisionId(T.meetingIdx(i));
end
end

% The summary is written in three parts. Each fact from the minutes carries its paragraph id
% in brackets, the way answers cite them, so a model that copies it copies the citations too.

function t = changeText(p, cites)
% The last change, whether it reversed direction or continued a run, and the holds around it
t = "";
lastMove = p.lastMove;
if isempty(fieldnames(lastMove))
    return
end
current = p.current;
if lastMove.meetingDate ~= ""
    where = " at the meeting ending " + lastMove.meetingDate + cite(cites.last);
    if isfield(lastMove, "minutesPublic")
        where = where + " (its minutes were not public yet)";
    end
elseif isfield(lastMove, "betweenMeetings")
    where = " on " + lastMove.date + ", between scheduled meetings";
else
    where = " on " + lastMove.date;
end
t = " The last change was " + article(current.direction) + current.direction + " of " + ...
    points(lastMove.change) + unit(lastMove.change) + where;
if current.changes == 1 && isfield(lastMove, "firstInThisDirectionSince")
    t = t + ", the first " + current.direction + " since " + lastMove.firstInThisDirectionSince + ...
        cite(cites.firstSince) + ".";
elseif current.changes > 1
    t = t + ", the " + ordinal(current.changes) + " " + current.direction + " since " + current.startDate + ...
        cite(cites.runStart) + " with no " + opposite(current.direction) + " in between (" + ...
        points(current.totalChange) + unit(current.totalChange) + " in all).";
else
    t = t + ".";
end
if ~isempty(fieldnames(p.previous))
    prev = p.previous;
    t = t + " It followed " + count(prev.changes, prev.direction) + " totaling " + ...
        points(prev.totalChange) + unit(prev.totalChange) + " from " + ...
        prev.startDate + cite(cites.previousStart) + " to " + prev.endDate + ...
        cite(cites.previousEnd) + " (target before: " + prev.fromRange + "; after: " + prev.toRange + ").";
end
if p.heldBefore > 0
    t = t + " Before that change, the target was held at " + count(p.heldBefore, "meeting") + ...
        cite(cites.heldBefore) + ".";
end
if p.heldSince > 0
    t = t + " It has been held at " + count(p.heldSince, "meeting") + " since" + cite(cites.heldSince) + ".";
end
end

function t = spanText(span)
% The span's counts, naming any changes that were not at a meeting with released minutes
if span.meetings > 0
    t = " Across the " + count(span.meetings, "meeting") + " from " + span.startDate + " to " + span.endDate + ": ";
else
    t = " From " + span.startDate + " to " + span.endDate + " (no meetings with minutes in this data): ";
end
t = t + count(span.increases, "increase") + ", " + count(span.cuts, "cut") + " and " + count(span.holds, "hold");
extra = strings(0, 1);
if span.changesBetweenMeetings > 0
    extra(end+1) = count(span.changesBetweenMeetings, "change") + " between scheduled meetings";
end
if span.changesMinutesNotPublic > 0
    extra(end+1) = count(span.changesMinutesNotPublic, "change") + " at a meeting whose minutes were not public yet";
end
if span.changesBeforeMinutesData > 0
    extra(end+1) = count(span.changesBeforeMinutesData, "change") + " from before 2008, when the minutes in this data begin";
end
if ~isempty(extra)
    t = t + " (the increases and cuts include " + strjoin(extra, " and ") + ")";
end
if span.fromRange ~= ""
    t = t + "; net change " + signed(span.netChange) + unit(span.netChange) + " (target at the start: " + ...
        span.fromRange + "; at the end: " + span.toRange + ").";
else
    t = t + ".";
end
end

function t = dissentText(span, tally, latest, cites)
% The dissenting votes by direction, with the latest each way
parts = strings(0, 1);
if tally.lower > 0
    parts(end+1) = tally.lower + " for a lower rate (latest " + latest.lower + cite(cites.lower) + ")";
end
if tally.higher > 0
    parts(end+1) = tally.higher + " for a higher rate (latest " + latest.higher + cite(cites.higher) + ")";
end
if tally.other > 0
    parts(end+1) = tally.other + " on other grounds, such as statement wording or asset purchases";
end
t = "";
if ~isempty(parts)
    t = " Dissenting votes: " + strjoin(parts, "; ") + ".";
elseif span.meetings > 0
    t = " No one dissented at these meetings.";
end
end

function t = cite(id)
% " [2026-09-16/policyAction/1]", or nothing when there is no paragraph to cite
t = "";
if id ~= ""
    t = " [" + id + "]";
end
end

function t = points(x)
% 0.25 -> "0.25", 1.5 -> "1.5", 2 -> "2"
t = string(sprintf("%.2f", abs(x)));
t = regexprep(t, "\.?0+$", "");
end

function t = signed(x)
% +0.25, -1.5, 0
if x > 0
    t = "+" + points(x);
elseif x < 0
    t = "-" + points(x);
else
    t = "0";
end
end

function u = unit(x)
% "0.25 percentage point", but "0 percentage points" and "1.75 percentage points"
u = " percentage point";
if x == 0 || abs(x) > 1
    u = " percentage points";
end
end

function t = count(n, noun)
% "1 meeting", "5 meetings"
t = n + " " + noun;
if n ~= 1
    t = t + "s";
end
end

function t = ordinal(n)
% 1st, 2nd, 3rd, 4th, 11th, 21st
suffix = "th";
if mod(n, 100) < 11 || mod(n, 100) > 13
    switch mod(n, 10)
        case 1, suffix = "st";
        case 2, suffix = "nd";
        case 3, suffix = "rd";
    end
end
t = string(n) + suffix;
end

function w = directionWord(change)
% "increase" or "cut"
if change > 0
    w = "increase";
else
    w = "cut";
end
end

function w = opposite(direction)
% The other direction: "cut" for "increase", and the reverse
if direction == "increase"
    w = "cut";
else
    w = "increase";
end
end

function a = article(word)
% "an increase", "a cut"
a = "a ";
if startsWith(word, ["a", "e", "i", "o", "u"])
    a = "an ";
end
end
