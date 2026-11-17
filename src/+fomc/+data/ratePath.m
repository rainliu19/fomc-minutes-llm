function [moves, levels] = ratePath(D, asOf)
%RATEPATH Every change in the federal funds rate target known on a date, from FRED.
%   [moves, levels] = fomc.data.ratePath(D, asOf)
%   levels: date, lower, upper (the target each day). Before the range began in
%     December 2008 the single target (DFEDTAR) is both lower and upper.
%   moves: date, lower, upper (after the change), change (on the top of the range, in
%     percentage points), meetingIdx (row of D.meetings within a day of the change, else NaN)
%     and betweenMeetings (true for a change made between scheduled meetings).
%   Levels come from the rate data, not the minutes: three changes since 2008 were made
%   between scheduled meetings and appear in no decision card.

arguments
    D (1,1) struct
    asOf (1,1) datetime
end

% The same date is asked for several times in one question: keep the last answer
persistent key moves0 levels0
stamp = D.id + "|" + posixtime(asOf);
if ~isempty(key) && key == stamp
    moves = moves0;
    levels = levels0;
    return
end

% The single target, then the range once it starts, each as known on the anchor date
[target, ~] = fomc.data.valueAsOf(D, "DFEDTAR", asOf);
[top, ~] = fomc.data.valueAsOf(D, "DFEDTARU", asOf);
[bottom, ~] = fomc.data.valueAsOf(D, "DFEDTARL", asOf);
% Days that have both the upper and the lower bound
[both, at] = ismember(top.date, bottom.date);
if any(both)
    target = target(target.date < min(top.date(both)), :);
end
levels = [table(target.date, target.value, target.value, VariableNames=["date", "lower", "upper"]); ...
    table(top.date(both), bottom.value(at(both)), top.value(both), VariableNames=["date", "lower", "upper"])];
levels = sortrows(levels(~isnan(levels.upper) & ~isnan(levels.lower), :), "date");

% A move is any day the target differs from the day before
changed = [false; diff(levels.upper) ~= 0 | diff(levels.lower) ~= 0];
prevUpper = [NaN; levels.upper(1:end-1)];
moves = levels(changed, :);
moves.change = round(moves.upper - prevUpper(changed), 4);

% Tie each move to the meeting it came from: the rate data dates it the meeting's last day or the day after
M = D.meetings;
moves.meetingIdx = nan(height(moves), 1);
[near, first] = max(abs(days(moves.date - M.MeetingDate.')) <= 1, [], 2);   % the first meeting within a day of each move
moves.meetingIdx(near) = first(near);
% A move with no meeting was made between meetings, but only where the meetings are known:
% the data starts with the January 2008 meeting, and scheduled meetings are at least five
% weeks apart, so a move in the 30 days before it (January 22, 2008) came between meetings.
% Earlier moves are left unlabeled.
known = min(M.MeetingDate) - caldays(30);
moves.betweenMeetings = isnan(moves.meetingIdx) & moves.date >= known;
key = stamp;
moves0 = moves;
levels0 = levels;
end
