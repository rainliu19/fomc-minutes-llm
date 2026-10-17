function [startDate, endDate, isDefault] = applyWindow(ctx, startDate, endDate)
%APPLYWINDOW Use the focus window when the model gave no dates.
%   [startDate, endDate, isDefault] = fomc.tools.applyWindow(ctx, startDate, endDate)
%   If the model gave either date, its choice stands (the other end stays open). This only
%   narrows what is looked at; the guardrails enforce the anchor date.

% Fall back to the focus window only if the model gave neither date
isDefault = false;
if isnat(startDate) && isnat(endDate) && ~isnat(ctx.focus.start)
    startDate = ctx.focus.start;
    endDate = ctx.focus.end;
    isDefault = true;
end
end
