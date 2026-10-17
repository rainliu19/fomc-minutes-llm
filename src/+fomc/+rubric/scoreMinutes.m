function s = scoreMinutes(minutesText, meetingDate)
%SCOREMINUTES Rubric score of whether a meeting's direction is good for the US consumer.
%   s = fomc.rubric.scoreMinutes(minutesText, meetingDate)
%
%   STUB (Aarya owns the rubric). Fixes the interface; see docs/agent_interface.md.
%   Input is the minutes text only, so the score cannot inherit errors from the agent's
%   analysis. The real version makes its own model call using cfg.scorerModel.
%
%   s: meetingDate (YYYY-MM-DD), criteria (struct array: title, reason, pass), aggregate
%   (0 to 1), direction ("positive" | "neutral" | "negative" | "unscored"), stub (true
%   until the real rubric replaces this file).

arguments
    minutesText (1,1) string %#ok<INUSA>   % the stub ignores it; the real rubric reads it
    meetingDate (1,1) string
end

s = struct("meetingDate", meetingDate, ...
    "criteria", struct("title", {}, "reason", {}, "pass", {}), ...
    "aggregate", NaN, "direction", "unscored", "stub", true);
end
