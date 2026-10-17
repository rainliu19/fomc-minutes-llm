classdef testBackstop < matlab.unittest.TestCase
    % Look-ahead check on REAL data: for many random anchor dates, run every tool directly
    % (bypassing the output guardrail); nothing may be dated after the anchor or come from
    % unreleased minutes. No model.

    properties
        D
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function toolsNeverReturnAnythingPastTheAnchor(tc)
            % Pick 25 random anchor dates plus 5 meeting release dates (fixed seed, so runs repeat)
            rng(7);
            lo = datetime(2008,3,1);
            hi = datetime(2026,10,9);
            asOfs = lo + days(randi(days(hi - lo), 25, 1));
            asOfs = [asOfs; tc.D.meetings.ReleaseDate(randperm(height(tc.D.meetings), 5))];
            cfg = fomc.config(verbose=false);
            ids = ["UNRATE","CPIAUCSL","DGS10","UMCSENT","GDPC1"];
            % For each anchor date, run every tool directly
            for asOf = asOfs.'
                ctx = fomc.context(asOf, cfg, tc.D, tracePath=string(tempname) + ".jsonl");
                M = tc.D.meetings(tc.D.meetings.ReleaseDate <= asOf, :);
                results = {
                    fomc.tools.listMeetings(ctx, struct("n", 50))
                    fomc.tools.getSnapshot(ctx, struct("group", "all"))
                    fomc.tools.getSeries(ctx, struct("seriesIds", strjoin(ids, ",")))
                    fomc.tools.getSeries(ctx, struct("seriesIds", "CPIAUCSL", "transform", "yoy_pct"))
                    fomc.tools.searchMinutes(ctx, struct("query", "inflation", "maxResults", 20))
                    fomc.tools.describeSeries(ctx, struct("seriesId", "UNRATE"))
                    };
                if ~isempty(M)
                    results{end+1, 1} = fomc.tools.readMinutes(ctx, struct( ...
                        "meetingDate", fomc.util.fmtDate(M.MeetingDate(end)), "section", "participantsViews")); %#ok<AGROW>
                end
                % No result may contain a date after the anchor
                for k = 1:numel(results)
                    r = results{k};
                    out = fomc.guard.checkToolOutput(ctx, r, string(jsonencode(r)));
                    tc.verifyTrue(out.ok, sprintf("asOf %s, result %d: %s", ...
                        fomc.util.fmtDate(asOf), k, out.message));
                end
                % Search hits only from minutes released by the anchor.
                s = results{5};
                for h = s.hits.'
                    rel = tc.D.meetings.ReleaseDate(tc.D.meetings.MeetingDate == fomc.util.parseDate(h{1}.meetingDate));
                    tc.verifyLessThanOrEqual(rel, asOf);
                end
            end
        end

        function everySeriesHasAnAvailabilityRule(tc)
            tc.verifyEmpty(setdiff(tc.D.dict.series_id, tc.D.avail.series_id));
        end

        function everyMeetingHasMinutesText(tc)
            tc.verifyEqual(height(tc.D.meetings), 150);
            tc.verifyTrue(all(strlength(tc.D.meetings.Body) > 5000));
        end

        function marchTwentyTwentyUnemploymentIsFirstKnownOnReleaseDay(tc)
            % March 2020 unemployment (4.4) was first published 2020-04-03
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,4,2));
            tc.verifyFalse(any(T.date == datetime(2020,3,1)));
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,4,3));
            tc.verifyEqual(T.value(T.date == datetime(2020,3,1)), 4.4);
        end
    end
end
