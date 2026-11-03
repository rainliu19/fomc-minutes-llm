function output = scoreMeeting(s, meetingDate)
%SCOREMEETING Generate and validate one meeting's FOMC-score skill output.
%   output = fomc.skills.scoreMeeting(s) scores the latest released meeting.
%   output = fomc.skills.scoreMeeting(s, meetingDate) scores a specific YYYY-MM-DD.
%   output.score contains the model result; output.ok and output.issues report validation.

arguments
    s (1,1) struct
    meetingDate (1,1) string = ""
end

ctx = s.ctx;
M = ctx.D.meetings;
available = find(M.ReleaseDate <= ctx.asOf);
if isempty(available)
    error("fomc:skills:noReleasedMeetings", "No meeting minutes were released by the anchor date.");
end
if strlength(strtrim(meetingDate)) == 0
    [~, order] = sort(M.ReleaseDate(available), "descend");
    row = available(order(1));
    meetingDate = fomc.util.fmtDate(M.MeetingDate(row));
else
    d = fomc.util.parseDate(meetingDate);
    if isnat(d)
        error("fomc:skills:invalidMeetingDate", "meetingDate must be written YYYY-MM-DD.");
    end
    row = find(M.MeetingDate == d & M.ReleaseDate <= ctx.asOf, 1);
    if isempty(row)
        error("fomc:skills:meetingUnavailable", ...
            "No minutes for meeting %s are available by anchor date %s.", meetingDate, fomc.util.fmtDate(ctx.asOf));
    end
    meetingDate = fomc.util.fmtDate(d);
end

releaseDate = fomc.util.fmtDate(M.ReleaseDate(row));
minutesText = string(M.Body(row));
rubrics = ["00_scale.md", "ratePath.md", "inflation.md", "laborMarket.md", ...
    "economicActivity.md", "financialConditions.md", "balanceSheet.md", "riskBalance.md"];
rubricText = strings(numel(rubrics), 1);
for i = 1:numel(rubrics)
    rubricText(i) = fomc.skills.read("fomc-score", "rubric/" + rubrics(i));
end

instructions = fomc.skills.read("fomc-score");
schema = fomc.skills.read("fomc-score", "schema.json");
prompt = "Score the FOMC minutes using the skill instructions and rubric below. Return only the JSON object that matches the supplied schema. " + ...
    "Score this meeting date: " + meetingDate + ". Its minutes release date is " + releaseDate + ...
    ". Use only the minutes text below; do not use later knowledge. Follow the rubric's per-dimension scoring and quote rules." + ...
    newline + newline + "SKILL INSTRUCTIONS" + newline + instructions + ...
    newline + newline + "RUBRICS" + newline + strjoin(rubricText, string(newline) + newline) + ...
    newline + newline + "MINUTES" + newline + minutesText;
history = addUserMessage(messageHistory, prompt);

maxAttempts = 3;
failures = strings(0, 1);
score = struct();
for attempt = 1:maxAttempts
    t0 = tic;
    [text, ~, stats] = s.llm(history, false, schema);
    content = strtrim(string(text));
    parseFailure = "";
    try
        score = jsondecode(content);
    catch ME
        score = struct();
        parseFailure = "The model response was not valid JSON: " + string(ME.message);
    end
    if parseFailure ~= ""
        failures = parseFailure;
    else
        failures = fomc.guard.validateScores(score, minutesText, meetingDate, ctx.D);
    end
    fomc.trace.logEvent(ctx, "skill_score_validation", struct( ...
        "meetingDate", meetingDate, "releaseDate", releaseDate, "attempt", attempt, ...
        "ok", isempty(failures), "issues", failures, "ms", round(toc(t0) * 1000), "stats", stats));

    history = addResponseMessage(history, struct("role", "assistant", "content", content));
    if isempty(failures) || attempt == maxAttempts
        break
    end
    history = addUserMessage(history, ...
        "These checks failed: " + strjoin(failures, " ") + ...
        " Fix only the affected dimensions and return the complete JSON object again. " + ...
        "Keep every quote verbatim from the supplied minutes.");
end

output = struct("score", score, "ok", isempty(failures), "issues", failures, ...
    "failedDimensions", dimensionsInFailures(failures), "attempts", attempt);
end

function dimensions = dimensionsInFailures(issues)
allDimensions = ["rate_path", "inflation", "labor_market", "economic_activity", ...
    "financial_conditions", "balance_sheet", "risk_balance"];
dimensions = strings(0, 1);
for name = allDimensions
    if any(contains(issues, name))
        dimensions(end+1, 1) = name; %#ok<AGROW>
    end
end
if ~isempty(issues) && isempty(dimensions)
    dimensions = allDimensions(:);
end
end
