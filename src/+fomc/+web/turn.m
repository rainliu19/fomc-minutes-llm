function json = turn(sessionId, message, asOfText, effort, model, tracePath, seedJson)
%TURN One chat turn for the web app (app.py calls it through the MATLAB Engine).
%   json = fomc.web.turn(sessionId, message, asOfText, effort, model, tracePath, seedJson)
%   The first message of a session creates it, anchored at asOfText (YYYY-MM-DD, or "" for
%   the latest release) and using Ollama model `model` ("" for the default). effort is
%   "low", "medium" or "high" (see fomc.effort) and may change between messages. seedJson
%   is earlier questions and answers as a JSON array of {q, a, ids}; it is used only when
%   the session is new, to continue a chat saved before a restart. Returns JSON: answer,
%   structured, anchorDate, seconds, citations, warning, toolCalls.

arguments
    sessionId (1,1) string
    message (1,1) string
    asOfText (1,1) string
    effort (1,1) string
    model (1,1) string
    tracePath (1,1) string
    seedJson (1,1) string = ""
end

% First message of a web session: create the session, anchored at the date given (or the latest release)
if ~fomc.web.store("has", sessionId)
    cfg = fomc.config(verbose=false, agents=agentMode());
    if model ~= ""
        cfg.model = model;
    end
    asOf = fomc.util.parseDate(asOfText);
    if isnat(asOf)
        asOf = fomc.latestAnchor();
    end
    s = fomc.newSession(asOf, cfg, TracePath=tracePath);
    s = fomc.web.seed(s, seedJson);
    fomc.web.store("set", sessionId, s);
end
s = fomc.web.store("get", sessionId);

% Apply the effort level. A real model connection is rebuilt because it holds the token cap.
[cfg, format] = fomc.effort(s.ctx.cfg, effort);
s.ctx.cfg = cfg;
if s.ownsLlm && s.effort ~= effort
    s.llm = fomc.llm.ollama(cfg, s.systemPrompt);
end
s.effort = effort;

% Run the question through the agent and save the updated session
t0 = tic;
[s, answer, structured, calls] = fomc.agents.run(s, message, Format=format);
fomc.web.store("set", sessionId, s);

% Check the answer (ids, plain words, citations, figures) and choose the warning for the page, if any
[answer, cites, warning] = fomc.guard.review(answer, s, calls, message, format, structured);
isSkillScore = isstruct(structured) && isscalar(structured) && isfield(structured, "skill");
if s.ctx.cfg.agents == "multi" && s.lastAgentIssues ~= ""   % a specialist agent failed: say so first
    warning = strip(s.lastAgentIssues + " " + warning);
end

% Analysis mode: put the written parts in plain words, then show the checked summary, or say it failed
structured = plainStructured(structured);
if format == "analysis" && isstruct(structured) && isfield(structured, "groundingOk") && structured.groundingOk
    % show the checked summary, not the draft
    answer = string(structured.summary) + newline + "Policy stance: " + string(structured.policyStance) + ".";
elseif format == "analysis" && ~isSkillScore && ~any(string({calls.name}) == "prefetchNotice")
    answer = "The analysis did not pass its checks, so it should not be relied on. The model's draft was:" + newline + answer;
end

% Everything the page needs, as JSON
out = struct("answer", answer, "structured", structured, ...
    "anchorDate", fomc.util.fmtDate(s.ctx.asOf), "seconds", toc(t0), ...
    "citations", {num2cell(cites)}, "warning", warning, "toolCalls", {packCalls(calls, lookupsOf(s), agentsOf(s, numel(calls)))});
json = jsonencode(out);
end

function st = plainStructured(st)
% The sentences of a structured analysis in plain words (ids, quotes and figures are untouched).
if ~isstruct(st) || ~isfield(st, "summary")
    return
end
st.summary = fomc.guard.plainEnglish(st.summary);
for name = ["keyDrivers", "caveats"]
    if isfield(st, name) && ~isempty(st.(name))
        items = fomc.util.asCell(st.(name));
        st.(name) = cellfun(@(x) fomc.guard.plainEnglish(x), items, UniformOutput=false);
    end
end
if isfield(st, "evidence") && ~isempty(st.evidence)
    items = fomc.util.asCell(st.evidence);
    for i = 1:numel(items)
        items{i}.claim = fomc.guard.plainEnglish(items{i}.claim);
    end
    st.evidence = items;
end
end

function mode = agentMode()
% "multi" turns on the organizer and specialist agents (set FOMC_AGENTS=multi); anything else is one agent
mode = "single";
if getenv("FOMC_AGENTS") == "multi"
    mode = "multi";
end
end

function n = lookupsOf(s)
% How many of the turn's calls the harness made before the model started
n = 0;
if isfield(s, "lastLookups")
    n = s.lastLookups;
end
end

function who = agentsOf(s, n)
% Which agent made each call: a lookup is its specialist's, anything after is the writer's (single mode: none)
who = repmat("", 1, n);
if s.ctx.cfg.agents == "multi"
    who(:) = "writer";
    k = min(n, numel(s.lastLookupAgents));
    who(1:k) = s.lastLookupAgents(1:k);
end
end

function c = packCalls(calls, nLookups, who)
% Tool calls for display: name, arguments, a clipped result, status, time, and whether the harness
% ran it before the model started (lookup) rather than the model choosing it.
c = cell(numel(calls), 1);
for i = 1:numel(calls)
    result = calls(i).result;
    % Shorten each result so the page stays light
    if strlength(result) > 1500
        result = extractBefore(result, 1501) + "...";
    end
    c{i} = struct("name", calls(i).name, "args", calls(i).args, "result", result, ...
        "ok", calls(i).ok, "ms", calls(i).ms, "lookup", i <= nLookups, "agent", who(i));
end
end
