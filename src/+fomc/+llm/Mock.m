classdef Mock < handle
    %MOCK A scripted stand-in for the model, for free tests.
    %   m = fomc.llm.Mock(script); f = @(history, useTools, format) m.call(history, useTools, format)
    %   script: cell array, one struct per model call with content and optional tool_calls
    %   (struct array of name, arguments). Calls past the end reuse the last entry.
    %   m.Seen records what each call received.

    properties
        Script cell
        Index (1,1) double = 0
        Seen struct = struct("nMessages", {}, "useTools", {}, "format", {})
    end

    methods
        function m = Mock(script)
            m.Script = script;
        end

        function [text, out, stats] = call(m, history, useTools, format)
            % Record what the agent sent, then return the next scripted reply
            m.Index = m.Index + 1;
            m.Seen(end+1) = struct("nMessages", numel(history.Messages), ...
                "useTools", useTools, "format", {format});
            entry = m.Script{min(m.Index, numel(m.Script))};
            text = string(entry.content);
            stats = struct("promptTokens", 0, "outputTokens", 0, "promptMs", 0, "outputMs", 0, "loadMs", 0);
            out = struct("role", "assistant", "content", text, "thinking", "");
            % Scripted tool calls get ids, as the real model's do
            if isfield(entry, "tool_calls") && ~isempty(entry.tool_calls)
                tcs = entry.tool_calls;
                calls = repmat(struct("id", "", "function", struct()), 1, numel(tcs));
                for k = 1:numel(tcs)
                    calls(k).id = "call_mock_" + m.Index + "_" + k;
                    calls(k).function = struct("index", k - 1, "name", tcs(k).name, ...
                        "arguments", tcs(k).arguments);
                end
                out.tool_calls = calls;
            end
        end
    end
end
