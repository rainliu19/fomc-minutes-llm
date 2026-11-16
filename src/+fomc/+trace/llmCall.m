function [text, out, stats] = llmCall(s, history, useTools, format, nvp)
%LLMCALL One model call, traced for the page's agent timeline: what the model was sent, what it answered.
%   [text, out, stats] = fomc.trace.llmCall(s, history, useTools, format, From=agents, Round=n)
%   Calls s.llm exactly as the callers did, and logs, under the agent in s.ctx.agent:
%     "message" events for what is new since the model last spoke (the messages after the history's
%       last assistant message; a context with none yet starts with the system prompt). role,
%       text, and from: the agents whose output a user message carries (the writer's question
%       carries the specialists' reports, a rewrite request carries the critic's).
%     one "model_response" event: the reply, tool calls asked, thinking, time and token counts,
%       which is where the benchmark adds up tokens, so every model call is counted once.
%   Round is the call's number in its loop. Nothing is kept between calls.

arguments
    s (1,1) struct
    history
    useTools (1,1) logical
    format
    nvp.From (1,:) string = strings(1, 0)
    nvp.Round (1,1) double = 1
end
ctx = s.ctx;
msgs = history.Messages;
last = find(cellfun(@(m) string(m.role) == "assistant", msgs), 1, "last");
if isempty(last)
    prompt = "";    % a bare session (a scorer's) may have none
    if isfield(s, "systemPrompt")
        prompt = s.systemPrompt;
    end
    logMessage(ctx, "system", prompt, strings(1, 0));
    last = 0;
elseif nvp.Round == 1 && isempty(nvp.From)
    logMessage(ctx, "note", last + " earlier messages in context", strings(1, 0));
end
for k = last + 1:numel(msgs)
    role = string(msgs{k}.role);
    logMessage(ctx, role, string(msgs{k}.content), nvp.From(1:end * (role == "user")));
end

t0 = tic;
[text, out, stats] = s.llm(history, useTools, format);

n = 0;
if isfield(out, "tool_calls") && ~isempty(out.tool_calls)
    tcs = out.tool_calls;
    if iscell(tcs)
        tcs = [tcs{:}];
    end
    n = numel(tcs);
end
thinking = "";
if isfield(out, "thinking") && ~isempty(out.thinking)
    thinking = string(out.thinking);
    if strlength(thinking) > 4000
        thinking = extractBefore(thinking, 4001) + "...";
    end
end
fomc.trace.logEvent(ctx, "model_response", struct("round", nvp.Round, ...
    "content", fomc.llm.cleanText(string(text)), "nToolCalls", n, "thinking", thinking, ...
    "ms", round(toc(t0) * 1000), "stats", stats));
end

function logMessage(ctx, role, text, from)
fomc.trace.logEvent(ctx, "message", struct("role", role, "text", text, "from", {cellstr(from)}));
end
