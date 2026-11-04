classdef FakeScorer < handle
    %FAKESCORER A stand-in model for scoring tests on the REAL minutes. No Ollama needed.
    %   f = FakeScorer(D);  s = fomc.newSession(asOf, cfg, Llm=@f.call, Data=D);
    %   f = FakeScorer(D, NotDiscussed="balance_sheet")  marks those dimensions not_discussed.
    %
    %   It reads the meeting date and minutes out of the scorer's prompt and returns a score
    %   that passes every check: a verbatim quote from those minutes and a rate_path whose
    %   sign matches the coded decision. So a test can check WHICH meeting was scored and
    %   how the result is returned, without depending on a real model's judgement.
    %   f.Dates lists the meeting dates the scorer asked for, in order (empty = never called).

    properties
        D
        NotDiscussed (1,:) string = strings(1, 0)
        Dates (:,1) string = strings(0, 1)
    end

    methods
        function f = FakeScorer(D, nvp)
            arguments
                D (1,1) struct
                nvp.NotDiscussed (1,:) string = strings(1, 0)
            end
            f.D = D;
            f.NotDiscussed = nvp.NotDiscussed;
        end

        function [text, out, stats] = call(f, history, ~, ~)
            % The scorer's first message holds the meeting date and, last, the minutes text
            messages = history.Messages;
            if iscell(messages)
                first = messages{1};
            else
                first = messages(1);
            end
            prompt = string(first.content);
            meetingDate = string(regexp(prompt, 'Score this meeting date: (\d{4}-\d{2}-\d{2})', ...
                'tokens', 'once'));
            f.Dates(end+1, 1) = meetingDate;
            parts = split(prompt, newline + "MINUTES" + newline);
            words = split(strtrim(parts(end)));
            quote = strjoin(words(1:min(12, numel(words))).', " ");

            % rate_path follows the coded decision, as the guard requires
            k = find(f.D.meetings.MeetingDate == datetime(meetingDate, InputFormat="yyyy-MM-dd"), 1);
            ratePath = 0;
            switch string(f.D.cards.action(k))
                case "raise", ratePath = 0.5;
                case "cut",   ratePath = -0.5;
            end

            names = ["rate_path", "inflation", "labor_market", "economic_activity", ...
                "financial_conditions", "balance_sheet", "risk_balance"];
            dims = struct();
            for name = names
                if any(name == f.NotDiscussed)
                    dims.(name) = struct("status", "not_discussed", "score", [], "confidence", [], ...
                        "rationale", "Not meaningfully discussed.", "evidence", {{}});
                else
                    score = 0;
                    if name == "rate_path"
                        score = ratePath;
                    end
                    dims.(name) = struct("status", "scored", "score", score, "confidence", "medium", ...
                        "rationale", "Fake score for testing.", "evidence", {{struct("quote", quote)}});
                end
            end
            result = struct("meeting_date", meetingDate, "scale", "hawkish_positive", "dimensions", dims);
            % Write JSON null where the schema expects it, as a real model would
            text = string(jsonencode(result));
            text = replace(text, ["""score"":[]", """confidence"":[]"], ...
                ["""score"":null", """confidence"":null"]);
            out = struct("role", "assistant", "content", text, "thinking", "");
            stats = struct("promptTokens", 0, "outputTokens", 0, "promptMs", 0, "outputMs", 0, "loadMs", 0);
        end
    end
end
