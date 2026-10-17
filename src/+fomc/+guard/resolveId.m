function r = resolveId(ctx, id)
%RESOLVEID Turn a paragraph id into its exact text, if it may be shown.
%   r = fomc.guard.resolveId(ctx, id)
%   r.ok is false, with a reason, if the id does not exist or its minutes were not public
%   on the anchor date; otherwise r has meetingDate, section, paragraph and text.

id = string(id);
r = struct("ok", false, "reason", "", "meetingDate", "", "section", "", "paragraph", 0, "text", "");
% Find the paragraph
P = ctx.D.paras;
k = find(P.id == id, 1);
if isempty(k)
    r.reason = "no such paragraph";
    return
end
% Refuse if its minutes were not yet public on the anchor date
M = ctx.D.meetings(P.meetingIdx(k), :);
if M.ReleaseDate > ctx.asOf
    r.reason = "those minutes were not public on the anchor date";
    return
end
% Allowed: return the exact text
r.ok = true;
r.meetingDate = fomc.util.fmtDate(M.MeetingDate);
r.section = P.section(k);
r.paragraph = P.paraIdx(k);
r.text = P.text(k);
end
