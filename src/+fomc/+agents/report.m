function r = report(agent, nvp)
%REPORT What a specialist agent hands back to the organizer: the agent contract.
%   r = fomc.agents.report("market", text=..., ids=..., ok=false, error=...)
%   Every specialist (fomc.agents.minutesRetriever, marketData, rubricScorer, consumerView)
%   returns one of these, built here so the fields and types stay the same for all of them.
%     text          the facts the writer sees: dated figures and paragraph ids, as found by code
%     ids           paragraph ids the text rests on (default: those in the calls' results)
%     calls         tool-call records (name, args, result, ok, ms) behind the text
%     meetingDate   the meeting the question is about, YYYY-MM-DD ("" if none)
%     direction     which way the minutes point for the rate, for the consumer view
%     structured    the skill's score output, for score questions
%     ok, error     a failed agent returns ok=false and says why; it never throws
%     ms            time taken (set by fomc.agents.runStage)

arguments
    agent (1,1) string
    nvp.ok (1,1) logical = true
    nvp.text (1,1) string = ""
    nvp.ids (:,1) string = strings(0, 1)
    nvp.calls struct = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {})
    nvp.meetingDate (1,1) string = ""
    nvp.direction (1,1) string = ""
    nvp.structured = []
    nvp.error (1,1) string = ""
    nvp.ms (1,1) double = 0
end
r = nvp;
r.agent = agent;
% The paragraph ids are the ones in the tool results behind the text, unless given
if isempty(r.ids) && ~isempty(r.calls)
    r.ids = fomc.guard.idsIn(string({r.calls.result}));
end
end
