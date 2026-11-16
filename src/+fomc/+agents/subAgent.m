function r = subAgent(ctx, brief, name, evidence, recs, topic)
%SUBAGENT A specialist as a sub-agent: its own prompt and tools, a short model loop on what its code found.
%   r = fomc.agents.subAgent(ctx, brief, name, evidence, recs, topic)
%   The agent's code has already looked things up (evidence, and recs, the tool-call records
%   behind it). The sub-agent is the writer's loop (fomc.runTurn) in a fresh conversation: its
%   system prompt is the body of agents/<name>.md plus the page agents/<name>/<topic>.md for the
%   topic the lookup found (none when topic is "" or has no page), only that file's tools are offered (and
%   enforced by fomc.tools.dispatch), and the evidence is its first message. It may call its
%   tools for more, then writes a short report. Code checks the report (fomc.guard.checkReport:
%   no id or number its sources lack); a bad report, a failed model or no model falls back to
%   the evidence, so facts are never lost. A report that cites none of the evidence's paragraph
%   ids also falls back (the writer cannot cite it). No model call when there is no evidence, when
%   it is shorter than cfg.agentSummarizeOver or the agent's own summarizeOver, whichever is longer
%   (see config.m and agents/market.md), in analysis mode (its grounding check
%   needs the raw text) or without brief.llmFor (a model factory f(cfg, prompt, tools) that
%   fomc.agents.run sets). The agent_model trace event says which, or how long the model took.

if nargin < 6
    topic = "";
end
r = fomc.agents.report(name, text=evidence, calls=recs);
c = fomc.agents.catalog();
a = c([c.name] == name);
limit = max(ctx.cfg.agentSummarizeOver, a.summarizeOver);    % NaN (no own limit) is ignored by max
why = skipReason(evidence, limit, brief);
if why ~= ""
    fomc.trace.logEvent(ctx, "agent_model", struct("skipped", true, "reason", why));
    return
end
prompt = a.body;
if isfield(a.pages, topic)
    prompt = prompt + newline + a.pages.(topic);
end
cfg = ctx.cfg;
cfg.maxToolRounds = 3;
cfg.maxTokens = min(cfg.maxTokens, 400);
ctx.cfg = cfg;
sub = struct("ctx", ctx, "history", messageHistory, "llm", brief.llmFor(cfg, prompt, a.tools), ...
    "systemPrompt", prompt, "contextBlock", "ANCHOR DATE: " + fomc.util.fmtDate(ctx.asOf) + ". Treat it as today.", ...
    "known", strings(0, 1), "ownsLlm", false, "effort", "low", "lastUsedRatePath", false);
lookups = struct("text", evidence, "recs", recs, "structured", []);
t0 = tic;
[~, answer, ~, calls] = fomc.runTurn(sub, brief.question, Lookups=lookups, Nudge=false);
reason = "";
if startsWith(answer, ["Model call failed" "Sorry, I hit my tool-call limit"])
    reason = "model";
else
    bad = fomc.guard.checkReport(answer, [evidence; string({calls.result}).']);
    if ~isempty(bad)
        reason = "not in sources: " + strjoin(bad, ", ");
    elseif ~isempty(fomc.guard.idsIn(evidence)) && isempty(fomc.guard.idsIn(answer))
        reason = "no paragraph id kept";
    end
end
fomc.trace.logEvent(ctx, "agent_model", ...
    struct("skipped", false, "ms", round(toc(t0) * 1000), "fallback", reason ~= "", "reason", reason));
text = evidence;
if reason == ""
    text = answer;
end
r = fomc.agents.report(name, text=text, calls=calls);
end

function why = skipReason(evidence, limit, brief)
% Why the specialist's model does not run ("" when it does); the trace tells the page
why = "";
if evidence == ""
    why = "no evidence to summarize";
elseif brief.isAnalysis
    why = "analysis mode needs the raw text";
elseif strlength(evidence) < limit
    why = "evidence is " + strlength(evidence) + " characters, under this agent's limit of " + limit;
elseif ~isfield(brief, "llmFor") || isempty(brief.llmFor)
    why = "no model connection";
end
end
