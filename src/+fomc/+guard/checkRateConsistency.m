function issues = checkRateConsistency(result, meetingDate, D)
%CHECKRATECONSISTENCY Compare rate_path score with the coded meeting decision.

issues = strings(0, 1);
d = fomc.util.parseDate(meetingDate);
if isnat(d)
    issues(end+1, 1) = "meetingDate must be a valid YYYY-MM-DD date."; %#ok<AGROW>
    return
end
k = find(D.meetings.MeetingDate == d, 1);
if isempty(k)
    issues(end+1, 1) = "No meeting was found for " + fomc.util.fmtDate(d) + "."; %#ok<AGROW>
    return
end
action = string(D.cards.action(k));
if ~any(action == ["raise", "cut", "hold"])
    return
end
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, "dimensions") || ...
        ~isstruct(result.dimensions) || ~isfield(result.dimensions, "rate_path")
    return
end
rate = result.dimensions.rate_path;
if ~isstruct(rate) || ~isscalar(rate)
    return
end
if ~isfield(rate, "status") || ~isText(rate.status) || string(rate.status) ~= "scored" || ...
        ~isfield(rate, "score") || ~isnumeric(rate.score) || ~isscalar(rate.score) || ~isfinite(rate.score)
    issues(end+1, 1) = "rate_path must be scored consistently with the meeting's actual " + action + "."; %#ok<AGROW>
    return
end

score = rate.score;
switch action
    case "raise"
        if score <= 0
            rationale = "";
            if isfield(rate, "rationale") && (ischar(rate.rationale) || isstring(rate.rationale))
                rationale = lower(string(rate.rationale));
            end
            describedAsFinal = any(contains(rationale, ...
                ["final hike", "last hike", "final increase", "last increase", "final one"]));
            if ~describedAsFinal || score < 0.25
                issues(end+1, 1) = "rate_path.score conflicts with the actual rate hike; a final hike may score +0.25 or higher."; %#ok<AGROW>
            end
        end
    case "cut"
        if score >= 0
            issues(end+1, 1) = "rate_path.score must be negative when the actual decision was a rate cut."; %#ok<AGROW>
        end
end

        function tf = isText(value)
        tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
            (isstring(value) && isscalar(value));
        end
end
