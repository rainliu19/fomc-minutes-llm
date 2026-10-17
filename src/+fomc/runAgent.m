function [answer, structured, calls, s] = runAgent(question, asOf, nvp)
%RUNAGENT Ask one question; returns the answer, any structured output and the tool calls.
%   [answer, structured, calls, s] = fomc.runAgent(question, asOf, Name=Value)
%   asOf: anchor date (default: latest release); the agent sees only what was public by then.
%   Config: settings struct. Format: "chat" (default) or "analysis" (structured output with
%   grounding check). MeetingDate: meeting to focus on. Llm: model function for tests.
%   s is the session, to continue with fomc.runTurn(s, ...).

arguments
    question (1,1) string
    asOf (1,1) datetime = NaT
    nvp.Config (1,1) struct = fomc.config()
    nvp.Format (1,1) string {mustBeMember(nvp.Format, ["chat", "analysis"])} = "chat"
    nvp.MeetingDate (1,1) datetime = NaT
    nvp.Llm = []
    nvp.Data = []
    nvp.TracePath (1,1) string = ""
end

% Default anchor: the latest minutes release in the data
if isnat(asOf)
    if isempty(nvp.Data)
        asOf = fomc.latestAnchor();
    else
        asOf = fomc.latestAnchor(nvp.Data);
    end
end
% If a meeting was named, point the question at it
if ~isnat(nvp.MeetingDate)
    question = "Focus on the FOMC meeting that ended on " + fomc.util.fmtDate(nvp.MeetingDate) + ". " + question;
end
% Start a session and run one turn
s = fomc.newSession(asOf, nvp.Config, Llm=nvp.Llm, Data=nvp.Data, TracePath=nvp.TracePath);
[s, answer, structured, calls] = fomc.runTurn(s, question, Format=nvp.Format);
end
