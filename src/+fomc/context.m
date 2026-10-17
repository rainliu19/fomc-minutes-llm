function ctx = context(asOf, cfg, D, nvp)
%CONTEXT Per-run state for tools, guardrails and the trace: anchor date, data, trace file.
%   ctx = fomc.context(asOf)
%   Passed to every tool and guardrail, never in a tool schema. Nothing dated after asOf
%   may reach the model.

arguments
    asOf (1,1) datetime
    cfg (1,1) struct = fomc.config()
    D (1,1) struct = fomc.data.load(cfg.dataDir)
    nvp.tracePath (1,1) string = ""
end

% Store the settings, data and anchor date (time of day removed), plus a unique run id
ctx.cfg = cfg;
ctx.D = D;
ctx.asOf = dateshift(asOf, "start", "day");
ctx.runId = string(datetime("now", Format="yyyyMMdd'T'HHmmss")) + "-" + sprintf("%04d", randi(9999));
% Where this run writes its trace file
if nvp.tracePath == ""
    ctx.tracePath = fullfile(cfg.logDir, "trace-" + ctx.runId + ".jsonl");
else
    ctx.tracePath = nvp.tracePath;
end
ctx.verbose = cfg.verbose;
% Default span of minutes for searches; NaT = no window.
ctx.focus = struct("start", NaT, "end", NaT, "years", cfg.focusYears, "reason", "");
end
