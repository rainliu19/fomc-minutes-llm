classdef testPolicyPath < matlab.unittest.TestCase
    % The rate path tool on REAL data. No model. Expected values were read off the rate data
    % (FRED) and the minutes text, not from memory.

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
        function theSeptember2026IncreaseIsTheFirstSince2023(tc)
            r = policyPath(tc, datetime(2026,10,25), struct());
            tc.verifyEqual(r.targetRange, "3-3/4 to 4 percent");
            tc.verifyEqual(r.lastChange.meetingDate, "2026-09-16");
            tc.verifyEqual(r.lastChange.change, 0.25);
            tc.verifyEqual(r.lastChange.firstInThisDirectionSince, "2023-07-26");
            tc.verifyEqual(r.meetingsHeldBeforeLastChange, 5);
            tc.verifySubstring(r.summary, "the first increase since 2023-07-26");
        end

        function theCutsBeforeItAreOneRunOfSix(tc)
            r = policyPath(tc, datetime(2026,10,25), struct());
            p = r.previousRun;
            tc.verifyEqual([p.direction, p.startDate, p.endDate], ["cut", "2024-09-18", "2025-12-10"]);
            tc.verifyEqual(p.changes, 6);
            tc.verifyEqual(p.totalChange, -1.75);
            tc.verifyEqual([p.fromRange, p.toRange], ["5-1/4 to 5-1/2 percent", "3-1/2 to 3-3/4 percent"]);
        end

        function theDefaultSpanIsTheLatestEightMeetings(tc)
            r = policyPath(tc, datetime(2026,10,25), struct());
            tc.verifyEqual(r.span.meetings, 8);
            tc.verifyEqual(r.span.startDate, "2025-10-29");
            tc.verifyEqual([r.span.increases, r.span.cuts, r.span.holds], [1 2 5]);
            tc.verifyEqual(r.span.netChange, -0.25);
        end

        function from2015To2018RatesRoseNineTimes(tc)
            % The evaluation's 2015-to-2018 question, answered by the tool
            r = policyPath(tc, datetime(2019,1,31), struct("startDate", "2015-01-01", "endDate", "2018-12-31"));
            tc.verifyEqual([r.span.increases, r.span.cuts], [9 0]);
            tc.verifyEqual(r.span.fromRange, "0 to 1/4 percent");
            tc.verifyEqual(r.span.toRange, "2-1/4 to 2-1/2 percent");
            tc.verifyEqual(r.span.netChange, 2.25);
            tc.verifyEqual(r.currentRun.startDate, "2015-12-16");
        end

        function aCopiedDefaultFocusWindowMeansTheLatestEightMeetings(tc)
            % "The past year" names no year, so the focus note offers the last 3 years; models
            % copy those dates. The tool treats them as no dates.
            ctx = context(tc, datetime(2026,10,7));
            ctx.focus = fomc.focus.window("How have interest rates changed over the past year?", ctx.asOf, tc.cfg);
            r = fomc.tools.getPolicyPath(ctx, struct("startDate", fomc.util.fmtDate(ctx.focus.start), ...
                "endDate", fomc.util.fmtDate(ctx.focus.end)));
            tc.verifyEqual(r.span.meetings, 8);
            % A window the question asked for (years named) is kept
            ctx.focus = fomc.focus.window("How did rates change between 2015 and 2018?", ctx.asOf, tc.cfg);
            r = fomc.tools.getPolicyPath(ctx, struct("startDate", "2015-01-01", "endDate", "2018-12-31"));
            tc.verifyEqual(r.span.startDate, "2015-01-01");
        end

        function changesBetweenMeetingsAreCounted(tc)
            % 2008: cuts on January 22 and October 8 came between meetings; 4-1/4 percent to 0 to 1/4
            r = policyPath(tc, datetime(2009,1,31), struct("startDate", "2008-01-01", "endDate", "2008-12-31"));
            tc.verifyEqual(r.span.changesBetweenMeetings, 2);
            tc.verifyEqual(r.span.cuts, 7);
            tc.verifyEqual(r.span.netChange, -4);
            between = cellfun(@(c) isfield(c, "betweenMeetings"), r.changes);
            dates = string(cellfun(@(c) c.date, r.changes, UniformOutput=false));
            tc.verifyEqual(sort(dates(between(:))).', ["2008-01-22", "2008-10-08"]);
        end

        function changesBeforeTheMinutesDataAreNotCalledBetweenMeetings(tc)
            % 2004-2006: 17 increases, all at meetings, but the minutes data starts in 2008
            r = policyPath(tc, datetime(2009,1,31), struct("startDate", "2004-01-01", "endDate", "2006-12-31"));
            tc.verifyEqual([r.span.increases, r.span.changesBetweenMeetings, r.span.changesBeforeMinutesData], [17 0 17]);
            tc.verifyFalse(contains(r.summary, "between scheduled meetings"));
            tc.verifySubstring(r.summary, "17 changes from before 2008, when the minutes in this data begin");
        end

        function theCountsAddUpWhenMinutesAreNotOut(tc)
            % 2026-10-01: 8 meetings with minutes (3 cuts, 5 holds) plus the September increase
            r = policyPath(tc, datetime(2026,10,1), struct());
            s = r.span;
            tc.verifyEqual([s.meetings, s.cuts, s.holds, s.increases, s.changesMinutesNotPublic], [8 3 5 1 1]);
            tc.verifySubstring(r.summary, "include 1 change at a meeting whose minutes were not public yet");
        end

        function aRunWithHoldsIsNotCalledInARow(tc)
            r = policyPath(tc, datetime(2019,1,31), struct("startDate", "2015-01-01", "endDate", "2018-12-31"));
            tc.verifySubstring(r.summary, "the 9th increase since 2015-12-16 [2015-12-16/policyAction/");
            tc.verifySubstring(r.summary, "with no cut in between");
            r = policyPath(tc, datetime(2015,3,1), struct("startDate", "2012-01-01", "endDate", "2014-12-31"));
            tc.verifySubstring(r.summary, "net change 0 percentage points");
        end

        function aChangeBetweenMeetingsIsTheLastChangeUntilTheNextMeeting(tc)
            r = policyPath(tc, datetime(2020,3,10), struct());
            tc.verifyEqual(r.lastChange.meetingDate, "");
            tc.verifyEqual(r.lastChange.date, "2020-03-04");
            tc.verifySubstring(r.summary, "between scheduled meetings");
        end

        function aChangeWhoseMinutesAreNotOutIsMarked(tc)
            % September 2026 minutes were released 2026-10-07; the rate change was public on the day
            r = policyPath(tc, datetime(2026,10,1), struct());
            tc.verifyFalse(r.lastChange.minutesPublic);
            tc.verifySubstring(r.summary, "not public yet");
            tc.verifyFalse(any(cellfun(@(c) string(c.meetingDate) == "2026-09-16", r.dissents)), ...
                "no dissent details from minutes that are not out");
        end

        function theSummaryCitesTheParagraphsBehindItsFacts(tc)
            % A model that copies the summary should copy the citations with it
            r = policyPath(tc, datetime(2026,10,25), struct());
            tc.verifySubstring(r.summary, "2026-09-16 [" + r.lastChange.meetingDate + "/policyAction/1]");
            tc.verifySubstring(r.summary, "[2026-07-29/policyAction/15]", "latest dissent for a higher rate");
            tc.verifySubstring(r.summary, "held at 5 meetings [2026-07-29/policyAction/", "the latest of the holds");
            % Every id in the summary is a real paragraph from released minutes
            ids = fomc.guard.idsIn(r.summary);
            tc.verifyGreaterThanOrEqual(numel(ids), 4);
            P = tc.D.paras;
            for id = ids(:).'
                k = find(P.id == id, 1);
                tc.assertNotEmpty(k, id + " is not a paragraph");
                tc.verifyLessThanOrEqual(tc.D.meetings.ReleaseDate(P.meetingIdx(k)), datetime(2026,10,25));
            end
        end

        function changesWithNoParagraphAreNotCited(tc)
            % Between meetings (March 4, 2020) and minutes not out yet (September 2026): no id
            r = policyPath(tc, datetime(2020,3,10), struct());
            tc.verifyFalse(contains(r.summary, "2020-03-04 ["));
            r = policyPath(tc, datetime(2026,10,1), struct());
            tc.verifyFalse(contains(r.summary, "[2026-09-16/"));
        end

        function theAnalysisCheckAcceptsRateFiguresTheToolCovered(tc)
            % High effort cites figures; a rate target on any day of the path counts as shown
            ctx = context(tc, datetime(2026,10,7));
            [~, rec] = fomc.tools.dispatch(ctx, "getPolicyPath", struct());
            tc.verifyTrue(citeFigure(ctx, rec, "DFEDTARU", "2026-09-16", 3.75).ok, "the day before the increase took effect");
            tc.verifyTrue(citeFigure(ctx, rec, "DFEDTARL", "2026-10-06", 3.75).ok);
            tc.verifyTrue(citeFigure(ctx, rec, "DFEDTARU", "2024-09-17", 5.5).ok, "the day before the earlier run of cuts");
            tc.verifyFalse(citeFigure(ctx, rec, "DFEDTARU", "2026-09-16", 4).ok, "a wrong value");
            tc.verifyFalse(citeFigure(ctx, rec, "DFEDTARU", "2020-01-02", 1.75).ok, "a day the path did not cover");
            % A change from a meeting on the span's last day takes effect the next day
            [~, rec] = fomc.tools.dispatch(ctx, "getPolicyPath", struct("startDate", "2026-01-01", "endDate", "2026-09-16"));
            tc.verifyTrue(citeFigure(ctx, rec, "DFEDTARU", "2026-09-17", 4).ok, "the day the September increase took effect");
        end

        function nothingAfterTheAnchorIsReturned(tc)
            for asOf = [datetime(2026,10,1), datetime(2020,3,10), datetime(2015,12,20)]
                ctx = context(tc, asOf);
                res = fomc.tools.getPolicyPath(ctx, struct());
                o = fomc.guard.checkToolOutput(ctx, res, string(jsonencode(res)));
                tc.verifyTrue(o.ok, o.message);
            end
        end

        function dissentDirectionsMatchTheMinutes(tc)
            % Read from each meeting's vote paragraph: who preferred a higher or lower rate
            check(tc, "2025-12-10", "Miran", "lower");
            check(tc, "2025-12-10", "Goolsbee", "higher");    % preferred no change at a cut
            check(tc, "2025-12-10", "Schmid", "higher");
            check(tc, "2026-01-28", "Waller", "lower");
            check(tc, "2026-04-29", "Logan", "other");        % objected to the statement's easing bias
            check(tc, "2026-07-29", "Hammack", "higher");
            check(tc, "2024-09-18", "Bowman", "higher");      % wanted a 1/4 point cut, not 1/2
            check(tc, "2020-03-15", "Mester", "higher");      % wanted 1/2 to 3/4 percent, not 0 to 1/4
            check(tc, "2022-03-16", "Bullard", "higher");     % wanted a 1/2 point increase, not 1/4
            check(tc, "2019-09-18", "Bullard", "lower");      % wanted a 1/2 point cut, not 1/4
            check(tc, "2019-07-31", "Rosengren", "higher");   % saw no case for more accommodation
            check(tc, "2019-09-18", "Rosengren", "higher");   % policy "already accommodative"
            check(tc, "2019-10-30", "Rosengren", "higher");
            check(tc, "2017-12-13", "Evans", "lower");        % preferred no change at an increase
            check(tc, "2016-09-21", "Mester", "higher");
            check(tc, "2008-03-18", "Plosser", "higher");     % favored easing less aggressively
            check(tc, "2010-01-27", "Hoenig", "other");       % objected to forward guidance wording
        end

        function everyDissenterIsCountedOnce(tc)
            % One direction per person who voted against, at every split vote
            C = tc.D.cards;
            for k = find(~C.unanimous & C.voteId ~= "").'
                o = fomc.data.dissentDirections(tc.D, k, 0, NaN);
                tc.verifyEqual(numel(o), C.nAgainst(k), "dissenters at " + fomc.util.fmtDate(tc.D.meetings.MeetingDate(k)));
            end
        end

        function theResultStaysSmallEvenForALongSpan(tc)
            r = policyPath(tc, datetime(2026,10,25), struct());
            tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 4500);
            r = policyPath(tc, datetime(2026,10,25), struct("startDate", "2008-01-01"));
            tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 8000);
            tc.verifyLessThanOrEqual(numel(r.changes), 24);
            tc.verifyLessThanOrEqual(numel(r.dissents), 12);
        end

        function badDatesReturnGuidance(tc)
            r = policyPath(tc, datetime(2026,10,25), struct("startDate", "June 2020"));
            tc.verifySubstring(r.error, "YYYY-MM-DD");
            r = policyPath(tc, datetime(2026,10,25), struct("startDate", "2020-06-01", "endDate", "2019-06-01"));
            tc.verifySubstring(r.error, "on or before");
        end
    end
