function s = seed(s, seedJson)
%SEED Replay saved questions and answers into a new session, to continue a chat after a restart.
%   s = fomc.web.seed(s, seedJson), seedJson: JSON array of {q, a, ids}; "" changes nothing.
%   Keeps the last 4 pairs. The first question carries the anchor and data block.
if seedJson == ""
    return
end
items = fomc.util.asCell(jsondecode(seedJson));
items = items(max(1, numel(items) - 3):end);
for i = 1:numel(items)
    q = string(items{i}.q);
    if isempty(s.history.Messages)
        q = s.contextBlock + newline + newline + q;
    end
    a = string(items{i}.a);
    if strlength(a) > 700
        a = extractBefore(a, 701) + "...";
    end
    s.history = addUserMessage(s.history, q);
    s.history = addResponseMessage(s.history, struct("role", "assistant", "content", a));
    if isfield(items{i}, "ids") && ~isempty(items{i}.ids)
        s.known = union(s.known, string(items{i}.ids(:)));
    end
end
end
