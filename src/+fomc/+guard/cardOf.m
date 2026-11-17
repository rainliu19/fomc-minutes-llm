function c = cardOf(calls)
%CARDOF The decision card (a getDecision result) the turn looked up, or [] when none was.
%   c = fomc.guard.cardOf(calls)
%   A card whose action could not be read ("unknown") counts as none.

c = [];
for k = numel(calls):-1:1
    if string(calls(k).name) == "getDecision" && calls(k).ok
        r = jsondecode(char(calls(k).result));
        if isfield(r, "action") && r.action ~= "unknown"
            c = r;
            return
        end
    end
end
end
