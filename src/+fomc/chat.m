function s = chat(asOf, nvp)
%CHAT Talk to the agent in the Command Window.
%   fomc.chat() anchors at the latest minutes release; fomc.chat(datetime(2020,4,8)) at another date.
%   Each tool call prints as it runs. Type exit to leave, /clear to start over. Returns the session.

arguments
    asOf (1,1) datetime = NaT
    nvp.Config (1,1) struct = fomc.config()
    nvp.Llm = []
end

% Load the data; default the anchor to the latest minutes release
D = fomc.data.load(nvp.Config.dataDir);
if isnat(asOf)
    asOf = fomc.latestAnchor(D);
end
% Start a session and print a short banner
s = fomc.newSession(asOf, nvp.Config, Llm=nvp.Llm, Data=D);
fprintf("FOMC agent | anchor date %s | model %s\n", fomc.util.fmtDate(asOf), nvp.Config.model);
fprintf("Trace: %s\nType exit to leave, /clear to start over.\n\n", s.ctx.tracePath);

% Read a question; handle exit and /clear; otherwise run a turn and print the answer
while true
    q = strtrim(string(input("YOU: ", "s")));
    if q == ""
        continue
    elseif any(lower(q) == ["exit", "quit"])
        break
    elseif lower(q) == "/clear"
        s = fomc.newSession(asOf, nvp.Config, Llm=nvp.Llm, Data=D);
        fprintf("Conversation cleared.\n\n");
        continue
    end
    [s, answer] = fomc.runTurn(s, q);
    fprintf("\nASSISTANT: %s\n\n", answer);
end
end
