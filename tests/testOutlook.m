classdef testOutlook < matlab.unittest.TestCase
    % What the recent rate path may mean ahead (getOutlook): the staff forecast revisions
    % read from the minutes, how far the rate changes have reached, earlier runs, the tool the
    % model is offered, and the lookup that adds it to a question. REAL data, no model. Expected revisions were read by
    % hand from the Staff Economic Outlook; expected figures were worked out from the data as
    % known on each date, not from memory.

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
        function theForecastRevisionsMatchAReadingByHand(tc)
            % Every meeting of 2022 and the latest twelve. "" means the minutes compare no
            % forecast with the previous one (July 2022 inflation, May 2022 had no growth
            % revision but said "broadly similar to the March projection")
            expected = [
                "2022-01-26", "higher", "lower"
                "2022-03-16", "higher", "lower"
                "2022-05-04", "higher", "about the same"
                "2022-06-15", "higher", "lower"
                "2022-07-27", "", "lower"
                "2022-09-21", "higher", "lower"
                "2022-11-02", "higher", "lower"
                "2022-12-14", "lower", "higher"
                "2025-05-07", "higher", "lower"
                "2025-06-18", "lower", "higher"
                "2025-07-30", "lower", "about the same"
                "2025-09-17", "about the same", "higher"
                "2025-10-29", "about the same", "higher"
                "2025-12-10", "lower", "higher"
                "2026-01-28", "higher", "higher"
                "2026-03-18", "higher", "lower"
                "2026-04-29", "higher", "higher"
                "2026-06-17", "higher", "lower"
                "2026-07-29", "about the same", "lower"
                "2026-09-16", "higher", "higher"];
            F = revisionsFor(tc, expected(:, 1));
            tc.verifyEqual([F.inflation, F.activity], expected(:, 2:3));
        end

        function eachRevisionCitesTheParagraphItWasReadFrom(tc)
            F = revisionsFor(tc, ["2026-09-16"; "2026-03-18"]);
            tc.verifyEqual(F.inflationId, ["2026-09-16/staffOutlook/1"; "2026-03-18/staffOutlook/2"]);
            tc.verifyEqual(F.activityId, ["2026-09-16/staffOutlook/2"; "2026-03-18/staffOutlook/1"]);
            for id = [F.inflationId; F.activityId].'
                tc.verifyTrue(fomc.guard.resolveId(context(tc, datetime(2026,10,7)), id).ok, id);
            end
        end

        function reasonsAndIntroductionsAreNotRevisions(tc)
            % "not as strong as the one prepared for the January meeting" is weaker;
            % "revised down ... reflecting higher ..." is lower, not higher; "In the projection
            % prepared by the staff for the November meeting, growth was faster in the second
            % half than in the first" introduces the forecast and compares no forecasts, so
            % November 2016 reads lower (from "lower than in the September projection");
            % a revised estimate of potential output (September 2022) is not a growth forecast
            F = revisionsFor(tc, ["2026-03-18"; "2016-11-02"; "2014-04-30"; "2010-03-16"]);
            tc.verifyEqual(F.activity, ["lower"; "lower"; "lower"; "about the same"]);
            tc.verifyEqual(F.inflation(2), "higher");
        end

        function theRisksAreReadAsTheStaffStatedThem(tc)
            F = revisionsFor(tc, ["2026-09-16"; "2026-07-29"; "2019-10-30"; "2021-03-17"]);
            tc.verifyEqual([F.inflationRisk, F.activityRisk], ...
                ["upside", "balanced"; "upside", "downside"; "downside", "downside"; "balanced", ""]);
        end

        function inOctober2026TheIncreaseHasReachedRatesButNotSpending(tc)
            r = fomc.data.outlookAssessment(tc.D, datetime(2026,10,7));
            tc.verifyEqual(r.currentRun.direction, "increase");
            tc.verifyEqual(r.currentRun.firstChange, "2026-09-17");
            tc.verifyEqual(r.staffForecast.meetings, ["2026-04-29", "2026-06-17", "2026-07-29", "2026-09-16"]);
            tc.verifyEqual(r.staffForecast.inflation.revisions, ["higher", "higher", "about the same", "higher"]);
            tc.verifyEqual(r.staffForecast.activity.revisions, ["stronger", "weaker", "weaker", "stronger"]);
            tc.verifyEqual(r.staffForecast.inflation.risks, "upside");
            s = step(r, "MORTGAGE30US");
            tc.verifyEqual([s.now, s.before, s.sixMonthsBefore], [7.28, 6.76, 6.11], AbsTol=0.005);
            tc.verifyTrue(s.sinceFirstChange);
            for id = ["PCEC96", "PCEPILFE", "MICH"]
                s = step(r, id);
                tc.verifyFalse(s.sinceFirstChange, id + ": its latest reading (August) is before the increase");
            end
            tc.verifySubstring(r.summary, "Too early to show the increase");
            tc.verifyEqual(r.market.suggests, "further increases");
        end

        function inOctober2022SpendingHadSlowedAfterTheIncreases(tc)
            % Six months into the 2022 increases: mortgage rates up almost 3 points, real
            % consumer spending growth down from 6.7% to 1.8%, as known on that date
            r = fomc.data.outlookAssessment(tc.D, datetime(2022,10,1));
            tc.verifyEqual(r.currentRun.firstChange, "2022-03-17");
            tc.verifyEqual(r.currentRun.changes, 5);
            s = step(r, "MORTGAGE30US");
            tc.verifyEqual(s.now - s.before, 2.85, AbsTol=0.01);
            s = step(r, "PCEC96");
            tc.verifyTrue(s.sinceFirstChange);
            tc.verifyEqual([s.now, s.before], [1.8, 6.7], AbsTol=0.05);
            tc.verifySubstring(r.summary, "Spending and prices: real consumer spending growth 1.8% (August 2022");
        end

        function earlierRunsAreTheOnesInTheSameDirection(tc)
            % Increases before the one of September 2026; the cuts of 2019 compare with earlier
            % cuts. The first run in the data (cuts from 1990) is left out: it began earlier.
            r = fomc.data.outlookAssessment(tc.D, datetime(2026,10,7));
            first = cellfun(@(x) x.firstChange, r.earlierRuns).';
            tc.verifyEqual(first, ["1994-02-04", "1997-03-25", "1999-06-30", "2004-06-30", "2015-12-16", "2022-03-17"]);
            r = fomc.data.outlookAssessment(tc.D, datetime(2019,12,1));
            first = cellfun(@(x) x.firstChange, r.earlierRuns).';
            tc.verifyEqual(first, ["1995-07-06", "1998-09-29", "2001-01-03", "2007-09-18"]);
            tc.verifySubstring(r.summary, "Earlier runs of cuts since 1990");
        end

        function beforeTheMinutesDataThereIsNoStaffForecast(tc)
            r = fomc.data.outlookAssessment(tc.D, datetime(2005,6,1));
            tc.verifySubstring(r.summary, "No minutes were public on this date");
            tc.verifyEqual(r.currentRun.firstChange, "2004-06-30");
        end

        function atEveryReleaseDateNothingIsLaterAndNothingIsMissing(tc)
            for asOf = tc.D.meetings.ReleaseDate.'
                ctx = context(tc, asOf);
                r = fomc.data.outlookAssessment(tc.D, asOf);
                json = string(jsonencode(r));
                g = fomc.guard.checkToolOutput(ctx, r, json);
                tc.verifyTrue(g.ok, g.message);
                tc.verifyFalse(contains(r.summary, ["NaN", "Inf", "  "]), fomc.util.fmtDate(asOf) + ": " + r.summary);
                tc.verifyLessThanOrEqual(strlength(r.summary), 2000, fomc.util.fmtDate(asOf));
                tc.verifyLessThanOrEqual(strlength(json), 8000, fomc.util.fmtDate(asOf));
                % Every id in the summary is a paragraph whose minutes were public
                for id = fomc.guard.idsIn(r.summary).'
                    tc.verifyTrue(fomc.guard.resolveId(ctx, id).ok, fomc.util.fmtDate(asOf) + ": " + id);
                end
            end
        end

        function theModelIsOfferedItAsATool(tc)
            reg = fomc.tools.registry();
            tc.verifyTrue(reg([reg.name] == "getOutlook").expose);
            ctx = context(tc, datetime(2026,10,7));
            [json, rec] = fomc.tools.dispatch(ctx, "getOutlook", struct());
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyEqual(string(r.summary), fomc.data.outlookAssessment(tc.D, datetime(2026,10,7)).summary);
        end

        function anEarlierEndDateShowsTheEvidenceAsItStoodThen(tc)
            % Asked in October 2026 about October 2022: the 2022 run, as known then
            ctx = context(tc, datetime(2026,10,7));
            [json, rec] = fomc.tools.dispatch(ctx, "getOutlook", struct("endDate", "2022-10-01"));
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyEqual(string(r.anchorDate), "2022-10-01");
            tc.verifyEqual(string(r.currentRun.firstChange), "2022-03-17");
            tc.verifyEqual(string(r.summary), fomc.data.outlookAssessment(tc.D, datetime(2022,10,1)).summary);
        end

        function datesAfterTheAnchorOrBeforeTheDataAreRefused(tc)
            ctx = context(tc, datetime(2026,10,7));
            [json, rec] = fomc.tools.dispatch(ctx, "getOutlook", struct("endDate", "2026-12-01"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "after the anchor date");
            [json, rec] = fomc.tools.dispatch(ctx, "getOutlook", struct("endDate", "1989-06-01"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "1991 or later");
            [~, rec] = fomc.tools.dispatch(ctx, "getOutlook", struct("endDate", "last year"));
            tc.verifyFalse(rec.ok);
        end

        function questionsAboutWhatTheRatePathMeansGetIt(tc)
            for q = ["What do these Fed minutes mean for future economic conditions?", ...
                    "What does the trajectory of the past few FOMC meetings mean for inflation, debt interest rates and consumer spending?", ...
                    "How will higher rates affect consumer spending?", "What is the outlook for inflation?", ...
                    "What is the impact of the rate hikes on mortgages?", "Will higher rates hurt the economy?", ...
                    "How do rate increases pass through to borrowing costs?", ...
                    "With the Fed raising rates again, where are things headed?", ...
                    "Is now a good time to buy a house given the Fed's recent moves?", ...
                    "What did the 2022 rate increases do to mortgage rates and consumer spending?"]
                [text, recs] = fomc.focus.outlookPrefetch(context(tc, datetime(2026,10,7)), q);
                tc.verifySubstring(text, "Evidence on what the recent rate path may mean ahead", q);
                tc.verifyEqual(recs.name, "getOutlook", q);
            end
        end

        function aQuestionAboutAPastYearGetsTheEvidenceAsItStoodThen(tc)
            % The end of the latest year named; a question naming the anchor year gets today's
            ctx = context(tc, datetime(2026,10,7));
            [text, recs] = fomc.focus.outlookPrefetch(ctx, "What did the 2022 rate increases do to mortgage rates and consumer spending?");
            tc.verifyEqual(string(recs.args.endDate), "2022-12-31");
            tc.verifySubstring(text, "as known on 2022-12-31");
            tc.verifySubstring(text, "The current run began with an increase on 2022-03-17");
            [~, recs] = fomc.focus.outlookPrefetch(ctx, "What do the 2026 increases mean for mortgage rates?");
            tc.verifyFalse(isfield(recs.args, "endDate"));
        end

        function otherQuestionsGetNothing(tc)
            for q = ["What did the Committee decide at its March 2020 meeting?", ...
                    "How have interest rates changed over the past year?", "What is the unemployment rate?", ...
                    "What did participants say about inflation?", "Who dissented in 2022?", ...
                    "Should the Fed raise rates at the next meeting?", "What does inflation mean?", ...
                    "Tell me something interesting."]
                [text, recs] = fomc.focus.outlookPrefetch(context(tc, datetime(2026,10,7)), q);
                tc.verifyEqual(text, "", q);
                tc.verifyEmpty(recs, q);
            end
        end

        function itIsTheLastLookupAndItsFiguresAndIdsCanBeCited(tc)
            % fomc.focus.prefetch adds it last; a High-effort answer may cite its figures and ids
            ctx = context(tc, datetime(2026,10,7));
            [text, recs] = fomc.focus.prefetch(ctx, "What do the recent minutes mean for inflation and mortgage rates?", false);
            names = string({recs.name});
            tc.verifyEqual(names(end), "getOutlook");
            tc.verifyTrue(endsWith(strtrim(text), "]"));
            ok = @(s, d, v) ~any(startsWith(fomc.guard.checkGrounding(struct("evidence", {{}}, ...
                "dataCited", {{struct("series", s, "date", d, "value", v)}}), ctx, recs).failures, "Data item"));
            tc.verifyTrue(ok("MORTGAGE30US", "2026-10-01", 7.28));
            tc.verifyTrue(ok("DGS2", "2026-10-06", 4.79));
            tc.verifyTrue(ok("PCEPILFE", "2026-08-01", 3.01), "core inflation, 12-month change");
            tc.verifyFalse(ok("MORTGAGE30US", "2026-10-01", 6.28), "a wrong value");
            g = fomc.guard.checkGrounding(struct("evidence", {{struct("id", "2026-09-16/staffOutlook/1")}}, ...
                "dataCited", {{}}), ctx, recs);
            tc.verifyFalse(any(contains(g.failures, "staffOutlook")), strjoin(g.failures, " "));
        end

        function aQuestionAboutMissingDataIsToldSoFirst(tc)
            % Qwen3 4B answered "What do the recent rate increases mean for interest on the federal
            % debt?" without saying the data lack it, when that was only in the result's note
            ctx = context(tc, datetime(2026,10,27));
            text = fomc.focus.outlookPrefetch(ctx, "What do the recent rate increases mean for interest on the federal debt?");
            first = "The question asks about interest on federal debt, which is not in this data. Begin the answer by saying so plainly";
            tc.verifySubstring(text, first);
            tc.verifyLessThan(strfind(text, first), strfind(text, "Fed staff forecasts"));
            text = fomc.focus.outlookPrefetch(ctx, "How will higher rates affect credit card and car loan payments?");
            tc.verifySubstring(text, "about credit card rates and car loan rates, which are not in this data");
            text = fomc.focus.outlookPrefetch(ctx, "What do the recent minutes mean for inflation and mortgage rates?");
            tc.verifyFalse(contains(text, "not in this data. Begin"));
        end

        function prefetchOffMeansNoLookup(tc)
            cfg2 = fomc.config(verbose=false, prefetch=false);
            ctx = fomc.context(datetime(2026,10,7), cfg2, tc.D, tracePath=string(tempname) + ".jsonl");
            tc.verifyEqual(fomc.focus.outlookPrefetch(ctx, "What do these minutes mean for inflation?"), "");
        end
    end
end

function ctx = context(tc, asOf)
% Helper: a session context at an anchor date, on the real data
ctx = fomc.context(asOf, tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
end

function F = revisionsFor(tc, dates)
% Helper: the forecast revisions for meetings given by date, in that order
[~, k] = ismember(datetime(dates), tc.D.meetings.MeetingDate);
tc.assertTrue(all(k > 0), "every date is a meeting");
F = fomc.data.forecastRevisions(tc.D, k);
end

function s = step(r, id)
% Helper: one series from the "so far" part
s = r.soFar{cellfun(@(x) x.seriesId == id, r.soFar)};
end
