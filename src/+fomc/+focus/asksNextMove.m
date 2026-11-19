function tf = asksNextMove(q)
%ASKSNEXTMOVE True if a (lower-case) question is about the next or future Fed decisions.
%   tf = fomc.focus.asksNextMove(lower(question))
%   "the next meeting", "coming meetings", "will rates go up", "should the Fed raise ...". The minutes
%   agent answers these from what participants expected (fomc.data.policyViews), the economy lookup from
%   the next-meeting reading, and the critic refuses a yes or no or advice for them.

patterns = [
    "next (fomc |fed )?(meeting|decision|move|step)"
    "(future|upcoming|coming) (fomc |fed )?(meetings?|decisions?|rate (moves|decisions))"
    "(will|could|might|are) (the fed's |interest )?rates (go up|go down|rise|fall|come down|be (raised|cut|lowered))"
    "(should|will|would|could|might) the (fed|fomc|committee) (raise|cut|lower|hike|hold|increase|tighten|ease|pause|keep|change)"
    "what (should|will|would|could|might) the (fed|fomc|committee) do"
    ];
tf = any(~cellfun(@isempty, regexp(q, patterns, "once")));
end
