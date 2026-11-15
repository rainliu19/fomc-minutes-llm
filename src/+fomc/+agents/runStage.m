function reports = runStage(ctx, stage, k, brief)
%RUNSTAGE Run the agents of one stage and return their reports, in the stage's order.
%   reports = fomc.agents.runStage(ctx, stage, k, brief)
%   One after another by default: a stage is mostly quick lookups and the one local model
%   answers one call at a time anyway. With cfg.parallel and more than one agent, they run at
%   the same time on thread workers (no new process, no second model; needs Parallel Computing
%   Toolbox, else serial), unless memory is short
%   (fomc.util.memoryShort). Each worker writes its trace to its own file; the lines are added
%   to the run's trace in the stage's order, so they never interleave.

n = numel(stage);
par = ctx.cfg.parallel && n > 1 && license("test", "Distrib_Computing_Toolbox") == 1;
if par
    [pressure, swapMB] = fomc.util.memoryNow();
    if fomc.util.memoryShort(pressure, swapMB)
        par = false;
        fomc.trace.logEvent(ctx, "parallel_off", struct("reason", "memory", "pressure", pressure, "swapMB", swapMB));
    end
end
fomc.trace.logEvent(ctx, "stage", struct("stage", k, "agents", {[stage.name]}, "parallel", par));
if ~par
    reports = arrayfun(@(a) fomc.agents.runOne(a, k, ctx, brief), stage);
    return
end

tmp = arrayfun(@(~) string(tempname) + ".jsonl", 1:n);
for i = 1:n
    wctx = ctx;
    wctx.tracePath = tmp(i);
    wctx.verbose = false;
    jobs(i) = parfeval(backgroundPool, @fomc.agents.runOne, 1, stage(i), k, wctx, brief); %#ok<AGROW>
end
reports = repmat(fomc.agents.report("x"), 1, n);
for i = 1:n
    try
        reports(i) = fetchOutputs(jobs(i));
    catch ME
        reports(i) = fomc.agents.report(stage(i).name, ok=false, error=fomc.trace.scrub(string(ME.message)));
    end
    if isfile(tmp(i))
        writelines(strip(fileread(tmp(i)), "right"), ctx.tracePath, WriteMode="append");
        delete(tmp(i));
    end
end
end
