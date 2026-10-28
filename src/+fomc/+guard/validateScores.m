function issues = validateScores(result, minutesText, meetingDate, D)
%VALIDATESCORES Run the skill score schema and evidence checks.
%   issues = fomc.guard.validateScores(result, minutesText, meetingDate)
%   An empty string array means the score passed all checks.

arguments
    result
    minutesText (1,1) string
    meetingDate (1,1) string
    D (1,1) struct = fomc.data.load()
end

issues = fomc.guard.checkSchema(result);
issues = [issues; fomc.guard.checkScoreRange(result)];
issues = [issues; fomc.guard.checkQuotes(result, minutesText)];
issues = [issues; fomc.guard.checkRateConsistency(result, meetingDate, D)];
if isstruct(result) && isscalar(result) && isfield(result, "meeting_date") && ...
        isText(result.meeting_date) && string(result.meeting_date) ~= meetingDate
    issues(end+1, 1) = "meeting_date does not match the requested meeting " + meetingDate + "."; %#ok<AGROW>
end

releaseDate = NaT;
d = fomc.util.parseDate(meetingDate);
if ~isnat(d)
    k = find(D.meetings.MeetingDate == d, 1);
    if ~isempty(k)
        releaseDate = D.meetings.ReleaseDate(k);
    end
end
if ~isnat(releaseDate)
    issues = [issues; fomc.guard.checkAsOf(result, releaseDate)];
end

issues = unique(issues(strlength(issues) > 0), "stable");
end

function tf = isText(value)
tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value));
end
