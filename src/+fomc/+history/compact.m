function [h, n] = compact(history, keepLast)
%COMPACT Replace old tool results with a one-line stub to free context.
%   [h, n] = fomc.history.compact(history, keepLast)
%   Keeps all user and assistant messages and the last keepLast tool results; n = replaced.

% Find the tool results older than the last keepLast
msgs = history.Messages;
isTool = cellfun(@(m) string(m.role) == "tool", msgs);
toolIdx = find(isTool);
older = toolIdx(1:max(0, numel(toolIdx) - keepLast));
% Rebuild the history message by message, shrinking old tool results to a stub
h = messageHistory;
n = 0;
for i = 1:numel(msgs)
    m = msgs{i};
    switch string(m.role)
        case "user"
            h = addUserMessage(h, string(m.content));
        case "assistant"
            msg = struct("role", "assistant", "content", string(m.content));
            if isfield(m, "tool_calls") && ~isempty(m.tool_calls)
                tc = m.tool_calls;
                if iscell(tc), tc = tc{1}; end
                msg.tool_calls = tc;
            end
            h = addResponseMessage(h, msg);
        case "tool"
            content = string(m.content);
            if any(older == i) && strlength(content) > 200
                content = "[Earlier result of " + string(m.name) + " removed to save space. Call the tool again if needed.]";
                n = n + 1;
            end
            h = addToolMessage(h, m.tool_call_id, string(m.name), content);
    end
end
end
