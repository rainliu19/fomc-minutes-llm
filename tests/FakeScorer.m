classdef FakeScorer < handle
    %FAKESCORER A stand-in model for scoring tests on the REAL minutes. No Ollama needed.
    %   f = FakeScorer(D);  s = fomc.newSession(asOf, cfg, Llm=@f.call, Data=D);
    %   f = FakeScorer(D, NotDiscussed="balance_sheet")  marks those dimensions not_discussed.
    %
    %   It answers both scorers' prompts: fomc.skills.scoreByDimension's (one dimension per
    %   call, which chat uses) with that one dimension, and fomc.skills.scoreMeeting's (the
    %   whole meeting in one call) with all seven. Each answer passes every check: a verbatim
    %   quote from the text it was given and a rate_path whose sign matches the coded decision.
    %   So a test can check WHICH meeting was scored and how the result is returned, without
    %   depending on a real model's judgement.
    %   f.Dates lists the meetings the scorer asked about, in order (empty = never called);
    %   the calls for one meeting's dimensions count once. f.Calls counts every call.

    properties
        D
        NotDiscussed (1,:) string = strings(1, 0)
        Dates (:,1) string = strings(0, 1)
        Calls (1,1) double = 0
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
            % The scorer's first message holds the meeting date and the text to quote from
            messages = history.Messages;
            if iscell(messages)
                first = messages{1};
            else
                first = messages(1);
            end
            prompt = string(first.content);
            f.Calls = f.Calls + 1;
            oneDimension = regexp(prompt, 'meeting that ended (\d{4}-\d{2}-\d{2})', 'tokens', 'once');
            if ~isempty(oneDimension)
                meetingDate = string(oneDimension{1});
                % The dimension's rubric starts "# <key>"; the passages are "[id] text" blocks
                name = string(regexp(prompt, 'RUBRIC\n# (\w+)', 'tokens', 'once'));
                passages = extractAfter(prompt, "PASSAGES" + newline);
                body = string(regexp(passages, '^\[[^\]]+\] ([^\n]*)', 'tokens', 'once', 'lineanchors'));
                % The first sentence, split as scoreByDimension splits them, so the quote matches it
                sentences = strtrim(string(regexp(body, "(?<=[.!?])\s+(?=[A-Z])", "split")));
                result = f.dimension(name, f.ratePath(meetingDate), sentences(1));
            else
                meetingDate = string(regexp(prompt, 'Score this meeting date: (\d{4}-\d{2}-\d{2})', ...
                    'tokens', 'once'));
                parts = split(prompt, newline + "MINUTES" + newline);
                words = split(strtrim(parts(end)));
                quote = strjoin(words(1:min(12, numel(words))).', " ");
                dims = struct();
                for name = ["rate_path", "inflation", "labor_market", "economic_activity", ...
                        "financial_conditions", "balance_sheet", "risk_balance"]
                    dims.(name) = f.dimension(name, f.ratePath(meetingDate), quote);
                end
                result = struct("meeting_date", meetingDate, "scale", "hawkish_positive", "dimensions", dims);
            end
            if isempty(f.Dates) || f.Dates(end) ~= meetingDate
                f.Dates(end+1, 1) = meetingDate;
            end
            % NaN is written as JSON null, where the schema expects it, as a real model would
            text = string(jsonencode(result));
            out = struct("role", "assistant", "content", text, "thinking", "");
            stats = struct("promptTokens", 0, "outputTokens", 0, "promptMs", 0, "outputMs", 0, "loadMs", 0);
        end
    end

    methods (Access = private)
        function v = ratePath(f, meetingDate)
            % rate_path follows the coded decision, as the guard requires
            k = find(f.D.meetings.MeetingDate == datetime(meetingDate, InputFormat="yyyy-MM-dd"), 1);
            v = 0;
            switch string(f.D.cards.action(k))
                case "raise", v = 0.5;
                case "cut",   v = -0.5;
            end
        end

        function dim = dimension(f, name, ratePath, quote)
            if any(name == f.NotDiscussed)
                dim = struct("status", "not_discussed", "score", NaN, "confidence", NaN, ...
                    "rationale", "Not meaningfully discussed.", "evidence", {{}});
                return
            end
            score = 0;
            if name == "rate_path"
                score = ratePath;
            end
            dim = struct("status", "scored", "score", score, "confidence", "medium", ...
                "rationale", "Fake score for testing.", "evidence", {{struct("quote", quote)}});
        end
    end
end
