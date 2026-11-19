classdef testDataIndex < matlab.unittest.TestCase
    % What the data build works out once (series index, retrieval corpus, data-set id) and the memos that use it. SYNTHETIC data.

    properties
        D
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
        end
    end

    methods (Test)
        function everySeriesInTheAvailabilityTableIsIndexed(tc)
            tc.verifyEqual(sort(string(fieldnames(tc.D.series))), sort(tc.D.avail.series_id));
        end

        function aSeriesComesBackOldestFirstWithoutASort(tc)
            for id = tc.D.avail.series_id.'
                T = fomc.data.valueAsOf(tc.D, id, datetime(2020,3,1));
                tc.verifyTrue(issorted(T.date), id);
            end
        end

        function aNameOutsideTheTableIsUnknown(tc)
            [T, note] = fomc.data.valueAsOf(tc.D, "NOPE", datetime(2020,3,1));
            tc.verifyEmpty(T);
            tc.verifyEqual(note, "Unknown series 'NOPE'.");
            tc.verifyEqual(T.Properties.VariableNames, {'date', 'value', 'availableDate'});
        end

        function theCorpusMatchesTheParagraphs(tc)
            tc.verifyEqual(tc.D.corpus.low, lower(tc.D.paras.text));
            tc.verifyEqual(tc.D.corpus.len, strlength(tc.D.paras.text));
            tc.verifyEqual(tc.D.corpus.avgLen, mean(strlength(tc.D.paras.text)));
        end

        function eachBuiltDataSetHasItsOwnId(tc)
            D2 = fomc.data.build(tc.D.wide, tc.D.vint, tc.D.dict, tc.D.avail, tc.D.meetings);
            tc.verifyNotEqual(D2.id, tc.D.id);
        end

        function theRatePathMemoGivesTheSameAnswerAndFollowsTheDate(tc)
            a1 = datetime(2020,3,1); a2 = datetime(2020,2,1);
            [m1, l1] = fomc.data.ratePath(tc.D, a1);
            [m1b, l1b] = fomc.data.ratePath(tc.D, a1);
            tc.verifyEqual(m1b, m1);
            tc.verifyEqual(l1b, l1);
            [~, l2] = fomc.data.ratePath(tc.D, a2);
            [~, l1c] = fomc.data.ratePath(tc.D, a1);
            tc.verifyEqual(l1c, l1);
            tc.verifyTrue(all(l2.date <= a2));
        end

        function thePolicyViewsMemoIsPerDataSet(tc)
            D2 = tc.D;
            D2.id = "other";
            D2.paras.text(:) = "Nothing about rates here.";
            V1 = fomc.data.policyViews(tc.D, 1);
            V2 = fomc.data.policyViews(D2, 1);
            tc.verifyEqual(V2.views, {});
            tc.verifyEqual(fomc.data.policyViews(tc.D, 1), V1);
        end
    end
end
