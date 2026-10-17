classdef testDataPrefetch < matlab.unittest.TestCase
    % The figures the harness looks up before the model starts. SYNTHETIC data (anchor 2020-03-01)
    % plus a look-ahead check on REAL data.

    properties
        D
        ctx
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
            tc.ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), tc.D, tracePath=string(tempname)+".jsonl");
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function aDataQuestionGetsTheLatestKnownFigure(tc)
            [text, recs] = fomc.focus.dataPrefetch(tc.ctx, "What is the unemployment rate?");
            tc.verifySubstring(text, "unemployment rate (UNRATE): 3.5 on 2020-01-01");
            tc.verifyEqual(recs.name, "prefetchData");
            tc.verifyTrue(recs.ok);
        end

        function aLaterRevisionIsNotLeaked(tc)
            text = fomc.focus.dataPrefetch(tc.ctx, "unemployment");
            tc.verifyFalse(contains(text, ["3.6", "4.4"]), "values published after the anchor date");
        end

        function aSeriesNotPublicYetSaysSo(tc)
            ctx2 = fomc.context(datetime(2020,2,6), tc.ctx.cfg, tc.D, tracePath=string(tempname)+".jsonl");
            text = fomc.focus.dataPrefetch(ctx2, "What is the unemployment rate?");
            tc.verifySubstring(text, "no value was public yet");
        end

        function aQuestionWithNoDataTopicGetsNothing(tc)
            [text, recs] = fomc.focus.dataPrefetch(tc.ctx, "Tell me something interesting.");
            tc.verifyEqual(text, "");
            tc.verifyEmpty(recs);
        end

        function prefetchOffMeansNoLookup(tc)
            ctx2 = fomc.context(datetime(2020,3,1), fomc.config(verbose=false, prefetch=false), tc.D, tracePath=string(tempname)+".jsonl");
            tc.verifyEqual(fomc.focus.dataPrefetch(ctx2, "unemployment"), "");
        end

        function theFiguresCountAsSeenForTheFigureCheck(tc)
            [~, recs] = fomc.focus.dataPrefetch(tc.ctx, "unemployment");
            item = struct("series", "UNRATE", "value", 3.5, "date", "2020-01-01");
            ev = struct("claim", "c", "id", "2020-01-29/participantsViews/1");
            r = fomc.guard.checkGrounding(struct("evidence", {{ev}}, "dataCited", {{item}}), tc.ctx, recs, "2020-01-29/participantsViews/1");
            tc.verifyTrue(r.ok, strjoin(r.failures));
        end

        function theCombinedPrefetchAddsDataToMinutes(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What did participants say about unemployment?", false);
            tc.verifySubstring(text, "UNRATE");
            tc.verifyTrue(any([recs.name] == "prefetchData"));
            tc.verifyTrue(any([recs.name] == "prefetchPassages"));
        end

        function topicsAreFoundFromTheWording(tc)
            known = ["MORTGAGE30US"; "UNRATE"; "DCOILWTICO"; "DTWEXBGS"; "GFDEGDQ188S"; "VIXCLS"];
            tc.verifyEqual(fomc.focus.dataTopics("Where are mortgage rates?", known), "MORTGAGE30US");
            tc.verifyEqual(fomc.focus.dataTopics("What happened to oil prices and the dollar?", known), ["DCOILWTICO"; "DTWEXBGS"]);
            tc.verifyEqual(fomc.focus.dataTopics("How much federal debt as a share of GDP?", known), "GFDEGDQ188S");
            tc.verifyEqual(fomc.focus.dataTopics("Is UNRATE high?", known), "UNRATE");
            tc.verifyEmpty(fomc.focus.dataTopics("Hello there", known));
        end

        function aTopicWithNoSeriesInTheDataIsSkipped(tc)
            tc.verifyEmpty(fomc.focus.dataTopics("mortgage rates", ["UNRATE"]));
        end

        function aWideQuestionIsCapped(tc)
            all = fomc.data.plainNames().series_id;
            ids = fomc.focus.dataTopics("inflation, unemployment, yields, mortgage rates, GDP, oil, the dollar, debt, volatility", all);
            tc.verifyLessThanOrEqual(numel(ids), 6);
        end

        function opinionQuestionsAboutTheFedCountAsMinutesQuestions(tc)
            tc.verifyTrue(fomc.focus.aboutMinutes("Compare the Fed's view of inflation in 2022 versus 2023."));
            tc.verifyTrue(fomc.focus.aboutMinutes("What did the Fed say about the labor market?"));
            tc.verifyFalse(fomc.focus.aboutMinutes("What is the fed funds rate?"));
            tc.verifyFalse(fomc.focus.aboutMinutes("Where are mortgage rates?"));
        end

        function realDataNeverReachesPastTheAnchor(tc)
            D2 = fomc.data.load();
            cfg = fomc.config(verbose=false);
            rng(11);
            asOfs = datetime(2008,3,1) + days(randi(days(datetime(2026,10,9) - datetime(2008,3,1)), 30, 1));
            q = "inflation unemployment yields mortgage GDP oil dollar debt volatility wages balance sheet stocks sentiment";
            for asOf = asOfs.'
                ctx2 = fomc.context(asOf, cfg, D2, tracePath=string(tempname)+".jsonl");
                [text, recs] = fomc.focus.dataPrefetch(ctx2, q);
                dates = datetime(regexp(text, "\d{4}-\d{2}-\d{2}", "match"), InputFormat="yyyy-MM-dd");
                tc.verifyTrue(all(dates <= asOf), "a figure dated after " + fomc.util.fmtDate(asOf));
                if ~isempty(recs)
                    out = fomc.guard.checkToolOutput(ctx2, jsondecode(recs.result), recs.result);
                    tc.verifyTrue(out.ok, out.message);
                end
            end
        end
    end
end
