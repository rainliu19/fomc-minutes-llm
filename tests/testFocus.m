classdef testFocus < matlab.unittest.TestCase
    % The focus window: a default span of minutes, never a limit.

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
        function noYearGivesTheLastThreeYears(tc)
            w = fomc.focus.window("What did they say about inflation?", datetime(2020,3,1), tc.cfg);
            tc.verifyEqual(w.end, datetime(2020,3,1));
            tc.verifyEqual(w.start, datetime(2017,3,2));
        end

        function oneYearGivesThreeYearsEndingThatYear(tc)
            w = fomc.focus.window("How did they view the labor market in 2012?", datetime(2026,10,7), tc.cfg);
            tc.verifyEqual(w.start, datetime(2010,1,1));
            tc.verifyEqual(w.end, datetime(2012,12,31));
        end

        function severalYearsGiveTheWholeSpan(tc)
            w = fomc.focus.window("Compare 2008 with 2020.", datetime(2026,10,7), tc.cfg);
            tc.verifyEqual(w.start, datetime(2008,1,1));
            tc.verifyEqual(w.end, datetime(2020,12,31));
        end

        function yearAfterTheAnchorIsIgnored(tc)
            w = fomc.focus.window("What will happen in 2030?", datetime(2020,3,1), tc.cfg);
            tc.verifyEqual(w.end, datetime(2020,3,1));
        end

        function yearBeforeTheMinutesBeginIsIgnored(tc)
            w = fomc.focus.window("Compare with 1994.", datetime(2020,3,1), tc.cfg);
            tc.verifyEqual(w.end, datetime(2020,3,1));
        end

        function windowEndIsNeverPastTheAnchor(tc)
            w = fomc.focus.window("Tell me about 2020.", datetime(2020,4,8), tc.cfg);
            tc.verifyEqual(w.end, datetime(2020,4,8));
        end

        function windowSizeFollowsTheConfig(tc)
            cfg2 = fomc.config(focusYears=1);
            w = fomc.focus.window("2015", datetime(2026,10,7), cfg2);
            tc.verifyEqual(w.start, datetime(2015,1,1));
        end

        function searchUsesTheWindowByDefaultAndSaysSo(tc)
            ctx = makeCtx(tc, datetime(2020,2,1), datetime(2020,3,1));
            r = fomc.tools.searchMinutes(ctx, struct("query", "SYNTHETIC"));
            tc.verifyEqual(r.totalMatches, 0);
            tc.verifyTrue(r.window.isDefault);
            tc.verifySubstring(r.note, "default focus window");
        end

        function explicitDatesOverrideTheWindow(tc)
            ctx = makeCtx(tc, datetime(2020,2,1), datetime(2020,3,1));
            r = fomc.tools.searchMinutes(ctx, struct("query", "SYNTHETIC", "startDate", "2020-01-01"));
            tc.verifyGreaterThan(r.totalMatches, 0);
            tc.verifyFalse(r.window.isDefault);
        end

        function listMeetingsFollowsTheWindowToo(tc)
            ctx = makeCtx(tc, datetime(2020,2,1), datetime(2020,3,1));
            tc.verifyEqual(fomc.tools.listMeetings(ctx, struct()).count, 0);
            tc.verifyEqual(fomc.tools.listMeetings(ctx, struct("startDate", "2020-01-01")).count, 1);
        end

        function noWindowMeansAllReleasedMinutes(tc)
            ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname)+".jsonl");
            r = fomc.tools.searchMinutes(ctx, struct("query", "SYNTHETIC"));
            tc.verifyGreaterThan(r.totalMatches, 0);
        end

        function noteListsOnlyReleasedMeetingsInTheWindow(tc)
            ctx = makeCtx(tc, datetime(2019,1,1), datetime(2020,12,31));
            n = fomc.focus.note(ctx);
            tc.verifySubstring(n, "2020-01-29");
            tc.verifyFalse(contains(n, "2020-03-18"), "its minutes are not public on the anchor date");
        end

        function noteSaysWhichMinutesAreTheLatestAvailable(tc)
            ctx = makeCtx(tc, datetime(2019,1,1), datetime(2020,12,31));
            n = fomc.focus.note(ctx);
            tc.verifySubstring(n, "Latest minutes available: meeting ended 2020-01-29, released 2020-02-19");
            tc.verifySubstring(n, "Later meetings are not public yet");
            tc.verifyFalse(contains(n, "2020-04-08"), "the release date of unreleased minutes must not appear");
        end

        function windowNeverWidensWhatTheGuardrailAllows(tc)
            ctx = makeCtx(tc, datetime(2019,1,1), datetime(2020,12,31));
            r = fomc.guard.checkToolInput(ctx, "listMeetings", struct("endDate", "2020-12-31"));
            tc.verifyFalse(r.ok);
        end

        function tooManyDataItemsFailTheGroundingCheck(tc)
            ctx = makeCtx(tc, datetime(2019,1,1), datetime(2020,3,1));
            [~, rec] = fomc.tools.dispatch(ctx, "getSeries", struct("seriesIds", "UNRATE"));
            item = struct("series", "UNRATE", "value", 3.5, "date", "2020-01-01");
            ev = struct("claim", "c", "id", "2020-01-29/participantsViews/1");
            s = struct("evidence", {{ev}}, "dataCited", {repmat({item}, 1, 7)});
            r = fomc.guard.checkGrounding(s, ctx, rec);
            tc.verifyFalse(r.ok);
            tc.verifySubstring(strjoin(r.failures), "Too many data items");
        end
    end
end

function ctx = makeCtx(tc, startDate, endDate)
ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname)+".jsonl");
% Set the focus window by hand
ctx.focus = struct("start", startDate, "end", endDate, "years", 3, "reason", "test");
end
