classdef testPathPrefetch < matlab.unittest.TestCase
    % The rate path the harness looks up before the model starts. REAL data, no model.

    properties
        D
        cfg
    end

    % Runs once before the tests: make the test helpers and src/ visible, load the real data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
            tc.cfg = fomc.config(verbose=false);
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function aPastYearQuestionGetsTheLatestEightMeetings(tc)
            [text, recs] = lookup(tc, datetime(2026,10,25), "How have interest rates changed over the past year?");
            tc.verifySubstring(text, "the first increase since 2023-07-26");
            tc.verifySubstring(text, "[2026-09-16/policyAction/1]");
            tc.verifyEqual(recs.name, "getPolicyPath");
            tc.verifyTrue(recs.ok);
            result = jsondecode(recs.result);
            tc.verifyEqual(result.span.meetings, 8);
        end

        function namedYearsSetTheSpan(tc)
            % The evaluation's question: two years named, so that whole span
            [text, recs] = lookup(tc, datetime(2019,1,31), ...
                "How did the Committee's view of interest rate policy change between 2015 and 2018?");
            tc.verifySubstring(text, ": 9 increases");
            tc.verifyEqual(string(recs.args.startDate), "2015-01-01");
            tc.verifyEqual(string(recs.args.endDate), "2018-12-31");
            % One year named: that calendar year (2022 had 7 increases)
            [text, recs] = lookup(tc, datetime(2023,3,1), "How many times did the Fed raise rates in 2022?");
            tc.verifySubstring(text, ": 7 increases");
            tc.verifyEqual(string(recs.args.startDate), "2022-01-01");
        end

        function everydayWordingFires(tc)
            for q = ["Has the Fed been cutting rates lately?", "Is the Fed in a tightening cycle?", ...
                    "How did rates move during 2020?", "What has the Fed done with interest rates over the past two years?"]
                text = lookup(tc, datetime(2026,10,25), q);
                tc.verifySubstring(text, "Rate path worked out by code", q);
            end
        end

        function sinceAYearAndTheLastFewYearsSetTheSpan(tc)
            % "since 2022" runs to the anchor date; "the last three years" is three years back
            [~, recs] = lookup(tc, datetime(2026,10,25), "How many times has the Fed hiked since 2022?");
            tc.verifyEqual(string(recs.args.startDate), "2022-01-01");
            tc.verifyFalse(isfield(recs.args, "endDate"));
            [~, recs] = lookup(tc, datetime(2026,10,7), "How have interest rates changed over the last three years?");
            tc.verifyEqual(string(recs.args.startDate), "2023-10-07");
            % Kept even when the question's focus window is the same three years
            ctx = context(tc, datetime(2026,10,7));
            q = "How have interest rates changed over the last three years?";
            ctx.focus = fomc.focus.window(q, ctx.asOf, tc.cfg);
            [~, recs] = fomc.focus.pathPrefetch(ctx, q);
            result = jsondecode(recs.result);
            tc.verifyGreaterThan(result.span.meetings, 20);
            % Even when the lookup's dates match a "no year" focus window exactly, the tool keeps them
            ctx.focus = struct("start", ctx.asOf - calyears(3), "end", ctx.asOf, "years", 3, ...
                "reason", "no year in the question, so the most recent 3 years", "fromQuestion", false);
            [~, recs] = fomc.focus.pathPrefetch(ctx, q);
            result = jsondecode(recs.result);
            tc.verifyGreaterThan(result.span.meetings, 20, "the lookup's own span must not be replaced");
        end

        function otherQuestionsGetNothing(tc)
            for q = ["What did the Committee decide at its March 2020 meeting?", ...
                    "What did participants say about inflation?", ...
                    "How has the unemployment rate changed over the past year?", ...
                    "How has the rate of inflation changed since 2020?", ...
                    "Has the easing of supply chain pressures continued since last year?", ...
                    "What is the trend in long-term interest rates?", ...
                    "How have mortgage rates changed over the past year?", ...
                    "Did the Fed cut rates in March 2020?", ...
                    "What is the federal funds rate?", ...
                    "Tell me something interesting."]
                [text, recs] = lookup(tc, datetime(2026,10,25), q);
                tc.verifyEqual(text, "", q);
                tc.verifyEmpty(recs, q);
            end
        end

        function itIsAddedAfterTheOtherLookupsAndItsIdsCount(tc)
            % fomc.focus.prefetch adds it after the passages and figures; runTurn remembers the ids
            % in every record, so citing them counts as verified
            ctx = context(tc, datetime(2026,10,25));
            ctx.focus = fomc.focus.window("How have interest rates changed over the past year?", ctx.asOf, tc.cfg);
            [text, recs] = fomc.focus.prefetch(ctx, "How have interest rates changed over the past year?", false);
            names = string({recs.name});
            tc.verifyEqual(names(end), "getPolicyPath");
            tc.verifyLessThan(strfind(text, "Latest figures"), strfind(text, "Rate path"));
            tc.verifyTrue(ismember("2026-09-16/policyAction/1", fomc.guard.idsIn(recs(end).result)));
        end

        function nothingAfterTheAnchorIsAdded(tc)
            % September 2026 minutes were released 2026-10-07: before that, no id from them
            text = lookup(tc, datetime(2026,10,1), "How have interest rates changed over the past year?");
            tc.verifySubstring(text, "not public yet");
            tc.verifyFalse(contains(text, "[2026-09-16/"));
        end

        function prefetchOffMeansNoLookup(tc)
            cfg2 = fomc.config(verbose=false, prefetch=false);
            ctx = fomc.context(datetime(2026,10,25), cfg2, tc.D, tracePath=string(tempname) + ".jsonl");
            tc.verifyEqual(fomc.focus.pathPrefetch(ctx, "How have interest rates changed over the past year?"), "");
        end
    end
end

function ctx = context(tc, asOf)
% Helper: a session context at an anchor date, on the real data
ctx = fomc.context(asOf, tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
end

function [text, recs] = lookup(tc, asOf, question)
% Helper: the path lookup for one question at an anchor date
[text, recs] = fomc.focus.pathPrefetch(context(tc, asOf), question);
end
