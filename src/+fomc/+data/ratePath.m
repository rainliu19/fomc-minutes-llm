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

% The single target, then the range once it starts, each as known on the anchor date
[target, ~] = fomc.data.valueAsOf(D, "DFEDTAR", asOf);
[top, ~] = fomc.data.valueAsOf(D, "DFEDTARU", asOf);
[bottom, ~] = fomc.data.valueAsOf(D, "DFEDTARL", asOf);
bounds = innerjoin(top(:, ["date", "value"]), bottom(:, ["date", "value"]), Keys="date");
if ~isempty(bounds)
    target = target(target.date < min(bounds.date), :);
end
levels = [table(target.date, target.value, target.value, VariableNames=["date", "lower", "upper"]); ...
    table(bounds.date, bounds.value_right, bounds.value_left, VariableNames=["date", "lower", "upper"])];
levels = sortrows(levels(~isnan(levels.upper) & ~isnan(levels.lower), :), "date");

% A move is any day the target differs from the day before
changed = [false; diff(levels.upper) ~= 0 | diff(levels.lower) ~= 0];
prevUpper = [NaN; levels.upper(1:end-1)];
moves = levels(changed, :);
moves.change = round(moves.upper - prevUpper(changed), 4);

% Tie each move to the meeting it came from: the rate data dates it the meeting's last day or the day after
M = D.meetings;
moves.meetingIdx = nan(height(moves), 1);
for i = 1:height(moves)
    k = find(abs(days(moves.date(i) - M.MeetingDate)) <= 1, 1);
    if ~isempty(k)
        moves.meetingIdx(i) = k;
    end
end
% A move with no meeting was made between meetings, but only where the meetings are known:
% the data starts with the January 2008 meeting, and scheduled meetings are at least five
% weeks apart, so a move in the 30 days before it (January 22, 2008) came between meetings.
% Earlier moves are left unlabeled.
known = min(M.MeetingDate) - caldays(30);
moves.betweenMeetings = isnan(moves.meetingIdx) & moves.date >= known;
end
