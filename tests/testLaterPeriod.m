classdef testLaterPeriod < matlab.unittest.TestCase
    % A question that names a month the data cannot show yet is answered by the harness, not the model.
    % SYNTHETIC data, anchor 2020-03-01: UNRATE is known up to January 2020 (February came out on 2020-03-06),
    % and the minutes of the 2020-03-18 meeting are not public. The real-data check over the lookahead key is in
    % testLookaheadGate.

    properties
        D
        ctx
        cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
            tc.cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname)+".jsonl");
        end
    end

    methods (Test)
        function monthsAreFoundByNameAndIsoDatesAreNot(tc)
            tc.verifyEqual(fomc.focus.monthsNamed("What was it in March 2020?"), datetime(2020,3,1));
            tc.verifyEqual(fomc.focus.monthsNamed("in sept. 2019 and Dec, 2021"), datetime([2019 2021], [9 12], 1));
            tc.verifyEqual(fomc.focus.monthsNamed("MAY 2021"), datetime(2021,5,1));
            tc.verifyEmpty(fomc.focus.monthsNamed("Your data stops at 2020-03-01. What now?"));
            tc.verifyEmpty(fomc.focus.monthsNamed("What is the unemployment rate?"));
        end

        function aLaterMonthIsSaidNotKnownWithTheLatestValueAndNoValueForIt(tc)
            [text, recs] = fomc.focus.dataPrefetch(tc.ctx, "What was the unemployment rate in June 2020?");
            tc.verifyEqual([recs.name], "prefetchNotice");
            reply = string(recs.result);
            tc.verifySubstring(reply, "June 2020 is not known as of 2020-03-01");
            tc.verifySubstring(reply, "3.5 on 2020-01-01");
            tc.verifyFalse(contains(reply, ["4.4", "2020-03-06"]), "the later revision and its date must not appear");
            tc.verifySubstring(text, reply);        % the line the model-free answer is made from, kept in the calls
        end

        function theMonthJustAfterTheNewestValueIsLaterToo(tc)
            [~, recs] = fomc.focus.dataPrefetch(tc.ctx, "What was the unemployment rate in February 2020?");
            tc.verifyEqual([recs.name], "prefetchNotice");      % February came out on 2020-03-06
        end

        function aMonthTheDataShowsGetsTheFiguresAsBefore(tc)
            [text, recs] = fomc.focus.dataPrefetch(tc.ctx, "What was the unemployment rate in January 2020?");
            tc.verifyEqual([recs.name], "prefetchData");
            tc.verifySubstring(text, "3.5 on 2020-01-01");
        end

        function knownAndLaterMonthsTogetherGoToTheModel(tc)
            [~, recs] = fomc.focus.dataPrefetch(tc.ctx, "Compare the unemployment rate in January 2020 with June 2020.");
            tc.verifyEqual([recs.name], "prefetchData");
        end

        function noMonthNamedMeansNoNotice(tc)
            [~, recs] = fomc.focus.dataPrefetch(tc.ctx, "What was the unemployment rate in 2021?");
            tc.verifyEqual([recs.name], "prefetchData");
        end

        function aSeriesWithNoPublicValueSaysSo(tc)
            [~, recs] = fomc.focus.dataPrefetch(tc.ctx, "What was PROJ in June 2020?");
            tc.verifyEqual([recs.name], "prefetchNotice");
            tc.verifySubstring(string(recs.result), "No value was public yet");
        end

        function prefetchOffMeansNothing(tc)
            cfg = tc.cfg; cfg.prefetch = false;
            ctx = fomc.context(datetime(2020,3,1), cfg, tc.D, tracePath=string(tempname)+".jsonl");
            [text, recs] = fomc.focus.dataPrefetch(ctx, "What was the unemployment rate in June 2020?");
            tc.verifyEqual(text, "");
            tc.verifyEmpty(recs);
        end

        function aLaterMonthIsAnsweredWithoutAskingTheModel(tc)
            m = fomc.llm.Mock({struct("content", "It was 9.9% in June 2020.")});     % a made-up value
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            [~, answer, ~, calls] = fomc.runTurn(s, "What was the unemployment rate in June 2020?");
            tc.verifyEmpty(m.Seen, "the model must not be called");
            tc.verifySubstring(answer, "not known as of 2020-03-01");
            tc.verifyFalse(contains(answer, "9.9"));
            tc.verifyTrue(any(string({calls.name}) == "prefetchNotice"), "so the critic is skipped");
        end

        function aRateChangeQuestionForAnUnreleasedMeetingGetsTheNotice(tc)
            [~, recs] = fomc.focus.prefetch(tc.ctx, "Did the Fed change interest rates at its March 2020 meeting, and to what range?", false);
            tc.verifyTrue(any([recs.name] == "prefetchNotice"));
        end

        function aTopicQuestionWithAMonthIsNotTurnedIntoADecisionQuestion(tc)
            [~, recs] = fomc.focus.prefetch(tc.ctx, "What did participants say about changes in the labor market in January 2020?", false);
            tc.verifyFalse(any(ismember([recs.name], ["getDecision" "prefetchNotice"])));
        end
    end
end
