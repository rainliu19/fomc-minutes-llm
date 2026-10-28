classdef testSkillScoreGuards < matlab.unittest.TestCase
    properties
        D
        ctx
        meetingText
        meetingDate
    end

    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    methods (TestMethodSetup)
        function createContext(tc)
            tc.D = syntheticData();
            tc.meetingDate = "2020-01-29";
            tc.meetingText = string(tc.D.meetings.Body(1));
            cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,4,8), cfg, tc.D, ...
                tracePath=string(tempname) + ".jsonl");
        end
    end

    methods (Test)
        function validOutputPassesEveryCheck(tc)
            issues = fomc.guard.validateScores(validScore(tc.meetingDate), ...
                tc.meetingText, tc.meetingDate, tc.D);
            tc.verifyEmpty(issues);
        end

        function schemaRequiresDimensionsAndRejectsUnexpectedKeys(tc)
            result = validScore(tc.meetingDate);
            result.extra = true;
            result.dimensions.extra_dimension = result.dimensions.inflation;
            issues = fomc.guard.checkSchema(result);
            tc.verifyTrue(any(contains(issues, "unexpected key 'extra'")));
            tc.verifyTrue(any(contains(issues, "unexpected key 'extra_dimension'")));
        end

        function scoreMustUseQuarterPointIncrementsAndValidConfidence(tc)
            result = validScore(tc.meetingDate);
            result.dimensions.inflation.score = 0.3;
            result.dimensions.inflation.confidence = "certain";
            issues = fomc.guard.checkScoreRange(result);
            tc.verifyTrue(any(contains(issues, "inflation.score")));
            tc.verifyTrue(any(contains(issues, "inflation.confidence")));
        end

        function notDiscussedRequiresNullScoreAndNoEvidence(tc)
            result = validScore(tc.meetingDate);
            result.dimensions.balance_sheet.status = "not_discussed";
            result.dimensions.balance_sheet.score = 0;
            issues = fomc.guard.checkScoreRange(result);
            tc.verifyTrue(any(contains(issues, "balance_sheet.score")));
            tc.verifyTrue(any(contains(issues, "balance_sheet.evidence")));
        end

        function quoteNormalizationHandlesPunctuationAndWhitespace(tc)
            result = validScore(tc.meetingDate);
            result.dimensions.inflation.evidence = {struct("quote", ...
                "Participants agreed that “SYNTHETIC” inflation was running below target.", ...
                "paragraph_ref", "test")};
            source = "Participants agreed that ""SYNTHETIC"" inflation" + char(160) + ...
                "was running below target.";
            issues = fomc.guard.checkQuotes(result, source);
            % The other dimensions' quotes are not in this one-sentence source; only inflation's is
            tc.verifyFalse(any(startsWith(issues, "inflation:")), strjoin(issues, " "));
        end

        function quoteMustBeVerbatimAndAtMostFortyWords(tc)
            result = validScore(tc.meetingDate);
            result.dimensions.inflation.evidence = {struct("quote", "not in the minutes", ...
                "paragraph_ref", "test")};
            issues = fomc.guard.checkQuotes(result, tc.meetingText);
            tc.verifyTrue(any(contains(issues, "not found")));
            longQuote = strjoin(repmat("word", 1, 41), " ");
            result.dimensions.inflation.evidence = {struct("quote", longQuote, "paragraph_ref", "test")};
            issues = fomc.guard.checkQuotes(result, tc.meetingText);
            tc.verifyTrue(any(contains(issues, "exceeds 40 words")));
        end

        function ratePathMustAgreeWithActualDecision(tc)
            result = validScore("2020-03-18");
            result.dimensions.rate_path.score = 0;
            issues = fomc.guard.checkRateConsistency(result, "2020-03-18", tc.D);
            tc.verifyNotEmpty(issues);
            result.dimensions.rate_path.score = -0.25;
            issues = fomc.guard.checkRateConsistency(result, "2020-03-18", tc.D);
            tc.verifyEmpty(issues);
            tc.D.cards.action(1) = "raise";
            result = validScore(tc.meetingDate);
            result.dimensions.rate_path.score = 0;
            result.dimensions.rate_path.rationale = "This was described as the final hike.";
            issues = fomc.guard.checkRateConsistency(result, tc.meetingDate, tc.D);
            tc.verifyNotEmpty(issues);
            result.dimensions.rate_path.score = 0.25;
            issues = fomc.guard.checkRateConsistency(result, tc.meetingDate, tc.D);
            tc.verifyEmpty(issues);
        end

        function rationaleCannotUseDatesAfterRelease(tc)
            result = validScore(tc.meetingDate);
            result.dimensions.inflation.rationale = "Later conditions in 2021-01-01 confirmed the trend.";
            issues = fomc.guard.checkAsOf(result, tc.D.meetings.ReleaseDate(1));
            tc.verifyTrue(any(contains(issues, "2021-01-01")));
        end

        function generationRetriesValidationFailures(tc)
            % The first call (rate_path) quotes made-up text; its retry passes
            model = EchoScoreModel(1);
            s = struct("ctx", tc.ctx, "llm", @model.call);

            output = fomc.skills.scoreMeeting(s, tc.meetingDate);

            tc.verifyTrue(output.ok);
            tc.verifyEqual(output.attempts, 2);
            tc.verifyEmpty(output.issues);
        end

        function exhaustedRetriesReturnFailedDimensionMarkers(tc)
            model = EchoScoreModel(Inf);
            s = struct("ctx", tc.ctx, "llm", @model.call);

            output = fomc.skills.scoreMeeting(s, tc.meetingDate);

            tc.verifyFalse(output.ok);
            tc.verifyEqual(output.attempts, 3);
            tc.verifyTrue(any(output.failedDimensions == "inflation"));
            tc.verifyNotEmpty(output.issues);
        end

        function aDimensionWithNoValidAnswerIsReportedNotLeftNotDiscussed(tc)
            % Every call returns text that is not JSON (a reply cut off by the output limit)
            model = fomc.llm.Mock({struct("content", "{""status"": ""scored"", ""rationale"": ""cut off")});
            s = struct("ctx", tc.ctx, "llm", @model.call);
            output = fomc.skills.scoreMeeting(s, tc.meetingDate);
            tc.verifyFalse(output.ok);
            tc.verifyTrue(any(startsWith(output.issues, "rate_path: no valid score after 3 attempts")));
            tc.verifyTrue(any(output.failedDimensions == "rate_path"));
        end

        function quotesAreTheNamedSentencesWordForWord(tc)
            % The model names S1; the quote is that sentence of the minutes, with its paragraph id
            model = EchoScoreModel();
            s = struct("ctx", tc.ctx, "llm", @model.call);
            output = fomc.skills.scoreMeeting(s, tc.meetingDate);
            ev = fomc.util.asCell(output.score.dimensions.inflation.evidence);
            tc.verifyEqual(string(ev{1}.quote), "Participants agreed that SYNTHETIC inflation was running below target.");
            tc.verifyEqual(string(ev{1}.paragraph_ref), "2020-01-29/participantsViews/1");
            tc.verifyEqual(output.passages.inflation, "2020-01-29/participantsViews/1");
        end

        function runTurnRoutesScoringRequestsThroughTheSkill(tc)
            model = EchoScoreModel();
            s = struct("ctx", tc.ctx, "llm", @model.call, "history", messageHistory, ...
                "systemPrompt", fomc.systemPrompt(), "known", strings(0, 1));

            [s, answer, structured, calls] = fomc.runTurn(s, ...
                "Score the FOMC minutes for 2020-01-29.", Format="chat");

            tc.verifyTrue(structured.ok);
            tc.verifyEqual(structured.skill, "fomc-score");
            tc.verifySubstring(answer, """meeting_date"":""2020-01-29""");
            tc.verifyEmpty(calls);
            % One call per dimension the minutes discuss: rate path, inflation, activity, risks
            tc.verifyEqual(model.Index, 4);
            tc.verifyEqual(structured.calls, 4);
            tc.verifyEqual(string(structured.score.dimensions.labor_market.status), "not_discussed");
            tc.verifyEqual(numel(s.history.Messages), 2);
        end

        function comparisonWithoutDatesRequestsDatesInsteadOfScoringLatest(tc)
            model = fomc.llm.Mock({struct("content", jsonencode(validScore(tc.meetingDate)))});
            s = struct("ctx", tc.ctx, "llm", @model.call, "history", messageHistory, ...
                "systemPrompt", fomc.systemPrompt(), "known", strings(0, 1));

            [~, answer, structured] = fomc.runTurn(s, "Compare FOMC stance numerically across meetings.");

            tc.verifyFalse(structured.ok);
            tc.verifySubstring(answer, "include at least two distinct meeting dates");
            tc.verifyEqual(model.Index, 0);
        end

        function comparisonAcceptsLatestAndReturnsSchemaScoresSeparately(tc)
            model = EchoScoreModel();
            s = struct("ctx", tc.ctx, "llm", @model.call, "history", messageHistory, ...
                "systemPrompt", fomc.systemPrompt(), "known", strings(0, 1));

            [~, answer, structured] = fomc.runTurn(s, ...
                "Compare the score for 2020-01-29 with the latest meeting.");
            decoded = jsondecode(answer);

            tc.verifyTrue(structured.ok);
            % January discusses 4 dimensions, March 2 (spending, and the cut)
            tc.verifyEqual(model.Index, 6);
            tc.verifyEqual(numel(structured.scores), 2);
            tc.verifyEqual(structured.scores{2}.dimensions.rate_path.score, -0.5);
            tc.verifyEqual(string(structured.scores{1}.meeting_date), "2020-01-29");
            tc.verifyEqual(string(structured.scores{2}.meeting_date), "2020-03-18");
            tc.verifyEqual(numel(structured.validation), 2);
            tc.verifyTrue(isfield(decoded, "scores"));
            tc.verifyTrue(isfield(decoded, "validation"));
            tc.verifyFalse(isfield(decoded.scores, "ok"));
            tc.verifyEqual(sort(string(fieldnames(structured.scores{1}))), ...
                sort(["meeting_date"; "scale"; "dimensions"]));
        end
    end
end

function result = validScore(meetingDate)
evidence = {struct("quote", "The Committee decided to maintain the target range.", ...
    "paragraph_ref", "2020-01-29/policyAction/1")};
dim = struct("status", "scored", "score", 0, "confidence", "high", ...
    "rationale", "Participants described the policy stance.", "evidence", {evidence});
dimensions = struct("rate_path", dim, "inflation", dim, "labor_market", dim, ...
    "economic_activity", dim, "financial_conditions", dim, "balance_sheet", dim, "risk_balance", dim);
result = struct("meeting_date", meetingDate, "scale", "hawkish_positive", "dimensions", dimensions);
end
