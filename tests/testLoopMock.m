classdef testLoopMock < matlab.unittest.TestCase
    % The agent loop with a scripted fake model: no Ollama, no cost. SYNTHETIC data, anchor 2020-03-01.

    properties
        D
        cfg
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
            tc.cfg = fomc.config(verbose=false, maxToolRounds=4, prefetch=false);
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function toolResultsAreAppendedWithMatchingCallIds(tc)
            script = {
                struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()))
                struct("content", "", "tool_calls", struct("name", "readMinutes", ...
                    "arguments", struct("meetingDate", "2020-01-29", "section", "policyAction")))
                struct("content", "The Committee decided to maintain the target range.")};
            m = fomc.llm.Mock(script);
            [answer, ~, calls, s] = fomc.runAgent("What did they decide?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(answer, "The Committee decided to maintain the target range.");
            tc.verifyEqual(numel(calls), 2);
            tc.verifyEqual([calls.name], ["listMeetings", "readMinutes"]);
            msgs = s.history.Messages;
            roles = cellfun(@(x) string(x.role), msgs);
            tc.verifyEqual(roles(:).', ["user","assistant","tool","assistant","tool","assistant"]);
            tc.verifyEqual(string(msgs{3}.tool_call_id), "call_mock_1_1");
            tc.verifyEqual(string(msgs{5}.tool_call_id), "call_mock_2_1");
        end

        function modelCallsSeeGrowingHistory(tc)
            script = {
                struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()))
                struct("content", "Done.")};
            m = fomc.llm.Mock(script);
            fomc.runAgent("Q", datetime(2020,3,1), Config=tc.cfg, Llm=@m.call, Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            tc.verifyEqual([m.Seen.nMessages], [1 3]);
            tc.verifyTrue(all([m.Seen.useTools]));
        end

        function roundCapStopsTheLoopAndRollsBack(tc)
            script = {struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()))};
            m = fomc.llm.Mock(script);
            [answer, ~, calls, s] = fomc.runAgent("Q", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifySubstring(answer, "tool-call limit");
            tc.verifyEqual(numel(calls), tc.cfg.maxToolRounds);
            tc.verifyEqual(numel(m.Seen), tc.cfg.maxToolRounds);
            tc.verifyEmpty(s.history.Messages, "the failed turn must be rolled back");
        end

        function modelErrorIsReportedAndRolledBack(tc)
            boom = @(h, u, f) error("fomc:test:boom", "connection refused");
            [answer, ~, ~, s] = fomc.runAgent("Q", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=boom, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifySubstring(answer, "Model call failed");
            tc.verifyEmpty(s.history.Messages);
        end

        function blockedToolCallComesBackToTheModelAsAnError(tc)
            script = {
                struct("content", "", "tool_calls", struct("name", "readMinutes", ...
                    "arguments", struct("meetingDate", "2020-03-18", "section", "policyAction")))
                struct("content", "I cannot read that meeting.")};
            m = fomc.llm.Mock(script);
            [answer, ~, calls, s] = fomc.runAgent("Q", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyFalse(calls(1).ok);
            toolMsg = s.history.Messages{3};
            tc.verifySubstring(string(toolMsg.content), "after the anchor date");
            tc.verifyEqual(answer, "I cannot read that meeting.");
        end

        function secondTurnKeepsTheConversation(tc)
            m = fomc.llm.Mock({struct("content", "First."), struct("content", "Second.")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            [s, a1] = fomc.runTurn(s, "one");
            [s, a2] = fomc.runTurn(s, "two");
            tc.verifyEqual([a1 a2], ["First." "Second."]);
            tc.verifyEqual([m.Seen.nMessages], [1 3]);
            tc.verifyEqual(numel(s.history.Messages), 4);
        end

        function emptyModelReplyDoesNotBreakTheSession(tc)
            m = fomc.llm.Mock({struct("content", ""), struct("content", "Now an answer.")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            [s, a1] = fomc.runTurn(s, "one");
            tc.verifySubstring(a1, "no text");
            [~, a2] = fomc.runTurn(s, "two");
            tc.verifyEqual(a2, "Now an answer.");
        end

        function contextBlockHasAnchorAndSnapshot(tc)
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@(h,u,f) deal("", struct()), Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            tc.verifySubstring(s.contextBlock, "ANCHOR DATE: 2020-03-01");
            tc.verifySubstring(s.contextBlock, "UNRATE");
            tc.verifyFalse(contains(s.contextBlock, "4.4"), "March 2020 unemployment was not yet known");
            tc.verifyFalse(contains(s.systemPrompt, "ANCHOR DATE:"), "the system prompt must not depend on the session");
        end

        function traceHasTheWholeStory(tc)
            path = string(tempname) + ".jsonl";
            m = fomc.llm.Mock({
                struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()))
                struct("content", "Done.")});
            fomc.runAgent("Q", datetime(2020,3,1), Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=path);
            lines = readlines(path);
            lines(lines == "") = [];
            types = arrayfun(@(l) string(jsondecode(l).type), lines).';
            % One prefetch call (the data snapshot) runs before the session starts
            tc.verifyEqual(types, ["tool_call" "session_start" "user_message" "model_response" ...
                "tool_call" "model_response" "final_answer"]);
        end

        function everyQuestionCarriesTheFocusNote(tc)
            m = fomc.llm.Mock({struct("content", "ok")});
            [~, ~, ~, s] = fomc.runAgent("What about 2020?", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            first = string(s.history.Messages{1}.content);
            tc.verifySubstring(first, "What about 2020?");
            tc.verifySubstring(first, "[Focus window:");
            tc.verifySubstring(first, "ANCHOR DATE: 2020-03-01");
            tc.verifySubstring(first, "2020-01-29");
            tc.verifyFalse(contains(first, "2020-03-18"), "unreleased minutes must not be listed");
        end
    end
end
