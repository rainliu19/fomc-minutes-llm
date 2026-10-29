%% FOMC project: score each meeting's minutes with the AI, once, and save the scores
% Checks which released minutes have no saved score yet, scores them with
% fomc.skills.scoreByDimension (the fomc-score skill, one dimension per model call), and saves
% each to data/scores/<model>/<meeting>.json (fomc.skills.scoreCache). Rerun it after new
% minutes come out (pipeline/fetch_fomc_minutes.m): only the new meetings are scored.
% Needs Ollama running with the model (the web app starts it; or run "ollama serve").
% About 25 seconds a meeting for the rate path alone, a few minutes for all seven dimensions.
% It stops before a meeting when memory is short (critical pressure, over 3.6 GB of swap with
% pressure above normal, or over 6 GB of swap); run it again to continue, since scored meetings
% are skipped.
% Swap builds up while MATLAB and the model run together on an 8 GB Mac, so set maxMeetings
% (e.g. maxMeetings = 8; run("pipeline/score_minutes.m")) and restart MATLAB and Ollama between runs.

if endsWith(pwd, "pipeline"), cd(".."); end
addpath("src");

% Which dimensions, and which model; the tools read the rate path
dimensions = ["rate_path"];          % or all seven: leave this line out of the call below
cfg = fomc.config(verbose=false);
model = cfg.model;

D = fomc.data.load();
s = fomc.newSession(fomc.latestAnchor(), cfg, TracePath=fullfile("logs", "score-minutes.jsonl"));
M = D.meetings;
if ~exist("maxMeetings", "var"), maxMeetings = Inf; end
done = 0;
for k = 1:height(M)
    meeting = fomc.util.fmtDate(M.MeetingDate(k));
    saved = fomc.skills.scoreCache("read", model, meeting);
    if ~isempty(saved) && all(ismember(dimensions, string(saved.dimensionsScored)))
        continue
    end
    [pressure, swapMB] = memoryNow();
    if fomc.util.memoryShort(pressure, swapMB)
        fprintf("STOP before %s: memory short (pressure %d, %.0f MB swap). Run again to continue.\n", meeting, pressure, swapMB);
        break
    end
    t0 = tic;
    try
        out = fomc.skills.scoreByDimension(s, meeting, Dimensions=dimensions);
    catch ME
        fprintf("FAIL %s: %s\n", meeting, ME.message);
        continue
    end
    fomc.skills.scoreCache("write", model, meeting, out);
    d = out.score.dimensions.(dimensions(1));
    sc = d.score;
    if isempty(sc), sc = NaN; end
    fprintf("%s  %s %5.2f  ok=%d  calls=%d  %.0fs\n", meeting, dimensions(1), sc, out.ok, out.calls, toc(t0));
    done = done + 1;
    if done >= maxMeetings
        break
    end
end

function [pressure, swapMB] = memoryNow()
% macOS memory pressure level (1 normal, 2 warning, 4 critical) and swap in use, in MB
[~, p] = system("sysctl -n kern.memorystatus_vm_pressure_level");
[~, sw] = system("sysctl -n vm.swapusage");
pressure = str2double(strtrim(p));
swapMB = str2double(regexp(sw, "used = ([\d.]+)M", "tokens", "once"));
end
