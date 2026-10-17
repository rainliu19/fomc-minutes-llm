function f = ollama(cfg, systemPrompt)
%OLLAMA A function that sends a conversation to the local Ollama model.
%   f = fomc.llm.ollama(cfg, systemPrompt)
%   [text, out, stats] = f(history, useTools, format)
%
%   history: messageHistory. useTools: offer the tools marked expose in fomc.tools.registry.
%   format: [] for text, or a JSON schema for structured output.
%   out: the add-on's assistant message (content, thinking, tool_calls).
%   stats: promptTokens, outputTokens, promptMs, outputMs, loadMs, as reported by Ollama.
%   Tests swap in fomc.llm.Mock.

arguments
    cfg (1,1) struct
    systemPrompt (1,1) string
end

% Two chat objects: one offered the tools, one without (for the structured analysis)
reg = fomc.tools.registry();
tools = [reg([reg.expose]).tool];
withTools = ollamaChat(cfg.model, systemPrompt, Tools=tools, ...
    TimeOut=cfg.timeoutSec, Endpoint=cfg.endpoint, Temperature=cfg.temperature);
plain = ollamaChat(cfg.model, systemPrompt, TimeOut=cfg.timeoutSec, Endpoint=cfg.endpoint, Temperature=cfg.temperature);

% Return a function the agent loop calls for each model request
f = @(history, useTools, format) send(withTools, plain, cfg, history, useTools, format);
end

function [text, out, stats] = send(withTools, plain, cfg, history, useTools, format)
% Choose the chat object, then ask for plain text or for JSON that fits the schema
if useTools
    chat = withTools;
else
    chat = plain;
end
if isempty(format)
    [text, out, response] = generate(chat, history, MaxNumTokens=cfg.maxTokens);
else
    [text, out, response] = generate(chat, history, ResponseFormat=format, ...
        MaxNumTokens=cfg.maxTokensAnalysis);
end
% Pass along Ollama's token counts and timings
stats = statsOf(response);
end

function stats = statsOf(response)
% Token counts and timings from Ollama's reply (durations are in nanoseconds).
stats = struct("promptTokens", 0, "outputTokens", 0, "promptMs", 0, "outputMs", 0, "loadMs", 0);
try
    d = response.Body.Data;
    if iscell(d), d = d{1}; end
    stats.promptTokens = pick(d, "prompt_eval_count", 0);
    stats.outputTokens = pick(d, "eval_count", 0);
    stats.promptMs = round(pick(d, "prompt_eval_duration", 0) / 1e6);
    stats.outputMs = round(pick(d, "eval_duration", 0) / 1e6);
    stats.loadMs = round(pick(d, "load_duration", 0) / 1e6);
catch
    % statistics are optional: never fail a model call over them
end
end

function v = pick(s, name, default)
if isfield(s, name) && isnumeric(s.(name)) && ~isempty(s.(name))
    v = double(s.(name));
else
    v = default;
end
end
