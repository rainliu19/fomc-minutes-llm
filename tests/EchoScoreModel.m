classdef EchoScoreModel < handle
    %ECHOSCOREMODEL A stand-in model for the one-dimension-at-a-time scorer, for free tests.
    %   m = EchoScoreModel(failFirst); s.llm = @m.call
    %   Each call scores the dimension it is asked about and quotes, slightly reworded, the first
    %   sentence it was shown; the scorer matches the quote to that sentence word for word. The
    %   first failFirst calls quote made-up text, to exercise the retries. rate_path scores -0.5 for a
    %   meeting whose minutes say "lower the target range", else 0. m.Index counts the calls.

    properties
        FailFirst (1,1) double = 0
        Index (1,1) double = 0
    end

    methods
        function m = EchoScoreModel(failFirst)
            if nargin > 0
                m.FailFirst = failFirst;
            end
        end

        function [text, out, stats] = call(m, history, ~, ~)
            m.Index = m.Index + 1;
            prompt = string(history.Messages{1}.content);
            passages = extractAfter(prompt, "PASSAGES" + newline);
            first = extractBefore(extractAfter(passages, "] ") + newline, newline);
            sentence = strtrim(string(regexp(first, "^.*?[.!?](?=\s|$)", "match", "once")));
            % Reworded a little, as a small model does; the scorer matches it to the sentence
            quote = replace(sentence, "Participants", "The participants");
            if m.Index <= m.FailFirst
                quote = "fabricated text that is not in the minutes";
            end
            score = 0;
            if contains(prompt, "the expected path of the policy rate") && contains(prompt, "lower the target range")
                score = -0.5;
            end
            d = struct("status", "scored", "score", score, "confidence", "medium", ...
                "rationale", "Participants described this topic.", ...
                "evidence", {{struct("quote", quote)}});
            text = string(jsonencode(d));
            out = struct("role", "assistant", "content", text, "thinking", "");
            stats = struct("promptTokens", 0, "outputTokens", 0, "promptMs", 0, "outputMs", 0, "loadMs", 0);
        end
    end
end
