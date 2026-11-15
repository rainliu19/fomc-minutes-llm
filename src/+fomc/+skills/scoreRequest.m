function [answer, output] = scoreRequest(s, userMsg)
%SCOREREQUEST Score the meetings a user's message names, one rubric dimension per model call.
%   [answer, output] = fomc.skills.scoreRequest(s, userMsg)
%   s: the session. answer: the score JSON (or the question to ask the user); output: the
%   skill's result (ok, issues, failedDimensions, attempts and score or scores). Used by
%   fomc.runTurn and by the rubric scorer agent (fomc.agents.rubricScorer).
% Route one or more requested meeting dates to the validated score skill. Each meeting is
% scored one dimension per model call (fomc.skills.scoreByDimension), so every prompt fits
% the local models' 8,192-token window; the one-call fomc.skills.scoreMeeting sends the full
% minutes, about 11,000 to 17,000 tokens, which those models refuse or cut.
text = char(userMsg);
dateMatches = regexp(text, '\d{4}-\d{2}-\d{2}', 'match');
[monthDates, monthIssue] = meetingsNamedByMonth(s, text);
dates = unique([string(dateMatches(:)); monthDates], "stable");
isComparison = any(contains(lower(userMsg), ["compare", "comparison", "versus", " vs "]));
asksLatest = ~isempty(regexpi(text, '(?<![a-z])latest(?![a-z])', 'once'));
if isComparison && asksLatest
    dates = unique([dates(:); latestReleasedMeetingDate(s)], "stable");
end
if monthIssue ~= ""
    % A month with no meeting or with several: ask, rather than score some other meeting
    answer = monthIssue;
    output = struct("skill", "fomc-score", "ok", false, "issues", answer, ...
        "failedDimensions", strings(0, 1), "attempts", 0);
elseif isComparison && numel(dates) < 2
    answer = "To compare FOMC scores, include at least two distinct meeting dates (YYYY-MM-DD), or pair one date with 'latest'.";
    output = struct("skill", "fomc-score", "ok", false, "issues", answer, ...
        "failedDimensions", strings(0, 1), "attempts", 0);
else
    try
        if numel(dates) <= 1
            meetingDate = "";
            if ~isempty(dates)
                meetingDate = dates(1);
            end
            output = fomc.skills.scoreByDimension(s, meetingDate);
            output.skill = "fomc-score";
            answer = string(jsonencode(fomc.skills.forJson(output.score)));
        else
            scores = cell(numel(dates), 1);
            validation = cell(numel(dates), 1);
            allIssues = strings(0, 1);
            failedDimensions = strings(0, 1);
            attempts = 0;
            ok = true;
            for i = 1:numel(dates)
                result = fomc.skills.scoreByDimension(s, dates(i));
                scores{i} = result.score;
                validation{i} = struct("meeting_date", string(result.score.meeting_date), ...
                    "ok", result.ok, "issues", result.issues, ...
                    "failedDimensions", result.failedDimensions, "attempts", result.attempts);
                ok = ok && result.ok;
                attempts = attempts + result.attempts;
                allIssues = [allIssues; string(result.score.meeting_date) + ": " + result.issues(:)]; %#ok<AGROW>
                failedDimensions = union(failedDimensions, result.failedDimensions, "stable");
            end
            output = struct("skill", "fomc-score", "scores", {scores}, "validation", {validation}, ...
                "ok", ok, "issues", allIssues, "failedDimensions", failedDimensions, ...
                "attempts", attempts);
            encoded = output;
            encoded.scores = cellfun(@fomc.skills.forJson, scores, UniformOutput=false);
            answer = string(jsonencode(encoded));
        end
    catch ME
        issue = "Scoring failed: " + fomc.trace.scrub(string(ME.message));
        output = struct("skill", "fomc-score", "ok", false, "issues", issue, ...
            "failedDimensions", strings(0, 1), "attempts", 0);
        answer = string(jsonencode(output));
        fomc.trace.logEvent(s.ctx, "skill_score_error", struct("message", issue));
    end
end

end

function [dates, issue] = meetingsNamedByMonth(s, text)
% Meetings named by month and year ("December 2015", "Dec. 2015"), as YYYY-MM-DD. A month
% with exactly one meeting held by the anchor date gives that meeting; a month with none or
% with several gives an issue asking for the date instead. Meetings after the anchor are not
% listed, so the answer cannot reveal them.
dates = strings(0, 1);
issue = "";
tokens = regexpi(text, ['(?<![a-z])(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|' ...
    'july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?,?\s+(\d{4})(?!\d)'], ...
    'tokens');
abbreviations = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
held = s.ctx.D.meetings.MeetingDate(s.ctx.D.meetings.MeetingDate <= s.ctx.asOf);
for k = 1:numel(tokens)
    mo = find(abbreviations == extractBefore(lower(string(tokens{k}{1})), 4));
    yr = str2double(tokens{k}{2});
    named = string(datetime(yr, mo, 1), "MMMM yyyy");
    inMonth = held(year(held) == yr & month(held) == mo);
    if numel(inMonth) == 1
        dates(end+1, 1) = fomc.util.fmtDate(inMonth); %#ok<AGROW>
    elseif isempty(inMonth)
        issue = "I have no FOMC meeting in " + named + " (by " + fomc.util.fmtDate(s.ctx.asOf) + ...
            "). Give the meeting date as YYYY-MM-DD.";
        return
    else
        issue = "There were " + numel(inMonth) + " FOMC meetings in " + named + " (" + ...
            strjoin(fomc.util.fmtDate(inMonth), ", ") + "). Which one should I score? " + ...
            "Give the date as YYYY-MM-DD.";
        return
    end
end
end

function meetingDate = latestReleasedMeetingDate(s)
% Resolve "latest" using the same release-date rule as the scorers.
M = s.ctx.D.meetings;
available = find(M.ReleaseDate <= s.ctx.asOf);
if isempty(available)
    error("fomc:skills:noReleasedMeetings", "No meeting minutes were released by the anchor date.");
end
[~, order] = sort(M.ReleaseDate(available), "descend");
meetingDate = fomc.util.fmtDate(M.MeetingDate(available(order(1))));
end

