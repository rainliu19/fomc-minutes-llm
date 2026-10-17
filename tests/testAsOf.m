classdef testAsOf < matlab.unittest.TestCase
    % As-of lookups for vintaged series. SYNTHETIC data.

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
        function revisionAfterAsOfIsInvisible(tc)
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,3,5));
            tc.verifyEqual(T.value(T.date == datetime(2020,1,1)), 3.5);
        end

        function revisionVisibleFromItsStartDate(tc)
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,3,6));
            tc.verifyEqual(T.value(T.date == datetime(2020,1,1)), 3.6);
        end

        function observationNotYetReleasedIsAbsent(tc)
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,3,5));
            tc.verifyFalse(any(T.date == datetime(2020,2,1)));
        end

        function windowEndIsInclusive(tc)
            % rtEnd of the first window is 2020-03-05: still current that day
            T = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,3,5));
            tc.verifyEqual(height(T), 1);
        end

        function beforeFirstVintageReturnsEmptyWithNote(tc)
            [T, note] = fomc.data.valueAsOf(tc.D, "UNRATE", datetime(2020,2,6));
            tc.verifyEmpty(T);
            tc.verifySubstring(note, "2020-02-07");
        end

        function gapInVintageHistoryCarriesEarlierValue(tc)
            T = fomc.data.valueAsOf(tc.D, "GAPS", datetime(2020,2,15));
            tc.verifyEqual(T.value, 1);
            T = fomc.data.valueAsOf(tc.D, "GAPS", datetime(2020,2,25));
            tc.verifyEqual(T.value, 2);
        end

        function removedObservationDisappearsAfterItsWindow(tc)
            T = fomc.data.valueAsOf(tc.D, "GONE", datetime(2020,2,15));
            tc.verifyEqual(T.value, 5);
            T = fomc.data.valueAsOf(tc.D, "GONE", datetime(2020,3,15));
            tc.verifyEmpty(T);
        end

        function futureDatedObservationIsDropped(tc)
            T = fomc.data.valueAsOf(tc.D, "PROJ", datetime(2020,6,1));
            tc.verifyEmpty(T);
        end

        function excludedSeriesReturnsNote(tc)
            [T, note] = fomc.data.valueAsOf(tc.D, "USREC", datetime(2020,3,1));
            tc.verifyEmpty(T);
            tc.verifySubstring(note, "excluded");
        end

        function unknownSeriesReturnsNote(tc)
            [T, note] = fomc.data.valueAsOf(tc.D, "NOPE", datetime(2020,3,1));
            tc.verifyEmpty(T);
            tc.verifySubstring(note, "Unknown");
        end
    end
end
