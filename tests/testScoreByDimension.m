classdef testScoreByDimension < matlab.unittest.TestCase
    % Scoring one dimension per model call (fomc.skills.scoreByDimension), with the fomc-score
    % skill and checks as written. Synthetic minutes and a stand-in model (EchoScoreModel), no
    % real model.

    properties
        D
        ctx
        meetingDate
    end

    % Runs once before the tests: make the test helpers and src/ visible
    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    % Before each test: the synthetic data, anchored after both meetings' minutes
    methods (TestMethodSetup)
        function createContext(tc)
            tc.D = syntheticData();
            tc.meetingDate = "2020-01-29";
            tc.ctx = fomc.context(datetime(2020,4,8), fomc.config(verbose=false), tc.D, ...
                tracePath=string(tempname) + ".jsonl");
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function itReturnsTheSkillsScoreObjectAndPassesItsChecks(tc)
            % January discusses 4 dimensions (rate path, inflation, activity, risks): one call each
            model = EchoScoreModel();
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            tc.verifyTrue(output.ok, strjoin(output.issues, " "));
            tc.verifyEqual([model.Index, output.calls, output.attempts], [4, 4, 1]);
            tc.verifyEqual(sort(string(fieldnames(output.score))), sort(["meeting_date"; "scale"; "dimensions"]));
            tc.verifyEmpty(fomc.guard.validateScores(output.score, string(tc.D.meetings.Body(1)) + newline + ...
                strjoin(string(tc.D.paras.text(tc.D.paras.meetingIdx == 1)), newline), tc.meetingDate, tc.D));
        end

        function aDimensionNoParagraphMentionsIsNotDiscussedWithoutACall(tc)
            model = EchoScoreModel();
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            d = output.score.dimensions.labor_market;
            tc.verifyEqual(string(d.status), "not_discussed");
            tc.verifyEmpty(d.score);
            tc.verifyEmpty(output.passages.labor_market);
        end

        function quotesAreTheMatchingSentencesWordForWord(tc)
            % The stand-in rewords the first sentence it was shown; the quote is the sentence itself
            model = EchoScoreModel();
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            ev = fomc.util.asCell(output.score.dimensions.inflation.evidence);
            tc.verifyEqual(string(ev{1}.quote), "Participants agreed that SYNTHETIC inflation was running below target.");
            tc.verifyEqual(string(ev{1}.paragraph_ref), "2020-01-29/participantsViews/1");
            tc.verifyEqual(output.passages.inflation, "2020-01-29/participantsViews/1");
        end

        function aQuoteMatchingNoSentenceIsRetried(tc)
            % The first call (rate path) quotes made-up text; its retry passes
            model = EchoScoreModel(1);
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            tc.verifyTrue(output.ok, strjoin(output.issues, " "));
            tc.verifyEqual([output.attempts, output.calls], [2, 5]);
        end

        function exhaustedRetriesReturnFailedDimensionMarkers(tc)
            model = EchoScoreModel(Inf);
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            tc.verifyFalse(output.ok);
            tc.verifyEqual(output.attempts, 3);
            tc.verifyTrue(any(output.failedDimensions == "inflation"));
        end

        function aDimensionWithNoValidAnswerIsReportedNotLeftNotDiscussed(tc)
            % Every call returns text that is not JSON (a reply cut off by the output limit)
            model = fomc.llm.Mock({struct("content", "{""status"": ""scored"", ""rationale"": ""cut off")});
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), tc.meetingDate);
            tc.verifyFalse(output.ok);
            tc.verifyTrue(any(startsWith(output.issues, "rate_path: no valid score after 3 attempts")));
            tc.verifyTrue(any(output.failedDimensions == "rate_path"));
        end

        function aCutIsScoredDovishOnTheRatePath(tc)
            % March: the minutes say the Committee decided to lower the target range
            model = EchoScoreModel();
            output = fomc.skills.scoreByDimension(struct("ctx", tc.ctx, "llm", @model.call), "2020-03-18");
            tc.verifyTrue(output.ok, strjoin(output.issues, " "));
            tc.verifyEqual(output.score.dimensions.rate_path.score, -0.5);
            tc.verifyEqual(model.Index, 2, "spending and the cut");
        end

        function savedScoresAreKeptAndMerged(tc)
            % Scoring the rate path, then inflation, keeps both in one saved file
            model = EchoScoreModel();
            s = struct("ctx", tc.ctx, "llm", @model.call);
            folder = string(tempname);
            fomc.skills.scoreCache("write", "mock", tc.meetingDate, ...
                fomc.skills.scoreByDimension(s, tc.meetingDate, Dimensions="rate_path"), Folder=folder);
            out = fomc.skills.scoreByDimension(s, tc.meetingDate, Dimensions="inflation");
            tc.verifyEqual(out.calls, 1);
            tc.verifyEqual(string(out.score.dimensions.rate_path.rationale), "Not scored in this run.");
            r = fomc.skills.scoreCache("write", "mock", tc.meetingDate, out, Folder=folder);
            tc.verifyEqual(sort(string(r.dimensionsScored(:))), ["inflation"; "rate_path"]);
            tc.verifyEqual(string(r.score.dimensions.rate_path.rationale), "Participants described this topic.");
            tc.verifyEqual(fomc.skills.scoreCache("list", "mock", Folder=folder), tc.meetingDate);
            tc.verifyEmpty(fomc.skills.scoreCache("read", "mock", "2020-03-18", Folder=folder));
        end

        function theMinutesDirectionUsesTheAIScoreElseTheWordRules(tc)
            % March 2020: the AI's rate path -0.5 points down; with no saved score, the word rules
            model = EchoScoreModel();
            s = struct("ctx", tc.ctx, "llm", @model.call);
            folder = string(tempname);
            fomc.skills.scoreCache("write", "mock", "2020-03-18", ...
                fomc.skills.scoreByDimension(s, "2020-03-18", Dimensions="rate_path"), Folder=folder);
            range = table(1, 1.25, VariableNames=["lower", "upper"]);
            m = fomc.data.minutesDirection(tc.D, 2, range, Model="mock", Folder=folder);
            tc.verifyEqual([m.source, m.way], ["ai", "down"]);
            tc.verifyEqual(m.score, -0.5);
            tc.verifyEqual(string(m.evidence{1}.paragraph_ref), "2020-03-18/policyAction/1");
            m = fomc.data.minutesDirection(tc.D, 1, range, Model="mock", Folder=folder);
            tc.verifyEqual(m.source, "rules");
            % At a range of 0 to 1/4 percent a dovish score means the rate itself holds
            m = fomc.data.minutesDirection(tc.D, 2, table(0, 0.25, VariableNames=["lower", "upper"]), ...
                Model="mock", Folder=folder);
            tc.verifyEqual(m.way, "hold");
        end

        function eachPromptFitsTheModelsWindow(tc)
            % Real minutes: every prompt, with the system prompt and room for two answers, stays
            % within 8,192 tokens at 3.3 characters a token
            D = fomc.data.load();
            ctx = fomc.context(datetime(2026,10,27), fomc.config(verbose=false), D, tracePath=string(tempname) + ".jsonl");
            model = EchoScoreModel();
            fomc.skills.scoreByDimension(struct("ctx", ctx, "llm", @model.call, ...
                "systemPrompt", fomc.systemPrompt()), "2026-09-16");
            % All seven dimensions are discussed; the stand-in's 0 for a hike makes rate_path retry
            tc.verifyGreaterThanOrEqual(model.Index, 7);
            tc.verifyLessThanOrEqual(max(model.PromptChars) + strlength(fomc.systemPrompt()), (8192 - 2 * 700) * 3.3);
        end
    end
end
