classdef testEffort < matlab.unittest.TestCase
    % Effort levels and continuing a saved chat. SYNTHETIC data, no model.

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
            tc.cfg = fomc.config(verbose=false);
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function lowKeepsTheDefaultsAndChats(tc)
            [c, f] = fomc.effort(tc.cfg, "low");
            tc.verifyEqual(f, "chat");
            tc.verifyEqual(c.maxTokens, fomc.config().maxTokens);
            tc.verifyEqual(c.prefetchHits, 3);
        end

        function mediumDoesMoreWorkButStillChats(tc)
            [c, f] = fomc.effort(tc.cfg, "medium");
            tc.verifyEqual(f, "chat");
            tc.verifyGreaterThan(c.maxTokens, fomc.config().maxTokens);
            tc.verifyEqual(c.prefetchHits, 5);
        end

        function highWritesTheCheckedAnalysis(tc)
            [~, f] = fomc.effort(tc.cfg, "high");
            tc.verifyEqual(f, "analysis");
        end

        function anUnknownLevelIsRejected(tc)
            tc.verifyError(@() fomc.effort(tc.cfg, "extreme"), "MATLAB:validators:mustBeMember");
        end

        function aSavedChatIsReplayedIntoANewSession(tc)
            seed = jsonencode({struct("q", "What did they decide?", "a", "They held [2020-01-29/policyAction/1].", ...
                "ids", {{"2020-01-29/policyAction/1"}})});
            m = fomc.llm.Mock({struct("content", "ok")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            id = "seed-" + string(randi(1e9));
            fomc.web.store("set", id, s);
            cleanup = onCleanup(@() fomc.web.store("remove", id));
            % an existing session ignores the seed
            fomc.web.turn(id, "Another question", "", "low", "", "", seed);
            tc.verifyEqual(numel(fomc.web.store("get", id).history.Messages), 2, "a seeded session would hold 4");
        end

        function seedRestoresHistoryAndCitableIds(tc)
            seed = jsonencode({struct("q", "Q1", "a", "A1", "ids", {{"2020-01-29/policyAction/1"}})});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@(h,u,f) deal("", struct()), Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            s = fomc.web.seed(s, seed);
            tc.verifyEqual(numel(s.history.Messages), 2);
            tc.verifySubstring(string(s.history.Messages{1}.content), "ANCHOR DATE: 2020-03-01");
            tc.verifyEqual(s.known, "2020-01-29/policyAction/1");
        end

        function onlyTheLastFourPairsAreKept(tc)
            pairs = arrayfun(@(i) struct("q", "Q" + i, "a", "A" + i, "ids", {{}}), 1:6);
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@(h,u,f) deal("", struct()), Data=tc.D, ...
                TracePath=string(tempname)+".jsonl");
            s = fomc.web.seed(s, jsonencode(pairs));
            tc.verifyEqual(numel(s.history.Messages), 8);
            tc.verifySubstring(string(s.history.Messages{1}.content), "Q3");
        end
    end
end
