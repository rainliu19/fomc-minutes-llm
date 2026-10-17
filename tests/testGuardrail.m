classdef testGuardrail < matlab.unittest.TestCase
    % The point-in-time guardrail. SYNTHETIC data, anchor 2020-03-01: January's minutes
    % (released 2020-02-19) are public, March's (released 2020-04-08) are not.

    properties
        ctx
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,3,1), cfg, syntheticData(), ...
                tracePath=string(tempname) + ".jsonl");
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function dateAfterAnchorIsRefused(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "getSeries", struct("endDate", "2020-03-02"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.message, "after the anchor date 2020-03-01");
        end

        function dateEqualToAnchorIsAccepted(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "getSeries", struct("endDate", "2020-03-01"));
            tc.verifyTrue(r.ok);
        end

        function everyDateArgumentIsChecked(tc)
            for f = ["meetingDate", "startDate", "endDate"]
                a = struct(f, "2021-01-01");
                r = fomc.guard.checkToolInput(tc.ctx, "x", a);
                tc.verifyFalse(r.ok, f);
            end
        end

        function unreleasedMinutesAreRefusedEvenForPastMeeting(tc)
            % A meeting that ended before the anchor but whose minutes are not yet public.
            D = syntheticData();
            D.meetings.ReleaseDate(1) = datetime(2020,3,20);   % pretend January minutes came out late
            ctx2 = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), D, ...
                tracePath=string(tempname) + ".jsonl");
            r = fomc.guard.checkToolInput(ctx2, "readMinutes", struct("meetingDate", "2020-01-29"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.message, "not public");
            tc.verifyFalse(contains(r.message, "2020-03-20"), "message must not reveal the release date");
        end

        function releasedMinutesAreAccepted(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "readMinutes", struct("meetingDate", "2020-01-29"));
            tc.verifyTrue(r.ok);
        end

        function malformedDateGetsActionableMessage(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "x", struct("startDate", "March 2019"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.message, "YYYY-MM-DD");
        end

        function impossibleCalendarDateIsRejected(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "x", struct("startDate", "2020-02-31"));
            tc.verifyFalse(r.ok);
        end

        function emptyDateArgumentIsIgnored(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "x", struct("startDate", [], "endDate", ""));
            tc.verifyTrue(r.ok);
        end

        function nonObjectArgumentsAreRefused(tc)
            r = fomc.guard.checkToolInput(tc.ctx, "x", "not an object");
            tc.verifyFalse(r.ok);
        end

        function outputBackstopCatchesLateDate(tc)
            res = struct("series", {{struct("rows", {{struct("date", "2020-01-01", "availableDate", "2020-03-05")}})}});
            r = fomc.guard.checkToolOutput(tc.ctx, res, string(jsonencode(res)));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.message, "2020-03-05");
        end

        function outputBackstopAcceptsEarlierDates(tc)
            res = struct("date", "2020-02-29", "meetingDate", "2020-01-29");
            r = fomc.guard.checkToolOutput(tc.ctx, res, string(jsonencode(res)));
            tc.verifyTrue(r.ok);
        end

        function outputBackstopRefusesOversizedResult(tc)
            res = struct("text", string(repmat('a', 1, 40000)));
            r = fomc.guard.checkToolOutput(tc.ctx, res, string(jsonencode(res)));
            tc.verifyFalse(r.ok);
        end
    end
end
