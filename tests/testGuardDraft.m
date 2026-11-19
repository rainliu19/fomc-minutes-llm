classdef testGuardDraft < matlab.unittest.TestCase
    % A draft that cannot stand: no words, or against the decision card. Cards here are made up for the test.

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    methods (Test)
        function aBareIdOrAnEmptyReplyHasNoWords(tc)
            tc.verifySubstring(fomc.guard.draftProblem("[2022-06-15/policyAction/3]", tc.calls(true), ""), "no sentence");
            tc.verifySubstring(fomc.guard.draftProblem("(The model returned no text.)", tc.calls(true), ""), "no sentence");
            tc.verifySubstring(fomc.guard.draftProblem("", [], ""), "no sentence");
        end

        function aSentenceWithAnIdPasses(tc)
            a = "The Committee raised the target range to 1-1/2 to 1-3/4 percent [2022-06-15/policyAction/3].";
            tc.verifyEqual(fomc.guard.draftProblem(a, tc.calls(true), ""), "");
        end

        function theVoteMustMatchTheCard(tc)
            said = "The vote was not unanimous: 10 for, 0 against.";
            tc.verifySubstring(fomc.guard.draftProblem(said, tc.calls(true), ""), "unanimous");
            tc.verifyEqual(fomc.guard.draftProblem("Yes, the vote was unanimous, all 10 members voted for the 1.5 range.", tc.calls(true), ""), "");
            tc.verifySubstring(fomc.guard.draftProblem("The vote was unanimous, 10 for and 0 against at 1.5.", tc.calls(false), ""), "not unanimous");
            tc.verifyEqual(fomc.guard.draftProblem("It was not unanimous: Mr. Fisher voted against the 1.5 range.", tc.calls(false), ""), "");
        end

        function theDirectionMustMatchTheCard(tc)
            tc.verifySubstring(fomc.guard.draftProblem("The Committee lowered the range to 1-1/2 to 1-3/4 percent today.", tc.calls(true), ""), "says otherwise");
            tc.verifyEqual(fomc.guard.draftProblem("The Committee raised the range to 1-1/2 to 1-3/4 percent today.", tc.calls(true), ""), "");
        end

        function aHoldAnswerMayUseKeptOrLeftAndTheLowerBound(tc)
            hold = tc.calls(true);
            hold.result = replace(replace(hold.result, '"raise"', '"hold"'), "1-1/2 to 1-3/4", "2-1/4 to 2-1/2");
            tc.verifyEqual(fomc.guard.draftProblem("The Committee left the range at 2-1/4 to 2-1/2 percent after the December increase.", hold, ""), "");
            tc.verifyEqual(fomc.guard.draftProblem("It kept the lower bound at 2-1/4 and the upper at 2-1/2 percent.", hold, ""), "");
            tc.verifySubstring(fomc.guard.draftProblem("The Committee raised the range to 2-1/4 to 2-1/2 percent.", hold, ""), "says otherwise");
        end

        function aDecisionAnswerNeedsAFigure(tc)
            tc.verifySubstring(fomc.guard.draftProblem("The Committee raised the federal funds rate at that meeting.", tc.calls(true), ""), "no figure");
        end

        function aVoteQuestionNeedsTheVoteInTheAnswer(tc)
            q = "Was the vote unanimous at the June 2022 meeting?";
            tc.verifySubstring(fomc.guard.draftProblem("The vote was 10 for, with Powell and others voting in favor of the range.", tc.calls(true), q), "unanimous");
            tc.verifyEqual(fomc.guard.draftProblem("Yes, the vote was unanimous with all 10 members for the range 1.5.", tc.calls(true), q), "");
            q2 = "Who voted against?";
            tc.verifySubstring(fomc.guard.draftProblem("The range was raised at the meeting to 1-1/2 percent, by a majority.", tc.calls(false), q2), "Name who voted against");
            tc.verifySubstring(fomc.guard.draftProblem("Mr. Fisher voted against the raise to 1-1/2 percent.", tc.calls(false), q2), "as written");
            tc.verifyEqual(fomc.guard.draftProblem("Richard W. Fisher voted against the raise to 1-1/2 percent.", tc.calls(false), q2), "");
        end

        function aCardMeansTheMinutesAreAvailable(tc)
            tc.verifySubstring(fomc.guard.draftProblem("The minutes for the December meeting are not available yet.", tc.calls(true), ""), "decision card has its facts");
            tc.verifyEqual(fomc.guard.draftProblem("The minutes for the December meeting are not available yet.", [], ""), "");
            tc.verifyEqual(fomc.guard.draftProblem("The range was not publicly known in 2008, but it was 1-1/2 to 1-3/4 percent here.", tc.calls(true), ""), "");
            q = "Was the vote unanimous?";
            tc.verifySubstring(fomc.guard.draftProblem("The vote was 10 for, 0 against, with Powell and others voting in favor. Against: None.", tc.calls(true), q), "unanimous");
        end

        function aCopyOfTheLookupTextOrAnIdListIsNoAnswer(tc)
            tc.verifySubstring(fomc.guard.draftProblem("ANCHOR DATE: 2016-01-11. Today is 2016-01-11; nothing after it is known.", [], ""), "repeats the lookup");
            tc.verifySubstring(fomc.guard.draftProblem("The answer has no sentence. Rewrite the answer to fix only that.", [], ""), "repeats the lookup");
            tc.verifySubstring(fomc.guard.draftProblem("[" + strjoin(repmat("2024-01-31/participantsViews/12", 1, 8), ", ") + "] and some words after the list", [], ""), "repeats the lookup");
        end

        function noCardMeansOnlyTheWordCheck(tc)
            tc.verifyEqual(fomc.guard.draftProblem("Participants expected rates to hold for some time.", [], ""), "");
        end

        function theCodeAnswerHasTheFactsAndIds(tc)
            t = fomc.guard.cardAnswer(tc.calls(false));
            tc.verifySubstring(t, "raised");
            tc.verifySubstring(t, "1-1/2 to 1-3/4");
            tc.verifySubstring(t, "not unanimous: 9 for, 1 against");
            tc.verifySubstring(t, "Against: Richard W. Fisher");
            tc.verifySubstring(t, "[2022-06-15/policyAction/3]");
            tc.verifyEqual(fomc.guard.draftProblem(t, tc.calls(false), ""), "");
        end

        function withoutACardTheBestPassageAnswers(tc)
            hits = struct("hits", {{struct("id", "2022-06-15/participantsViews/2", "snippet", "Participants saw a strong labor market.")}});
            rec = struct("name", "prefetchPassages", "args", struct(), "result", string(jsonencode(hits)), "ok", true, "ms", 0);
            tc.verifyEqual(fomc.guard.cardAnswer(rec), "The minutes say: Participants saw a strong labor market. [2022-06-15/participantsViews/2]");
            tc.verifyEqual(fomc.guard.cardAnswer([]), "");
        end

        function aWrongTargetRangeIsFoundAndTheCardsRangeIsNot(t)
            c = t.calls(true);
            t.verifyNotEqual(fomc.guard.draftProblem("The Committee raised the target range to between 1-1/4 percent and 2 percent [2022-06-15/policyAction/3].", c, "What happened?"), "");
            t.verifyEqual(fomc.guard.draftProblem("The Committee raised the target range to between 1-1/2 percent and 1-3/4 percent [2022-06-15/policyAction/3].", c, "What happened?"), "");
            t.verifyEqual(fomc.guard.draftProblem("The Committee raised the target range to 1.5 to 1.75 percent [2022-06-15/policyAction/3].", c, "What happened?"), "");
            t.verifyEqual(fomc.guard.draftProblem("It raised the range to 1" + char(8211) + "1/2 to 1" + char(8211) + "3/4 percent.", c, "What happened?"), "");
        end
    end

    methods (Static)
        function c = calls(unanimous)
            vote = struct("nFor", 10, "nAgainst", 0, "unanimous", true, "id", "2022-06-15/policyAction/4");
            vote.("for") = "Jerome H. Powell";
            vote.against = "";
            r = struct("meetingDate", "2022-06-15", "action", "raise", "targetRange", "1-1/2 to 1-3/4", ...
                "decision", struct("text", "The Committee decided to raise.", "id", "2022-06-15/policyAction/3"));
            if ~unanimous
                vote.nFor = 9; vote.nAgainst = 1; vote.unanimous = false; vote.against = "Richard W. Fisher";
                r.dissent = struct("text", "Mr. Fisher dissented.", "id", "2022-06-15/policyAction/5");
            end
            r.vote = vote;
            c = struct("name", "getDecision", "args", struct(), "result", string(jsonencode(r)), "ok", true, "ms", 0);
        end
    end
end
