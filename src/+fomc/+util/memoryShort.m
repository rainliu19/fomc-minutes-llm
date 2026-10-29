function tf = memoryShort(pressure, swapMB)
%MEMORYSHORT Whether memory is too short to start another model call on an 8 GB Mac.
%   tf = fomc.util.memoryShort(pressure, swapMB)
%   pressure: macOS memory pressure level (1 normal, 2 warning, 4 critical). swapMB: swap in use.
%   Short at critical pressure, at over 3.6 GB of swap with pressure above normal, or at over
%   6 GB of swap. Swap stays allocated after memory frees up, so 3.6 GB alone does not stop a
%   run while pressure is normal. Used by pipeline/score_minutes.m.

arguments
    pressure (1,1) double
    swapMB (1,1) double
end

tf = pressure == 4 || (swapMB > 3600 && pressure > 1) || swapMB > 6000;
end
