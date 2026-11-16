classdef testAgentsCritic < matlab.unittest.TestCase
    % The critic: a code check, then at most one rewrite. Scripted model, SYNTHETIC data, anchor 2020-03-01.

    properties
        D
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
        end
    end

    methods (Test)
        function aCleanAnswerCostsNoExtraModelCall(tc)
            [~, m, s] = tc.ask("Hello there.", "Fine.");
            tc.verifyEqual(numel(m.Seen), 1);
            tc.verifyFalse(s.lastReview.unverified);
            tc.verifyEqual(s.lastReview.rounds, 1);
        end

        function aFailedCheckGetsOneRewriteAndTheHistoryKeepsOnlyTheRewrite(tc)
            [a, m, s] = tc.ask("Hello there.", "The range is 1-1/2 to 1-3/4 percent.", "The Committee held the rate.");
            tc.verifyEqual(a, "The Committee held the rate.");
            tc.verifyEqual(numel(m.Seen), 2);
            msgs = s.history.Messages;
            tc.verifyEqual(numel(msgs), 2, "the feedback message must not stay in the history");
            tc.verifyEqual(string(msgs{end}.content), a);
            tc.verifyFalse(s.lastReview.unverified);
            tc.verifyEqual(s.lastReview.rounds, 2);
        end

        function twoFailuresMarkTheAnswerUnverifiedWithoutLooping(tc)
            [~, m, s] = tc.ask("Hello there.", "The range is 1-1/2 to 1-3/4 percent.", "The range is 1-1/2 to 1-3/4 percent.");
            tc.verifyEqual(numel(m.Seen), 2);
            tc.verifyTrue(s.lastReview.unverified);
            tc.verifyNotEmpty(s.lastReview.issues);
        end

        function aRewriteThatCallsToolsIsDroppedAndTheDraftIsKept(tc)
            bad = struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()));
            [a, ~, s] = tc.ask("Hello there.", "The range is 1-1/2 to 1-3/4 percent.", bad);
            tc.verifyEqual(a, "The range is 1-1/2 to 1-3/4 percent.");
            tc.verifyTrue(s.lastReview.unverified);
        end

        function aYesOrNoOrWhatTheFedShouldDoToANextMoveQuestionGetsOneRewrite(tc)
            q = "Should the Fed raise rates at the next meeting?";
            rewrite = "Participants did not expect a change [2020-01-29/policyAction/1].";
            [a, m] = tc.ask(q, "Yes, the Fed should raise rates [2020-01-29/policyAction/1].", rewrite);
            tc.verifyEqual(a, rewrite);
            tc.verifyEqual(numel(m.Seen), 2);
            [~, m2] = tc.ask(q, "Participants expected rates to hold [2020-01-29/policyAction/1].");
            tc.verifyEqual(numel(m2.Seen), 1, "an answer about what participants expected passes");
        end

        function criticRoundsAreCappedInCode(tc)
            cfg = fomc.config(verbose=false, criticRounds=1);
            [~, m, s] = tc.ask("Hello there.", "The range is 1-1/2 to 1-3/4 percent.", "Fine.", cfg);
            tc.verifyEqual(numel(m.Seen), 1);
            tc.verifyTrue(s.lastReview.unverified);
        end

        function criticEventsAreTraced(tc)
            tp = string(tempname) + ".jsonl";
            tc.ask("Hello there.", "The range is 1-1/2 to 1-3/4 percent.", "Fine.", [], tp);
            ev = traceEvents(tp);
            c = ev(cellfun(@(e) string(e.type) == "critic", ev));
            tc.verifyEqual(cellfun(@(e) e.pass, c).', [false true]);
        end
    end

    methods
        function [answer, m, s] = ask(tc, q, varargin)
            % Run one multi-agent turn; varargin: scripted replies (text or reply struct), then optional cfg and trace path
            script = {};
            cfg = fomc.config(verbose=false);
            tp = string(tempname) + ".jsonl";
            for i = 1:numel(varargin)
                v = varargin{i};
                if isstruct(v) && isfield(v, "content")
                    script{end+1} = v; %#ok<AGROW>
                elseif isstruct(v)
                    cfg = v;
                elseif isstring(v) && endsWith(v, ".jsonl")
                    tp = v;
                elseif ~isempty(v)
                    script{end+1} = struct("content", v); %#ok<AGROW>
                end
            end
            m = fomc.llm.Mock(script);
            [answer, ~, ~, s] = fomc.runAgent(q, datetime(2020,3,1), Config=cfg, Llm=@m.call, Data=tc.D, TracePath=tp);
        end
    end
end
