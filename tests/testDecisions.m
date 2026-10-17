classdef testDecisions < matlab.unittest.TestCase
    % Decision cards on REAL minutes, checked against the actual change in the target rate
    % (FRED). No model. Spot checks were read off the minutes text, not from memory.

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
        function cardsAgreeWithTheActualRateChangeForEveryMeeting(tc)
            % Work out from the FRED rate data what each meeting actually did, then compare with the card
            M = tc.D.meetings; C = tc.D.cards; W = tc.D.wide;
            % upper limit of the target range; the single target before December 2008
            target = W.DFEDTARU;
            old = isnan(target);
            target(old) = W.DFEDTAR(old);
            ok = ~isnan(target);
            d = W.date(ok); v = target(ok);
            at = @(x) v(find(d <= x, 1, "last"));
            delta = arrayfun(@(m) at(m + 1) - at(m - 1), M.MeetingDate);
            % A change of more than 1 basis point counts as a raise or a cut
            truth = repmat("hold", height(M), 1);
            truth(delta > 0.01) = "raise";
            truth(delta < -0.01) = "cut";
            bad = C.action ~= truth;
            tc.verifyFalse(any(bad), "cards disagree with the rate data for: " + ...
                strjoin(fomc.util.fmtDate(M.MeetingDate(bad)).', ", "));
        end

        function everyMeetingHasADecisionSentenceAndTheActionIsKnown(tc)
            tc.verifyFalse(any(tc.D.cards.action == "unknown"));
            tc.verifyFalse(any(tc.D.cards.decisionText == ""));
        end

        function everyRaiseOrCutHasATargetRange(tc)
            C = tc.D.cards;
            tc.verifyFalse(any(C.targetRange(C.action ~= "hold") == ""));
        end

        function theDecisionIdPointsAtTheParagraphTheSentenceCameFrom(tc)
            C = tc.D.cards; P = tc.D.paras;
            for i = 1:height(C)
                k = find(P.id == C.decisionId(i), 1);
                tc.assertNotEmpty(k, "decision id " + C.decisionId(i) + " does not exist");
                tc.verifyTrue(contains(P.text(k), C.decisionText(i)), "sentence not in paragraph for " + C.decisionId(i));
            end
        end

        function aDissentCardNamesWhatTheDissenterPreferred(tc)
            C = tc.D.cards;
            split = ~C.unanimous & C.voteId ~= "";
            share = mean(C.dissentText(split) ~= "");
            tc.verifyGreaterThan(share, 0.9, "dissent explanations found for " + round(100 * share) + "% of split votes");
        end

        function almostEveryMeetingHasAVoteLine(tc)
            tc.verifyLessThanOrEqual(sum(tc.D.cards.voteId == ""), 2);
        end

        function voteCountsAreCountedByCodeAndLookLikeACommittee(tc)
            C = tc.D.cards; has = C.voteId ~= "";
            total = C.nFor(has) + C.nAgainst(has);
            tc.verifyGreaterThanOrEqual(min(total), 8, "fewer voters than a committee has");
            tc.verifyLessThanOrEqual(max(total), 12, "more voters than a committee has");
            tc.verifyTrue(all(C.nAgainst(has & C.unanimous) == 0));
            tc.verifyTrue(all(C.nAgainst(has & ~C.unanimous) >= 1));
        end

        function specificVoteCounts(tc)
            c = card(tc, "2020-03-15"); tc.verifyEqual([c.nFor c.nAgainst], [9 1]);
            c = card(tc, "2022-06-15"); tc.verifyEqual([c.nFor c.nAgainst], [10 1]);
            c = card(tc, "2008-03-18"); tc.verifyEqual([c.nFor c.nAgainst], [8 2]);
            c = card(tc, "2019-07-31"); tc.verifyEqual([c.nFor c.nAgainst], [8 2]);
        end

        function march2020EmergencyCut(tc)
            c = card(tc, "2020-03-15");
            tc.verifyEqual(c.action, "cut");
            tc.verifyEqual(c.targetRange, "0 to 1/4 percent");
            tc.verifyEqual(c.votesAgainst, "Loretta J. Mester");
            tc.verifySubstring(c.dissentText, "1/2 to 3/4 percent");
        end

        function june2022LargeHike(tc)
            c = card(tc, "2022-06-15");
            tc.verifyEqual(c.action, "raise");
            tc.verifyEqual(c.targetRange, "1-1/2 to 1-3/4 percent");
            tc.verifyEqual(c.votesAgainst, "Esther L. George");
        end

        function march2008Cut(tc)
            c = card(tc, "2008-03-18");
            tc.verifyEqual(c.action, "cut");
            tc.verifySubstring(c.targetRange, "2-1/4");
            tc.verifySubstring(c.votesAgainst, "Fisher");
        end

        function july2019CutHadTwoDissenters(tc)
            c = card(tc, "2019-07-31");
            tc.verifyEqual(c.action, "cut");
            tc.verifySubstring(c.votesAgainst, "George");
            tc.verifySubstring(c.votesAgainst, "Rosengren");
        end

        function december2015FirstHikeWasUnanimous(tc)
            c = card(tc, "2015-12-16");
            tc.verifyEqual(c.action, "raise");
            tc.verifyTrue(c.unanimous);
        end

        function september2024CutHadOneDissenter(tc)
            c = card(tc, "2024-09-18");
            tc.verifyEqual(c.action, "cut");
            tc.verifyEqual(c.targetRange, "4-3/4 to 5 percent");
            tc.verifySubstring(c.votesAgainst, "Bowman");
        end

        function september2026HikeWasUnanimous(tc)
            c = card(tc, "2026-09-16");
            tc.verifyEqual(c.action, "raise");
            tc.verifyTrue(c.unanimous);
        end
    end
end

function c = card(tc, date)
% Helper: the decision card for the meeting that ended on a date
k = find(tc.D.meetings.MeetingDate == datetime(date, InputFormat="yyyy-MM-dd"), 1);
c = tc.D.cards(k, :);
end