end

function ctx = context(tc, asOf)
% Helper: a session context at an anchor date, on the real data
ctx = fomc.context(asOf, tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
end

function r = citeFigure(ctx, rec, series, date, value)
% Helper: the High-effort grounding check for one cited figure, after one getPolicyPath call
% (the evidence cites the September 2026 decision, which that call returned)
ev = {struct("claim", "The target was raised.", "id", "2026-09-16/policyAction/1")};
r = fomc.guard.checkGrounding(struct("evidence", {ev}, ...
    "dataCited", {{struct("series", series, "date", date, "value", value)}}), ctx, rec);
end

function r = policyPath(tc, asOf, args)
% Helper: run the tool at an anchor date
r = fomc.tools.getPolicyPath(context(tc, asOf), args);
end

function check(tc, meeting, name, expected)
% Helper: one dissenter's direction at one meeting, as the tool reports it
d = datetime(meeting, InputFormat="yyyy-MM-dd");
r = policyPath(tc, d + caldays(60), struct("startDate", meeting, "endDate", meeting));
tc.assertNotEmpty(r.dissents, "no dissents found for " + meeting);
row = r.dissents{1};
fields = struct("lower", "wantedLower", "higher", "wantedHigher", "other", "otherGrounds");
field = fields.(expected);
tc.verifyTrue(isfield(row, field) && contains(row.(field), name), ...
    name + " at " + meeting + " should be '" + expected + "': " + jsonencode(row));
end
