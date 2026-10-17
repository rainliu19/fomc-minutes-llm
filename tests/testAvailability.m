classdef testAvailability < matlab.unittest.TestCase
    % Publication-lag rules for unrevised series. SYNTHETIC data.

    properties
        D
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function dailyValueIsKnownTheNextDay(tc)
            T = fomc.data.valueAsOf(tc.D, "DGS10", datetime(2020,1,2));
            tc.verifyEmpty(T);
            T = fomc.data.valueAsOf(tc.D, "DGS10", datetime(2020,1,3));
            tc.verifyEqual(T.value, 1.8);
        end

        function monthlySurveyIsKnownAtMonthEnd(tc)
            T = fomc.data.valueAsOf(tc.D, "UMCSENT", datetime(2020,1,30));
            tc.verifyEmpty(T);
            T = fomc.data.valueAsOf(tc.D, "UMCSENT", datetime(2020,1,31));
            tc.verifyEqual(T.value, 99.1);
        end

        function monthEndWithLeapFebruary(tc)
            % Feb 2020 has 29 days: lag 1 gives March 1
            a = fomc.data.availableDate("monthend", 1, datetime(2020,2,1));
            tc.verifyEqual(a, datetime(2020,3,1));
        end

        function weeklyClaimsAreKnownThursdayAfterWeekEnd(tc)
            % Week ending Sat 2020-01-04, published Thu 2020-01-09
            T = fomc.data.valueAsOf(tc.D, "ICSA", datetime(2020,1,8));
            tc.verifyEmpty(T);
            T = fomc.data.valueAsOf(tc.D, "ICSA", datetime(2020,1,9));
            tc.verifyEqual(T.value, 214000);
        end

        function availableDateRejectsUnknownRule(tc)
            tc.verifyError(@() fomc.data.availableDate("nope", 0, datetime(2020,1,1)), ...
                "fomc:data:badRule");
        end
    end
end
