classdef testPlainEnglish < matlab.unittest.TestCase
    % Answers must read in plain English: no data codes, section names, tool names or other
    % identifiers. Uses answers a real model wrote, including ones that went wrong.

    % Runs once before the tests: make src/ visible
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function aDataCodeBecomesItsName(tc)
            out = fomc.guard.plainEnglish("Core PCE inflation rose to 3.0% by August 2026 (PCEPILFE), and UNRATE was 4.4%.");
            tc.verifyFalse(contains(out, ["PCEPILFE", "UNRATE"]));
            tc.verifySubstring(out, "the unemployment rate was 4.4%");
            tc.verifySubstring(out, "the core PCE price index");
        end

        function aCodeInParenthesesIsDroppedWhenTheNameIsAlreadyThere(tc)
            out = fomc.guard.plainEnglish("The unemployment rate (UNRATE) was 4.4%.");
            tc.verifyEqual(out, "The unemployment rate was 4.4%.");
        end

        function sectionAndToolNamesBecomeWords(tc)
            out = fomc.guard.plainEnglish("According to participantsViews and the getDecision result, staffOutlook was weak.");
            tc.verifyFalse(contains(out, ["participantsViews", "getDecision", "staffOutlook"]));
            tc.verifySubstring(out, "participants' views");
        end

        function anUnknownCodeWithDigitsIsRemoved(tc)
            out = fomc.guard.plainEnglish("Yields (XYZ10A) rose.");
            tc.verifyEqual(out, "Yields rose.");
        end

        function otherIdentifierStylesAreRemoved(tc)
            out = fomc.guard.plainEnglish("The fooBarBaz value and some_snake_name were noted.");
            tc.verifyFalse(contains(out, ["fooBarBaz", "some_snake_name"]));
        end

        function paragraphIdsFullAndShortSurvive(tc)
            text = "Held [2020-01-29/policyAction/1] and (staffOutlook/2).";
            tc.verifyEqual(fomc.guard.plainEnglish(text), text);
        end

        function everyKnownSeriesCodeHasAPlainName(tc)
            D = fomc.data.load();
            names = fomc.data.plainNames();
            tc.verifyEmpty(setdiff(D.dict.series_id, names.series_id), "a series has no everyday name");
            tc.verifyTrue(all(strlength(names.name) > 3));
        end

        function ordinaryAcronymsAndSentencesAreUntouched(tc)
            text = "The FOMC kept the target range for the federal funds rate, and PCE inflation stayed near 2%.";
            tc.verifyEqual(fomc.guard.plainEnglish(text), text);
        end

        function aRealAnswerThatWentWrongIsCleaned(tc)
            text = "In December 2023, staff revised down inflation forecasts (staffOutlook/2). Core PCE inflation rose to 3.0% by August 2026 (PCEPILFE), indicating a persistent upward trend.";
            out = fomc.guard.plainEnglish(text);
            tc.verifyFalse(contains(out, "PCEPILFE"));
            tc.verifySubstring(out, "(staffOutlook/2)");        % left for the page to mark unverified
        end
    end
end
