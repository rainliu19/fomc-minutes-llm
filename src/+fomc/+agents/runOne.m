function r = runOne(agent, k, ctx, brief)
%RUNONE Hand the brief to one agent, check what it returns, hand control back.
%   r = fomc.agents.runOne(agent, stage, ctx, brief)
%   The agent runs with ctx.agent set (so every trace event says whose it is) and only its own
%   tools (ctx.allowedTools, enforced by fomc.tools.dispatch). Whatever it returns passes the
%   date gate (nothing dated after the anchor, nothing oversized). The trace says what the agent is
%   briefed with (handoff reads) and what it returned (handback text). A failure is a report with
%   ok=false, never an error, so one agent cannot stop the others. Safe on a thread worker.

reads = {};    % the earlier agents' reports this one is briefed with
if isfield(brief, "reports")
    reads = fieldnames(brief.reports);
end
fomc.trace.logEvent(ctx, "handoff", struct("to", agent.name, "stage", k, "tools", {agent.tools}, "reads", {reads}));
ctx.agent = agent.name;
ctx.allowedTools = agent.tools;
t0 = tic;
try
    r = agent.fn(ctx, brief);
    view = rmfield(r, "calls");
    gate = fomc.guard.checkToolOutput(ctx, view, string(jsonencode(view)));
    if ~gate.ok
        r = fomc.agents.report(agent.name, ok=false, error=gate.message);
    end
catch ME
    r = fomc.agents.report(agent.name, ok=false, error=fomc.trace.scrub(string(ME.message)));
end
r.ms = round(toc(t0) * 1000);
fomc.trace.logEvent(ctx, "handback", struct("to", "organizer", "ok", r.ok, "ms", r.ms, ...
    "nIds", numel(r.ids), "error", r.error, "text", r.text));
end
