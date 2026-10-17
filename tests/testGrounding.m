classdef testGrounding < matlab.unittest.TestCase
    % Citation by paragraph id and the grounding check. SYNTHETIC data, anchor 2020-03-01:
    % January's minutes are public, March's are not.

    properties
        D
        ctx
        calls
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
            tc.ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), tc.D, ...
                tracePath=string(tempname) + ".jsonl");
            % The tools the "model" used: it read participantsViews and asked for UNRATE
            [~, r1] = fomc.tools.dispatch(tc.ctx, "readMinutes", ...
                struct("meetingDate", "2020-01-29", "section", "participantsViews"));
            [~, r2] = fomc.tools.dispatch(tc.ctx, "getSeries", struct("seriesIds", "UNRATE"));
            tc.calls = [r1, r2];
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function idsAreStableAndReadable(tc)
            tc.verifyEqual(tc.D.paras.id(1), "2020-01-29/participantsViews/1");
        end

        function resolvingAnIdGivesTheExactParagraph(tc)
            r = fomc.guard.resolveId(tc.ctx, "2020-01-29/participantsViews/1");
            tc.verifyTrue(r.ok);
            tc.verifyEqual(r.text, "Participants agreed that SYNTHETIC inflation was running below target.");
            tc.verifyEqual(r.meetingDate, "2020-01-29");
            tc.verifyEqual(r.section, "participantsViews");
        end

        function unreleasedMinutesCannotBeResolved(tc)
            r = fomc.guard.resolveId(tc.ctx, "2020-03-18/participantsViews/1");
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.reason, "not public");
            tc.verifyEqual(r.text, "", "the text of unreleased minutes must not be returned");
        end

        function nonexistentIdCannotBeResolved(tc)
            tc.verifyFalse(fomc.guard.resolveId(tc.ctx, "2020-01-29/participantsViews/99").ok);
        end

        function citedIdReturnedByAToolPasses(tc)
            tc.verifyTrue(check(tc, evidence("2020-01-29/participantsViews/1")).ok);
        end

        function realIdNoToolReturnedFails(tc)
            r = check(tc, evidence("2020-01-29/policyAction/1"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.failures(1), "no tool returned");
        end

        function nonexistentIdFails(tc)
            r = check(tc, evidence("2020-01-29/participantsViews/99"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.failures(1), "no such paragraph");
        end

        function idFromUnreleasedMinutesFails(tc)
            r = check(tc, evidence("2020-03-18/participantsViews/1"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.failures(1), "not public");
        end

        function evidenceWithoutAnIdFails(tc)
            tc.verifyFalse(check(tc, struct("claim", "c")).ok);
        end

        function noEvidenceFails(tc)
            r = fomc.guard.checkGrounding(struct("evidence", {{}}, "dataCited", {{}}), tc.ctx, tc.calls);
            tc.verifyFalse(r.ok);
        end

        function tooManyEvidenceItemsFail(tc)
            s = struct("evidence", {repmat({evidence("2020-01-29/participantsViews/1")}, 1, 7)}, "dataCited", {{}});
            tc.verifyFalse(fomc.guard.checkGrounding(s, tc.ctx, tc.calls).ok);
        end

        function citedFigureMatchingAToolResultPasses(tc)
            tc.verifyTrue(checkData(tc, struct("series", "UNRATE", "value", 3.5, "date", "2020-01-01")).ok);
        end

        function citedFigureWithinRoundingPasses(tc)
            tc.verifyTrue(checkData(tc, struct("series", "UNRATE", "value", 3.52, "date", "2020-01-01")).ok);
        end

        function citedFigureWithWrongValueFails(tc)
            r = checkData(tc, struct("series", "UNRATE", "value", 9, "date", "2020-01-01"));
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.failures(1), "3.5");
        end

        function citedFigureNeverShownFails(tc)
            tc.verifyFalse(checkData(tc, struct("series", "PAYEMS", "value", 150000, "date", "2020-01-01")).ok);
        end

        function tooManyDataItemsFail(tc)
            item = struct("series", "UNRATE", "value", 3.5, "date", "2020-01-01");
            % Helper: check one data item, with valid evidence beside it
            s = struct("evidence", {{evidence("2020-01-29/participantsViews/1")}}, "dataCited", {repmat({item}, 1, 7)});
            r = fomc.guard.checkGrounding(s, tc.ctx, tc.calls);
            tc.verifyFalse(r.ok);
            tc.verifySubstring(strjoin(r.failures), "Too many data items");
        end

        function answerCitationsAreResolvedAndVerified(tc)
            known = fomc.guard.idsIn(string({tc.calls.result}));
            answer = "Inflation was low [2020-01-29/participantsViews/1] and spending fell [2020-03-18/participantsViews/1].";
            c = fomc.guard.citations(answer, tc.ctx, known);
            tc.verifyEqual(numel(c), 2);
            tc.verifyTrue(c(1).ok);
            tc.verifyEqual(c(1).text, "Participants agreed that SYNTHETIC inflation was running below target.");
            tc.verifyFalse(c(2).ok, "minutes not public on the anchor date");
        end

        function aPlausibleButUnreturnedIdIsNotVerified(tc)
            known = fomc.guard.idsIn(string({tc.calls.result}));
            c = fomc.guard.citations("See [2020-01-29/policyAction/1].", tc.ctx, known);
            tc.verifyFalse(c.ok);
            tc.verifySubstring(c.reason, "no tool returned");
        end

        function aShortenedIdIsRepairedWhenOnlyOneKnownIdMatches(tc)
            known = ["2020-01-29/participantsViews/1"; "2020-03-18/policyAction/2"];
            out = fomc.guard.expandIds("Inflation was low (participantsViews/1) and they cut [policyAction/2].", known);
            tc.verifyEqual(out, "Inflation was low (2020-01-29/participantsViews/1) and they cut [2020-03-18/policyAction/2].");
        end

        function aShortenedIdMatchingTwoMeetingsIsLeftAlone(tc)
            known = ["2020-01-29/policyAction/2"; "2020-03-18/policyAction/2"];
            text = "They held (policyAction/2).";
            tc.verifyEqual(fomc.guard.expandIds(text, known), text);
        end

        function aShortenedIdNoToolReturnedIsLeftAlone(tc)
            text = "See participantsViews/9.";
            tc.verifyEqual(fomc.guard.expandIds(text, "2020-01-29/participantsViews/1"), text);
        end

        function fullIdsAreNotChanged(tc)
            known = ["2020-01-29/policyAction/2"; "2020-03-18/policyAction/2"];
            text = "Held [2020-01-29/policyAction/2].";
            tc.verifyEqual(fomc.guard.expandIds(text, known), text);
        end

        function textWithoutIdsHasNoCitations(tc)
            tc.verifyEmpty(fomc.guard.citations("No ids here.", tc.ctx, strings(0, 1)));
        end
    end
end

function r = check(tc, e)
% Helper: check one evidence item against the tool results
s = struct("evidence", {{e}}, "dataCited", {{}});
r = fomc.guard.checkGrounding(s, tc.ctx, tc.calls);
end

function r = checkData(tc, item)
s = struct("evidence", {{evidence("2020-01-29/participantsViews/1")}}, "dataCited", {{item}});
r = fomc.guard.checkGrounding(s, tc.ctx, tc.calls);
end

function e = evidence(id)
% Helper: an evidence item citing the given paragraph id
e = struct("claim", "A claim.", "id", id);
end
