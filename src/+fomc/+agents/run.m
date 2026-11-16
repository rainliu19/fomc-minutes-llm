function [s, answer, structured, calls] = run(s, msg, nvp)
%RUN One user turn through the organizer: route, run the specialists in stages, write, check.
%   [s, answer, structured, calls] = fomc.agents.run(s, msg, Format="chat" | "analysis")
%   The entry for every turn (web app, fomc.runAgent, fomc.chat):
%     1. fomc.agents.route picks the stages (agents/organizer.md);
%     2. each stage's agents run (fomc.agents.runStage) and hand back reports;
%     3. their texts become the lookups the writer sees, in place of fomc.focus.prefetch, and
%        fomc.runTurn runs its usual loop on them to write the answer (a failed agent is named
%        in the lookups, so the answer says that part is missing);
%     4. fomc.agents.critic checks the answer.
%   Score questions take the scorer's answer directly. Trace events from
%   inside an agent carry its name; s.lastLookupAgents says which agent made each lookup and
%   s.lastAgentIssues which agents failed ("" if none).

arguments
    s (1,1) struct
    msg (1,1) string
    nvp.Format (1,1) string {mustBeMember(nvp.Format, ["chat", "analysis"])} = "chat"
end
ctx = s.ctx;
ctx.focus = fomc.focus.window(msg, ctx.asOf, ctx.cfg);
ctx.agent = "organizer";
[stages, route] = fomc.agents.route(msg);
planned = [stages{:}];
fomc.trace.logEvent(ctx, "route", struct("route", route, "agents", {[planned.name]}));

% Brief each stage with the question and the reports so far (reports.<agent>)
llmFor = [];
if s.ownsLlm
    llmFor = @(cfg, prompt, tools) fomc.llm.ollama(cfg, prompt, Tools=tools);
elseif isfield(s, "agentLlm")
    llmFor = s.agentLlm;
end
brief = struct("llmFor", {llmFor}, "question", msg, "isAnalysis", nvp.Format == "analysis", "route", route, ...
    "followsRatePath", isfield(s, "lastUsedRatePath") && s.lastUsedRatePath, "reports", struct(), "session", []);
if route == "score"
    brief.session = s;
end
done = cell(1, numel(stages));
for k = 1:numel(stages)
    done{k} = fomc.agents.runStage(ctx, stages{k}, k, brief);
    for r = done{k}
        brief.reports.(r.agent) = r;
    end
end
reports = [done{:}];

% The writer's lookups: each report's text in stage order; a failed agent is named instead
text = [reports.text];
bad = ~[reports.ok];
why = "The " + [reports(bad).agent] + " agent could not report (" + [reports(bad).error] + ").";
text(bad) = "[" + why + " Say plainly that this part is missing.]";
lookups = struct("text", strjoin(text(text ~= ""), newline), "recs", [reports.calls], ...
    "structured", reports(end).structured);
s.ctx = ctx;
s.lastLookupAgents = repelem([reports.agent], arrayfun(@(r) numel(r.calls), reports));
s.lastAgentIssues = strjoin(why, " ");

[s, answer, structured, calls] = fomc.runTurn(s, msg, Format=nvp.Format, Lookups=lookups);
if route ~= "score" && nvp.Format == "chat" && ~any(string({calls.name}) == "prefetchNotice")
    [s, answer] = fomc.agents.critic(s, msg, answer, calls);
end
end
