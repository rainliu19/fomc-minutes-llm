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

        function aFollowUpThatOnlyChangesThePeriodGetsTheRatePath(tc)
            % After a rate question, "And what about in 2022?" means "how did rates move in 2022?"
            cases = ["And what about in 2022?", "2022-01-01", "2022-12-31"
                     "How about 2019?", "2019-01-01", "2019-12-31"
                     "What about since 2020?", "2020-01-01", ""
                     "And over the last three years?", "2023-10-07", ""];
            for i = 1:size(cases, 1)
                ctx = context(tc, datetime(2026,10,7));
                [text, recs] = fomc.focus.pathPrefetch(ctx, cases(i, 1), true);
                tc.verifySubstring(text, "Rate path worked out by code", cases(i, 1));
                tc.verifyEqual(string(recs.args.startDate), cases(i, 2), cases(i, 1));
                if cases(i, 3) == ""
                    tc.verifyFalse(isfield(recs.args, "endDate"), cases(i, 1));
                else
                    tc.verifyEqual(string(recs.args.endDate), cases(i, 3), cases(i, 1));
                end
                % Without a rate question before it, the same follow-up gets nothing
                tc.verifyEqual(fomc.focus.pathPrefetch(ctx, cases(i, 1), false), "", cases(i, 1));
            end
        end

        function moreFollowUpWordingGetsTheRatePath(tc)
            % A follow-up may mention rates; "few" and "several" years are 3, "a couple" 2
            ctx = context(tc, datetime(2026,10,7));
            [~, recs] = fomc.focus.pathPrefetch(ctx, "And rates in 2022?", true);
            tc.verifyEqual(string(recs.args.startDate), "2022-01-01");
            [~, recs] = fomc.focus.pathPrefetch(ctx, "And in the last few years?", true);
            tc.verifyEqual(string(recs.args.startDate), "2023-10-07");
            [~, recs] = fomc.focus.pathPrefetch(ctx, "What about the past couple of years?", true);
            tc.verifyEqual(string(recs.args.startDate), "2024-10-07");
        end

        function yearsBeforeTheMinutesStillGetTheirSpan(tc)
            % The rate data starts in 1990; 2005 had 8 increases
            [text, recs] = lookup(tc, datetime(2026,10,25), "How did rates change in 2005?");
            tc.verifyEqual([string(recs.args.startDate), string(recs.args.endDate)], ["2005-01-01", "2005-12-31"]);
            tc.verifySubstring(text, ": 8 increases");
            [~, recs] = lookup(tc, datetime(2026,10,25), "How did interest rates change between 1995 and 1999?");
            tc.verifyEqual([string(recs.args.startDate), string(recs.args.endDate)], ["1995-01-01", "1999-12-31"]);
        end

        function rangesDecadesAndSinceAreReadAsOneSpan(tc)
            % Trimmed to the rate data (1990 to the anchor year); "since" runs to the anchor date
            cases = ["How did interest rates change between 1985 and 2005?", "1990-01-01", "2005-12-31"
                     "How did rates change between 2020 and 2030?", "2020-01-01", "2026-10-07"
                     "How did rates change in the 2010s?", "2010-01-01", "2019-12-31"
                     "How have rates changed since 2020, especially in 2022?", "2020-01-01", ""
                     "How have rates changed since 1985?", "1990-01-01", ""
                     "Has the Fed raised rates this year?", "2026-01-01", ""];
            for i = 1:size(cases, 1)
                [~, recs] = lookup(tc, datetime(2026,10,7), cases(i, 1));
                tc.assertNotEmpty(recs, cases(i, 1));
                tc.verifyEqual(string(recs.args.startDate), cases(i, 2), cases(i, 1));
                if cases(i, 3) == ""
                    tc.verifyFalse(isfield(recs.args, "endDate"), cases(i, 1));
                else
                    tc.verifyEqual(string(recs.args.endDate), cases(i, 3), cases(i, 1));
                end
            end
            % A follow-up naming a decade
            [~, recs] = fomc.focus.pathPrefetch(context(tc, datetime(2026,10,7)), "What about the 1990s?", true);
            tc.verifyEqual([string(recs.args.startDate), string(recs.args.endDate)], ["1990-01-01", "1999-12-31"]);
        end

        function yearsWithNoRateDataGetNothing(tc)
            % Rather than a different span: years after the anchor, or before the data starts.
            % No tool call is made either (a call with a future date would only be refused).
            ctx = context(tc, datetime(2026,10,25));
            for q = ["How did rates change in 2030?", "How did rates change in 1985?"]
                [text, recs] = fomc.focus.pathPrefetch(ctx, q);
                tc.verifyEqual(text, "", q);
                tc.verifyEmpty(recs, q);
            end
            [text, recs] = fomc.focus.pathPrefetch(ctx, "How about 2027?", true);
            tc.verifyEqual(text, "");
            tc.verifyEmpty(recs);
        end

        function aFollowUpAboutSomethingElseGetsNothing(tc)
            for q = ["What about inflation in 2022?", "And what was the unemployment rate in 2022?", ...
                    "Who dissented in 2022?", "What did they say in 2022?", "What did the Committee decide in 2022?", ...
                    "Thanks!", "And what about the housing market and consumer spending over the course of 2022?", ...
                    "Could you please tell me a little more about what was going on back in 2022?"]   % long: a new question, not a follow-up
                [text, recs] = fomc.focus.pathPrefetch(context(tc, datetime(2026,10,7)), q, true);
                tc.verifyEqual(text, "", q);
                tc.verifyEmpty(recs, q);
            end
        end

        function theSessionCarriesTheRatePathIntoAFollowUp(tc)
            % The whole turn, with a scripted model: the follow-up's message carries the 2022 path
            m = fomc.llm.Mock({struct("content", "Answer.")});
            s = fomc.newSession(datetime(2026,10,7), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
            tc.verifyFalse(s.lastUsedRatePath);
            s = fomc.runTurn(s, "How have interest rates changed over the past year?");
            tc.verifyTrue(s.lastUsedRatePath);
            s = fomc.runTurn(s, "And what about in 2022?");
            sent = lastUserMessage(s);
            tc.verifySubstring(sent, "Rate path worked out by code");
            tc.verifySubstring(sent, "from 2022-01-01 to 2022-12-31");
            tc.verifyTrue(s.lastUsedRatePath, "the follow-up used it too, so a further follow-up can");
            % A question about something else ends the chain
            s = fomc.runTurn(s, "What did participants say about inflation?");
            tc.verifyFalse(s.lastUsedRatePath);
            s = fomc.runTurn(s, "And what about in 2022?");
            tc.verifyFalse(contains(lastUserMessage(s), "Rate path worked out by code"));
        end

        function aTurnThatIsRolledBackLeavesTheMemoryAlone(tc)
            % A model that keeps calling tools hits the round cap; the turn is undone, and the
            % session still remembers that the answer before it used the rate path
            call = struct("name", "listMeetings", "arguments", struct());
            m = fomc.llm.Mock({struct("content", "", "tool_calls", call)});
            cfg2 = fomc.config(verbose=false, maxToolRounds=2);
            s = fomc.newSession(datetime(2026,10,7), cfg2, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
            s.lastUsedRatePath = true;
            [s, answer] = fomc.runTurn(s, "What did participants say about inflation?");
            tc.verifySubstring(answer, "tool-call limit");
            tc.verifyTrue(s.lastUsedRatePath);
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

function t = lastUserMessage(s)
% Helper: the text of the latest message the agent sent the model for a question
t = "";
for i = numel(s.history.Messages):-1:1
    msg = s.history.Messages{i};
    if string(msg.role) == "user"
        t = string(msg.content);
        return
    end
end
end

function [text, recs] = lookup(tc, asOf, question)
% Helper: the path lookup for one question at an anchor date
[text, recs] = fomc.focus.pathPrefetch(context(tc, asOf), question);
end
