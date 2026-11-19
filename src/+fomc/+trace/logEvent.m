function logEvent(ctx, type, payload)
%LOGEVENT Append one JSON line to the run's trace file.
%   fomc.trace.logEvent(ctx, "tool_call", struct(name=..., args=..., result=...))
%   Each line has time, run id, anchor date, event type, the agent when ctx.agent is set, and the payload
%   (a text field is cut at 20,000 characters). API keys are scrubbed.

arguments
    ctx (1,1) struct
    type (1,1) string
    payload (1,1) struct = struct()
end

% Build one event: common fields first, then the payload
ev = struct("time", string(datetime("now", Format="yyyy-MM-dd'T'HH:mm:ss")), ...
    "runId", ctx.runId, "asOf", fomc.util.fmtDate(ctx.asOf), "type", type);
% Inside an agent (fomc.agents.runStage), label every event with it
if isfield(ctx, "agent")
    ev.agent = ctx.agent;
end
for f = string(fieldnames(payload)).'
    v = payload.(f);
    if isstring(v) && isscalar(v) && strlength(v) > 20000   % one text field never fills the log
        v = extractBefore(v, 20001) + "...";
    end
    ev.(f) = v;
end
line = fomc.trace.scrub(string(jsonencode(ev)));

% Make sure the log folder exists, then append the line to the file
folder = fileparts(ctx.tracePath);
if ~isfolder(folder)
    mkdir(folder);
end
fid = fopen(ctx.tracePath, "a", "n", "UTF-8");
if fid < 0
    warning("fomc:trace:open", "Could not open trace file %s.", ctx.tracePath);
    return
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", line);
end
