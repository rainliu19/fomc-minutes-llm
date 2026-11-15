function [pressure, swapMB] = memoryNow()
%MEMORYNOW macOS memory pressure level (1 normal, 2 warning, 4 critical) and swap in use, in MB.
%   Feeds fomc.util.memoryShort (pipeline/score_minutes.m, parallel agent stages).
[~, p] = system("sysctl -n kern.memorystatus_vm_pressure_level");
[~, sw] = system("sysctl -n vm.swapusage");
pressure = str2double(strtrim(p));
swapMB = str2double(regexp(sw, "used = ([\d.]+)M", "tokens", "once"));
end
