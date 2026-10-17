classdef testLeakAndTrace < matlab.unittest.TestCase
    % Cutoff labels and trace hygiene.

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function cutoffLabelsSplitMeetingsIntoGroups(tc)
            cfg = fomc.config(modelCutoff=datetime(2024,6,30), cutoffBufferDays=90);
            d = [datetime(2024,6,30); datetime(2024,7,1); datetime(2024,9,28); datetime(2024,9,29)];
            tc.verifyEqual(fomc.leak.cutoffLabel(d, cfg), ...
                ["before_cutoff"; "near_cutoff"; "near_cutoff"; "after_cutoff"]);
        end

        function unsetCutoffMeansEverythingIsUnverified(tc)
            cfg = fomc.config();
            tc.verifyEqual(fomc.leak.cutoffLabel([datetime(2010,1,1); datetime(2026,1,1)], cfg), ...
                ["unverified"; "unverified"]);
        end

        function apiKeysAreScrubbedFromTheTrace(tc)
            old = getenv("OPENAI_API_KEY");
            tc.addTeardown(@() setenv("OPENAI_API_KEY", old));
            setenv("OPENAI_API_KEY", "sk-test-1234567890abcdef");
            path = string(tempname) + ".jsonl";
            ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), syntheticData(), tracePath=path);
            fomc.trace.logEvent(ctx, "turn_error", struct("message", "401 bad key sk-test-1234567890abcdef"));
            txt = fileread(path);
            tc.verifyFalse(contains(txt, "sk-test-1234567890abcdef"));
            tc.verifySubstring(txt, "[REDACTED]");
        end

        function everyTraceLineIsValidJsonWithTheCommonFields(tc)
            path = string(tempname) + ".jsonl";
            ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), syntheticData(), tracePath=path);
            fomc.trace.logEvent(ctx, "a", struct("x", 1));
            fomc.trace.logEvent(ctx, "b");
            lines = readlines(path);
            lines(lines == "") = [];
            tc.verifyEqual(numel(lines), 2);
            for l = lines.'
                e = jsondecode(l);
                tc.verifyTrue(all(isfield(e, ["time", "runId", "asOf", "type"])));
                tc.verifyEqual(e.asOf, '2020-03-01');
            end
        end
    end
end
