classdef testSkillScoreCases < matlab.unittest.TestCase
    % The scoring skill's chat cases on the REAL minutes, with a fake model (FakeScorer).
    % Checks which meeting gets scored, the point-in-time rules, comparisons, bad inputs and
    % the rate_path rule. No Ollama needed. Whether a real model's scores are sensible
    % (hawkish enough, stable across runs) is in testSkillScoreLive.

    properties
        D
        cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
            tc.cfg = fomc.config(verbose=false);
        end
    end

    methods (Test)
        % --- 1. Basic scoring: it triggers and returns valid JSON ---

        function scoresJune2022AsSchemaShapedJson(tc)
            [answer, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Score the FOMC minutes for 2022-06-15.");
            tc.verifyEqual(fake.Dates, "2022-06-15");
            tc.verifyTrue(structured.ok, strjoin(structured.issues, " "));
            tc.verifyEqual(structured.attempts, 1);
            decoded = jsondecode(answer);
            tc.verifyEqual(string(decoded.meeting_date), "2022-06-15");
            tc.verifyEmpty(fomc.guard.checkSchema(decoded));
        end

        function latestScoresTheMostRecentReleasedMeeting(tc)
            anchor = fomc.latestAnchor(tc.D);
            [~, structured, fake] = tc.ask(anchor, "Score the latest meeting.");
            tc.verifyEqual(fake.Dates, tc.latestMeeting(anchor));   % 2026-09-16 in the current data
            tc.verifyTrue(structured.ok);
        end

        function hawkishWordingTriggersTheSkill(tc)
            [~, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "How hawkish were the minutes from 2019-07-31?");
            tc.verifyEqual(structured.skill, "fomc-score");
            tc.verifyEqual(fake.Dates, "2019-07-31");
        end

        function monthAndYearWordingScoresThatMeeting(tc)
            % "December 2015" has no YYYY-MM-DD date. The skill must score 2015-12-16 or ask
            % for a date; it must not quietly score a different meeting.
            [~, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Rate the tone of the December 2015 meeting.");
            tc.verifyEqual(structured.skill, "fomc-score");
            if ~isempty(fake.Dates)
                tc.verifyEqual(fake.Dates, "2015-12-16", ...
                    "Asked about December 2015 but scored a different meeting.");
            end
        end

        % --- 2. rate_path must match the actual decision ---

        function ratePathRuleUsesTheRealDecisions(tc)
            % meeting, coded decision, a rate_path the guard must reject, one it must accept
            cases = { ...
                "2015-12-16", "raise",  0,     0.25;   % first hike after years at zero
                "2019-07-31", "cut",    0,    -0.25;
                "2024-09-18", "cut",    0.25, -0.5;    % 50 bp cut
                "2008-12-16", "cut",    0,    -1 };    % cut to near zero
            for i = 1:height(cases)
                [date, action, bad, good] = cases{i, :};
                k = find(tc.D.meetings.MeetingDate == datetime(date, InputFormat="yyyy-MM-dd"), 1);
                tc.verifyEqual(string(tc.D.cards.action(k)), action, date + " decision");
                tc.verifyNotEmpty(fomc.guard.checkRateConsistency(scoreWithRatePath(date, bad), date, tc.D), ...
                    date + ": rate_path " + bad + " should be rejected after a " + action);
                tc.verifyEmpty(fomc.guard.checkRateConsistency(scoreWithRatePath(date, good), date, tc.D), ...
                    date + ": rate_path " + good + " should be accepted after a " + action);
            end
        end

        % --- 3. not_discussed ---

        function notDiscussedValidatesOnRealMinutes(tc)
            fake = FakeScorer(tc.D, NotDiscussed="balance_sheet");
            [~, structured] = tc.ask(fomc.latestAnchor(tc.D), "Score the FOMC minutes for 2019-07-31.", fake);
            tc.verifyTrue(structured.ok, strjoin(structured.issues, " "));
            dim = structured.score.dimensions.balance_sheet;
            tc.verifyEqual(string(dim.status), "not_discussed");
            tc.verifyEmpty(dim.score);
            tc.verifyEmpty(dim.confidence);
        end

        function notDiscussedIsReturnedAsJsonNull(tc)
            % schema.json allows number or null for score and string or null for confidence.
            % An empty array ([]) matches neither.
            fake = FakeScorer(tc.D, NotDiscussed="balance_sheet");
            answer = tc.ask(fomc.latestAnchor(tc.D), "Score the FOMC minutes for 2019-07-31.", fake);
            tc.verifySubstring(answer, """score"":null");
            tc.verifySubstring(answer, """confidence"":null");
            tc.verifyFalse(contains(answer, """score"":[]"), "score is [] instead of null");
        end

        function evidenceIsReturnedAsJsonArray(tc)
            % schema.json makes evidence an array. With one quote, it must still be [{...}], not {...}.
            answer = tc.ask(fomc.latestAnchor(tc.D), "Score the FOMC minutes for 2019-07-31.");
            tc.verifyEqual(count(answer, """evidence"":["), 7, ...
                "every dimension's evidence should be a JSON array");
        end

        % --- 4. Comparisons ---

        function readmeComparisonScoresTheDateAndLatest(tc)
            anchor = fomc.latestAnchor(tc.D);
            [answer, structured, fake] = tc.ask(anchor, "Compare the score for 2020-01-29 with the latest meeting.");
            tc.verifyEqual(fake.Dates, ["2020-01-29"; tc.latestMeeting(anchor)]);
            tc.verifyTrue(structured.ok);
            decoded = jsondecode(answer);
            tc.verifyTrue(isfield(decoded, "scores") && isfield(decoded, "validation"));
            tc.verifyNumElements(structured.scores, 2);
        end

        function comparesTwoExplicitMeetings(tc)
            % The router needs a scoring word ("score", "hawkish", ...) or "compare ... meetings".
            % A bare "Compare 2008-12-16 and 2022-06-15." goes to the normal chat agent instead.
            [~, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Compare the scores for 2008-12-16 and 2022-06-15.");
            tc.verifyEqual(fake.Dates, ["2008-12-16"; "2022-06-15"]);
            tc.verifyTrue(structured.ok);
            tc.verifyEqual(string(structured.scores{1}.meeting_date), "2008-12-16");
            tc.verifyEqual(string(structured.scores{2}.meeting_date), "2022-06-15");
        end

        function comparingAMeetingWithItselfIsRejected(tc)
            [answer, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Compare the scores for 2022-06-15 and 2022-06-15.");
            tc.verifyFalse(structured.ok);
            tc.verifySubstring(answer, "at least two distinct meeting dates");
            tc.verifyEmpty(fake.Dates, "the model should not be called");
        end

        % --- 5. Point-in-time guardrails ---

        function refusesMeetingAfterTheAnchor(tc)
            [~, structured, fake] = tc.ask(datetime(2022,1,1), "Score the minutes for 2022-06-15.");
            tc.verifyFalse(structured.ok);
            tc.verifyEmpty(fake.Dates, "scored minutes that were not public yet");
            tc.verifySubstring(strjoin(structured.issues, " "), ...
                "No minutes for meeting 2022-06-15 are available by anchor date 2022-01-01");
        end

        function refusesMeetingHeldButNotYetReleased(tc)
            % The meeting was 2022-06-15; its minutes came out 2022-07-06, after this anchor
            k = find(tc.D.meetings.MeetingDate == datetime(2022,6,15), 1);
            tc.assertGreaterThan(tc.D.meetings.ReleaseDate(k), datetime(2022,6,20));
            [~, structured, fake] = tc.ask(datetime(2022,6,20), "Score the minutes for 2022-06-15.");
            tc.verifyFalse(structured.ok);
            tc.verifyEmpty(fake.Dates, "scored minutes that were not public yet");
        end

        function latestRespectsAnEarlyAnchor(tc)
            [~, structured, fake] = tc.ask(datetime(2022,1,1), "Score the latest meeting.");
            tc.verifyEqual(fake.Dates, "2021-11-03");   % released 2021-11-24; December's came out in January
            tc.verifyTrue(structured.ok);
        end

        function comparisonLatestRespectsAnEarlyAnchor(tc)
            [~, ~, fake] = tc.ask(datetime(2022,1,1), "Compare the score for 2020-01-29 with the latest meeting.");
            tc.verifyEqual(fake.Dates, ["2020-01-29"; "2021-11-03"]);
        end

        % --- 6. Bad inputs ---

        function nonMeetingDateIsRefusedNotRoundedToANearbyMeeting(tc)
            [~, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Score 2022-06-14.");
            tc.verifyFalse(structured.ok);
            tc.verifyEmpty(fake.Dates, "scored a different meeting instead of refusing");
            tc.verifySubstring(strjoin(structured.issues, " "), "2022-06-14");
            s = tc.session(fomc.latestAnchor(tc.D), FakeScorer(tc.D));
            tc.verifyError(@() fomc.skills.scoreMeeting(s, "2022-06-14"), "fomc:skills:meetingUnavailable");
        end

        function dateBeforeTheDataIsRefused(tc)
            [~, structured, fake] = tc.ask(fomc.latestAnchor(tc.D), "Score 2007-12-11.");
            tc.verifyFalse(structured.ok);
            tc.verifyEmpty(fake.Dates);
            tc.verifySubstring(strjoin(structured.issues, " "), "No minutes for meeting 2007-12-11");
        end
    end

    methods
        function s = session(tc, asOf, fake)
            s = fomc.newSession(asOf, tc.cfg, Llm=@fake.call, Data=tc.D, ...
                TracePath=string(tempname) + ".jsonl");
        end

        function [answer, structured, fake] = ask(tc, asOf, question, fake)
            % One chat turn through the real router (fomc.runTurn) with the fake model
            if nargin < 4
                fake = FakeScorer(tc.D);
            end
            s = tc.session(asOf, fake);
            [~, answer, structured] = fomc.runTurn(s, question);
            answer = string(answer);
        end

        function d = latestMeeting(tc, asOf)
            % The meeting whose minutes were released most recently by asOf
            M = tc.D.meetings;
            released = find(M.ReleaseDate <= asOf);
            [~, i] = max(M.ReleaseDate(released));
            d = fomc.util.fmtDate(M.MeetingDate(released(i)));
        end
    end
end

function result = scoreWithRatePath(meetingDate, ratePath)
dim = struct("status", "scored", "score", 0, "confidence", "medium", ...
    "rationale", "Test.", "evidence", {{struct("quote", "test")}});
dims = struct("rate_path", dim, "inflation", dim, "labor_market", dim, "economic_activity", dim, ...
    "financial_conditions", dim, "balance_sheet", dim, "risk_balance", dim);
dims.rate_path.score = ratePath;
result = struct("meeting_date", meetingDate, "scale", "hawkish_positive", "dimensions", dims);
end
