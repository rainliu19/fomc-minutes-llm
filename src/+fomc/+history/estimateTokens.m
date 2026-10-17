function n = estimateTokens(history, systemPrompt)
%ESTIMATETOKENS Rough token count of the conversation, to decide when to trim.
%   n = fomc.history.estimateTokens(history, systemPrompt)
%   About 3.3 characters per token, plus an allowance for the tool descriptions.

% Count characters: system prompt, an allowance for tool descriptions, then every message
chars = strlength(systemPrompt) + 3000;
for i = 1:numel(history.Messages)
    m = history.Messages{i};
    if isfield(m, "content") && ~isempty(m.content)
        chars = chars + strlength(string(m.content));
    end
    if isfield(m, "tool_calls") && ~isempty(m.tool_calls)
        chars = chars + 120;
    end
end
% Convert characters to tokens
n = ceil(chars / 3.3);
end
