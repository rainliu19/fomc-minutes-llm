function r = rubricScorer(ctx, brief)
%RUBRICSCORER The rubric scorer (stage 2).
%   r = fomc.agents.rubricScorer(ctx, brief)
%   Score questions: the skill's own scorer (fomc.skills.scoreRequest), one rubric dimension
%   per model call; text is the score JSON and structured its checked result. Household
%   questions: which way the minutes point for the rate (fomc.data.minutesDirection: the saved
%   AI score, else word rules) for the meeting the minutes agent found, else the latest
%   released one; direction and meetingDate go to the consumer view. To replace this agent
%   keep this signature; the contract is in docs/agents.md.

if brief.route == "score"
    s = brief.session;
    s.ctx = ctx;
    [answer, out] = fomc.skills.scoreRequest(s, brief.question);
    r = fomc.agents.report("scorer", text=answer, structured=out);
    return
end
M = ctx.D.meetings;
if isfield(brief.reports, "minutes") && brief.reports.minutes.meetingDate ~= ""
    k = find(M.MeetingDate == fomc.util.parseDate(brief.reports.minutes.meetingDate), 1);
else
    released = find(M.ReleaseDate <= ctx.asOf);
    [~, i] = max(M.MeetingDate(released));
    k = released(i);
end
[~, levels] = fomc.data.ratePath(ctx.D, ctx.asOf);
if isempty(levels)   % no rate data: the direction then comes from the minutes alone
    levels = table(NaT, NaN, NaN, VariableNames=["date" "lower" "upper"]);
end
m = fomc.data.minutesDirection(ctx.D, k, levels(end, :), Model=ctx.cfg.scorerModel);
date = fomc.util.fmtDate(M.MeetingDate(k));
how = replace(replace(m.source, "ai", "the saved AI score"), "rules", "word rules");
r = fomc.agents.report("scorer", meetingDate=date, direction=m.way, text="[Which way the minutes of the meeting that ended " + ...
    date + " point for the rate, by code from " + how + ": " + m.way + ".]");
end
