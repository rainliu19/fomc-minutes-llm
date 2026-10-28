function [text, recs] = economyPrefetch(ctx, question)
%ECONOMYPREFETCH The economy against the Fed's goals and the latest minutes, looked up before the model starts.
%   [text, recs] = fomc.focus.economyPrefetch(ctx, question)
%   For questions about where policy should go (the next or future decisions, whether policy
%   is too tight or too loose, the Fed's goals, what markets expect), the harness works out
%   the gaps from the goals, jobs and growth, two policy rules, the market's reading, and what
%   the latest minutes say about future meetings and the staff forecast
%   (fomc.data.economyAssessment), and adds the summary to the question. The model is also
%   offered this as the assessEconomy tool, but a small model often skips tools, so the harness
%   runs it through the normal tool path for questions the wording shows are about where policy
%   is going. Other questions get nothing. No model.

text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch || ~asksWherePolicyShouldGo(lower(string(question)))
    return
end

% Run the tool as known on the anchor date, through the normal tool path (guardrails, including
% withholding anything dated later, and trace apply)
[json, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct());
recs(end+1) = rec;
if ~rec.ok
    return
end
r = jsondecode(json);
text = "[How the economy compares with the Fed's goals, and what the latest minutes say about future meetings, " + ...
    "worked out by code from the data and minutes as known on " + r.anchorDate + ". Policy rules are rules of thumb, " + ...
    "not forecasts; quote the minutes and cite their ids, and say what participants expected, never what the " + ...
    "Committee will do:" + newline + r.summary + citeLine(r, lower(string(question))) + "]";
fomc.trace.logEvent(ctx, "prefetch", struct("kind", "economy"));
end

function t = citeLine(r, q)
% How to answer, and the ids of the minutes it quotes, asked for by name at the end, where a small
% model reads them last. A question about what is likely at the next meeting is answered from
% the next-meeting reading at the start (the minutes for direction, the 6-month bill for timing),
% not from the minutes alone: in a backtest the minutes' lean was right about the next decision
% 69% of the time, worse than always guessing a hold. Qwen3 4B also answered without citing the
% quotes when the ask was only at the start. Asked "Should the Fed raise rates at the next
% meeting?", it answered "Yes, the Fed should raise rates" even when told not to say what the Fed
% should do, so a question that asks for a judgment is told what to answer with instead: what
% participants judged appropriate.
t = "";
if ~isfield(r, "minutes") || ~isfield(r.minutes, "views") || isempty(r.minutes.views)
    return
end
% Decoded from the tool's JSON, the views may be a struct array or a cell array
ids = unique(cellfun(@(v) string(v.id), fomc.util.asCell(r.minutes.views)), "stable");
if isfield(r, "nextMeeting")
    t = newline + "If the question asks what is likely at the next meeting, answer from the next-meeting reading " + ...
        "at the start, and say what it rests on: the minutes for the direction of future moves, the 6-month bill " + ...
        "for whether markets expect a move soon.";
end
t = t + newline + "In the answer, cite the minutes you use with their ids, such as [" + ids(1) + "], and say " + ...
    "what participants expected, not what the Fed should or will do.";
if ~isempty(regexp(q, "(?<![a-z])(should|ought to|need to|needs to|is it (right|wise|time) to)(?![a-z])", "once"))
    t = t + newline + "The question asks what the Fed should do. Do not answer yes or no and do not give your " + ...
        "own view: begin with what participants judged appropriate, such as ""Participants judged that further " + ...
        "increases would be appropriate"", and cite it.";
end
end

function tf = asksWherePolicyShouldGo(q)
% The next or future decisions, whether policy is too tight or too loose, the Fed's goals, or
% what markets expect
patterns = [
    "next (fomc |fed )?(meeting|decision|move|step)"
    "(future|upcoming|coming) (fomc |fed )?(meetings?|decisions?|rate (moves|decisions))"
    "(will|could|might|are) (the fed's |interest )?rates (go up|go down|rise|fall|come down|be (raised|cut|lowered))"
    "(should|will|would|could|might) the (fed|fomc|committee) (raise|cut|lower|hike|hold|increase|tighten|ease|pause|keep|change)"
    "what (should|will|would|could|might) the (fed|fomc|committee) do"
    "where (should|will) (interest )?rates (go|be|head)"
    "(more|further|another|any) (rate )?(hikes?|cuts?|increases?)"
    "rate (hikes?|cuts?|increases?) (coming|likely|expected|ahead)"
    "behind the curve|ahead of the curve"
    "too (tight|loose|high|low|restrictive|easy|accommodative)"
    "(how|is|are|still) (policy |rates )?(restrictive|accommodative)"
    "neutral (interest )?rate|r-star|r\*|taylor rule|policy rule"
    "appropriate (level|rate|policy|stance)"
    "dual mandate|maximum employment|full employment|price stability"
    "(inflation|prices?) .*(goal|target)|(goal|target) .*inflation"
    "output gap|overheat\w*|(?<![a-z])slack(?![a-z])"
    "(markets?|investors?|traders?) (expect|are pricing|price in|see)"
    ];
tf = any(~cellfun(@isempty, regexp(q, patterns, "once")));
end
