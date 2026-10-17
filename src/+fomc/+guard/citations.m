function c = citations(text, ctx, known)
%CITATIONS The paragraphs an answer cites, with exact text, checked.
%   c = fomc.guard.citations(text, ctx, known)
%   A citation is verified only if the paragraph exists, its minutes were public on the
%   anchor date, and the id is in known (ids tools returned this session), which stops
%   made-up ids. The page shows the exact paragraph beside each one.

% One entry per id found in the text
c = struct("id", {}, "ok", {}, "reason", {}, "meetingDate", {}, "section", {}, "paragraph", {}, "text", {});
% Resolve each id to its exact text, and mark it unverified if no tool returned it this session
for id = fomc.guard.idsIn(text).'
    r = fomc.guard.resolveId(ctx, id);
    if r.ok && ~any(known == id)
        r.ok = false;
        r.reason = "no tool returned this id in the session";
    end
    c(end+1) = struct("id", id, "ok", r.ok, "reason", r.reason, "meetingDate", r.meetingDate, ...
        "section", r.section, "paragraph", r.paragraph, "text", r.text); %#ok<AGROW>
end
end
