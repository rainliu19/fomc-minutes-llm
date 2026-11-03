classdef testPrefetch < matlab.unittest.TestCase
    % What the harness looks up itself: decision cards, ranked passages, and the statement that
    % a meeting's minutes are not public yet. SYNTHETIC data for the logic, REAL for ranking.
    % Anchor 2020-03-01: January's minutes are public (released 2020-02-19), March's are not
    % (released 2020-04-08).

    properties
        D
        cfg
        ctx
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
            tc.cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function aDecisionQuestionWithNoDateGetsTheLatestCard(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What did the Committee decide at its latest meeting?", false);
            tc.verifyEqual([recs.name], "getDecision");
            tc.verifySubstring(text, "Action: hold");
            tc.verifySubstring(text, "[2020-01-29/policyAction/1]");
        end

        function aNamedMonthGetsThatMeetingsCard(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What did the Committee decide in January 2020?", false);
            tc.verifyEqual(numel(recs), 1);
            tc.verifySubstring(text, "ended 2020-01-29");
        end

        function aMeetingWhoseMinutesAreNotPublicIsSaidSoWithoutLeakingAnything(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What did the Committee decide in March 2020?", false);
            tc.verifyEqual([recs.name], "prefetchNotice");
            tc.verifySubstring(text, "not public on the anchor date");
            tc.verifySubstring(text, "2020-01-29");                      % the latest available minutes
            tc.verifyFalse(contains(text, "2020-04-08"), "the release date of unreleased minutes must not appear");
            tc.verifyFalse(contains(text, "lower the target"), "the decision itself must not appear");
        end

        function anUnreleasedMeetingIsAnsweredWithoutAskingTheModel(tc)
            m = fomc.llm.Mock({struct("content", "The Committee cut rates to zero.")});    % a made-up decision
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            [s, answer, structured, calls] = fomc.runTurn(s, "What did the Committee decide in March 2020?");
            tc.verifyEmpty(m.Seen, "the model must not be called");
            tc.verifySubstring(answer, "not public as of 2020-03-01");
            tc.verifySubstring(answer, "2020-01-29");
            tc.verifyFalse(contains(answer, ["2020-04-08", "cut", "zero"]));
            tc.verifyEmpty(structured);
            tc.verifyEqual([calls.name], "prefetchNotice");
            tc.verifyEqual(numel(s.history.Messages), 2);
        end

        function aFollowUpAfterTheDirectAnswerReachesTheModel(tc)
            m = fomc.llm.Mock({struct("content", "Rates were held in January.")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            s = fomc.runTurn(s, "What did the Committee decide in March 2020?");
            [~, answer] = fomc.runTurn(s, "And in January 2020?");
            tc.verifyEqual(answer, "Rates were held in January.");
            tc.verifyEqual(numel(m.Seen), 1);
        end

        function anAnalysisOfAnUnreleasedMeetingIsAlsoAnsweredDirectly(tc)
            m = fomc.llm.Mock({struct("content", "READY")});
            [answer, structured] = fomc.runAgent("Analyze it.", datetime(2020,3,1), Format="analysis", ...
                MeetingDate=datetime(2020,3,18), Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEmpty(m.Seen);
            tc.verifySubstring(answer, "not public as of");
            tc.verifyEmpty(structured);
        end

        function theWebTurnShowsTheDirectAnswerWithoutAFailedAnalysisBanner(tc)
            out = webTurn(tc, "ignored", "What did the Committee decide in March 2020?");
            tc.verifySubstring(string(out.answer), "not public as of");
            tc.verifyFalse(contains(string(out.answer), "did not pass its checks"));
        end

        function theWebTurnMarksTheLookupsTheHarnessRan(tc)
            % The decision card is looked up through getDecision before the model starts; the page
            % showed it as a tool the model chose. The turn now says which calls were lookups.
            m = fomc.llm.Mock({struct("content", "It held. [2020-01-29/policyAction/1]")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            [s, ~, ~, calls] = fomc.runTurn(s, "What did the Committee decide at its latest meeting?");
            tc.verifyEqual([string(calls.name), string(s.lastLookups)], ["getDecision", "1"]);
            out = webTurn(tc, "It held. [2020-01-29/policyAction/1]");
            tc.verifyEqual(out.toolCalls(1).name, 'getDecision');
            tc.verifyTrue(out.toolCalls(1).lookup);
        end

        function anIsoDateForAnUnreleasedMeetingIsHandledTheSameWay(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What was the vote at the 2020-03-18 meeting?", false);
            tc.verifyEqual([recs.name], "prefetchNotice");
            tc.verifySubstring(text, "not public on the anchor date");
        end

        function aTopicQuestionGetsRankedPassagesWithIds(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "What did participants say about the trade dispute?", false);
            tc.verifyEqual([recs.name], "prefetchPassages");
            tc.verifySubstring(text, "[2020-01-29/participantsViews/2]");
        end

        function passagesNeverComeFromUnreleasedMinutes(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "Did participants say spending weakened sharply?", false);
            tc.verifyFalse(contains(text, "2020-03-18"));
            tc.verifyFalse(any(contains(string({recs.result}), "2020-03-18")));
        end

        function aQuestionAboutNoMinutesOrDataTopicGetsNothing(tc)
            [text, recs] = fomc.focus.prefetch(tc.ctx, "Tell me something interesting.", false);
            tc.verifyEqual(text, "");
            tc.verifyEmpty(recs);
        end

        function prefetchCanBeSwitchedOff(tc)
            ctx2 = fomc.context(datetime(2020,3,1), fomc.config(verbose=false, prefetch=false), tc.D, ...
                tracePath=string(tempname) + ".jsonl");
            [text, recs] = fomc.focus.prefetch(ctx2, "What did the Committee decide?", false);
            tc.verifyEqual(text, "");
            tc.verifyEmpty(recs);
        end

        function aYearAloneFallsBackToPassagesBecauseTheMeetingIsAmbiguous(tc)
            [~, recs] = fomc.focus.prefetch(tc.ctx, "What did the Committee decide in 2019?", false);
            tc.verifyFalse(any(string({recs.name}) == "getDecision"));
        end

        function analysisModeFetchesTheCardForTheNamedMeeting(tc)
            [~, recs] = fomc.focus.prefetch(tc.ctx, "Focus on the FOMC meeting that ended on 2020-01-29. Why?", true);
            tc.verifyEqual([recs.name], "getDecision");
        end

        function theTurnCarriesTheCardAndRemembersItsIds(tc)
            m = fomc.llm.Mock({struct("content", "It held. [2020-01-29/policyAction/1]")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            [s, ~, ~, calls] = fomc.runTurn(s, "What did the Committee decide at its latest meeting?");
            tc.verifyEqual([calls.name], "getDecision");
            tc.verifySubstring(string(s.history.Messages{1}.content), "[Decision card");
            tc.verifyTrue(any(s.known == "2020-01-29/policyAction/1"));
            tc.verifyEqual(numel(m.Seen), 1, "the model did not need a tool round");
        end

        function aPrefetchedDecisionCountsAsReadingSoThereIsNoNudge(tc)
            m = fomc.llm.Mock({struct("content", "It held.")});
            [~, ~, ~, s] = fomc.runAgent("What did the Committee decide?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            contents = cellfun(@(x) string(x.content), s.history.Messages);
            tc.verifyFalse(any(contains(contents, "You have not read any minutes yet")));
        end

        function analysisModeAsksForReadyNotADraft(tc)
            m = fomc.llm.Mock({struct("content", "READY"), struct("content", "{}")});
            [~, ~, ~, s] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", MeetingDate=datetime(2020,1,29), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifySubstring(string(s.history.Messages{1}.content), "reply with just: READY");
        end

        function theStanceInAnAnalysisFollowsTheDecisionCardNotTheModel(tc)
            ev = struct("claim", "c", "id", "2020-01-29/policyAction/1");
            j = string(jsonencode(struct("meetingDate", "2020-01-29", "summary", "s", "policyStance", "tightening", ...
                "keyDrivers", {{"a"}}, "evidence", {{ev}}, "dataCited", {{}}, "caveats", {{"c"}})));
            m = fomc.llm.Mock({struct("content", "READY"), struct("content", j)});
            [~, st] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", MeetingDate=datetime(2020,1,29), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyTrue(st.groundingOk);
            tc.verifyEqual(string(st.policyStance), "neutral");          % the January card says hold
            tc.verifyEqual(string(st.policyStanceSource), "decision card");
        end

        function theWebTurnWarnsWhenAnAnswerAboutTheMinutesCitesNothing(tc)
            out = webTurn(tc, "They held rates.");
            tc.verifyNotEmpty(out.warning);
            tc.verifySubstring(out.warning, "cites no paragraph");
        end

        function theWebTurnDoesNotWarnWhenTheCitationIsVerified(tc)
            out = webTurn(tc, "They held rates [2020-01-29/policyAction/1].");
            tc.verifyEmpty(out.warning);
            tc.verifyEqual(numel(out.citations), 1);
        end

        function theWebTurnFlagsAnIdNoToolReturned(tc)
            out = webTurn(tc, "They held rates [2020-01-29/participantsViews/2].");
            tc.verifyNotEmpty(out.warning);
        end

        function prefetchedPassagesCountAsReadingSoThereIsNoNudge(tc)
            m = fomc.llm.Mock({struct("content", "Participants saw a trade dispute.")});
            [~, ~, ~, s] = fomc.runAgent("What did participants say about the trade dispute?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            contents = cellfun(@(x) string(x.content), s.history.Messages);
            tc.verifyFalse(any(contains(contents, "You have not read any minutes yet")));
        end

        function aQuestionAboutChangeGetsPassagesFromDifferentYears(tc)
            allData = fomc.data.load();
            cx = fomc.context(datetime(2022,12,31), tc.cfg, allData, tracePath=string(tempname) + ".jsonl");
            q = "How did the Committee's view of inflation change between 2021 and 2022?";
            cx.focus = fomc.focus.window(q, cx.asOf, tc.cfg);
            hits = fomc.retrieve.rank(q, cx, 3);
            years = unique(year(datetime([hits.meetingDate], InputFormat="yyyy-MM-dd")));
            tc.verifyGreaterThanOrEqual(numel(years), 2);
        end

        function aMangledRateRangeIsCaught(tc)
            sources = "decided to raise the target range to 1-1/2 to 1-3/4 percent";
            bad = fomc.guard.checkFigures("The Committee raised it to 1/2 to 13/4 percent.", sources);
            tc.verifyEqual(bad, "1/2 to 13/4 percent");
        end

        function aCorrectRateRangePasses(tc)
            sources = "decided to raise the target range to 1-1/2 to 1-3/4 percent";
            tc.verifyEmpty(fomc.guard.checkFigures("It raised the range to 1-1/2 to 1-3/4 percent.", sources));
        end

        function figuresWithoutFractionsAreNotChecked(tc)
            tc.verifyEmpty(fomc.guard.checkFigures("Unemployment was 4.4 percent.", "nothing"));
        end

        function anHonestNotPublicYetAnswerIsNeitherNudgedNorWarned(tc)
            out = webTurn(tc, "The March 2020 minutes are not public yet; the latest are from 2020-01-29.", ...
                "What did the Committee decide in March 2020?");
            tc.verifyEmpty(out.warning);
        end

        function theWebTurnWarnsAboutAMangledFigure(tc)
            out = webTurn(tc, "They lowered the range to 9/4 to 11/4 percent [2020-01-29/policyAction/1].");
            tc.verifySubstring(out.warning, "9/4 to 11/4 percent");
        end

        function theWebAnalysisShowsTheCheckedSummary(tc)
            ev = struct("claim", "c", "id", "2020-01-29/policyAction/1");
            j = string(jsonencode(struct("meetingDate", "2020-01-29", "summary", "The Committee held rates.", ...
                "policyStance", "neutral", "keyDrivers", {{"a"}}, "evidence", {{ev}}, "dataCited", {{}}, "caveats", {{"c"}})));
            id = "test-" + string(randi(1e9));
            m = fomc.llm.Mock({struct("content", "A draft with an invented claim about rising inflation."), struct("content", j)});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            fomc.web.store("set", id, s);
            cleanup = onCleanup(@() fomc.web.store("remove", id));
            out = jsondecode(fomc.web.turn(id, "Analyze the 2020-01-29 meeting.", "", "high", "", ""));
            tc.verifySubstring(out.answer, "The Committee held rates.");
            tc.verifyFalse(contains(out.answer, "rising inflation"), "the unchecked draft must not be shown");
        end

        function rankingPutsParagraphsAboutTheTopicFirst(tc)
            allData = fomc.data.load();
            cx = fomc.context(datetime(2020,4,8), tc.cfg, allData, tracePath=string(tempname) + ".jsonl");
            cx.focus = fomc.focus.window("How did participants describe the labor market?", cx.asOf, tc.cfg);
            hits = fomc.retrieve.rank("How did participants describe the labor market?", cx, 3);
            tc.verifyEqual(numel(hits), 3);
            tc.verifyTrue(all(contains(lower([hits.snippet]), "labor") | contains(lower([hits.snippet]), "employment")));
            tc.verifyGreaterThanOrEqual(hits(1).score, hits(end).score);
        end

        function rankingRespectsTheAnchorAndTheWindow(tc)
            allData = fomc.data.load();
            cx = fomc.context(datetime(2012,1,1), tc.cfg, allData, tracePath=string(tempname) + ".jsonl");
            cx.focus = fomc.focus.window("inflation expectations in 2010", cx.asOf, tc.cfg);
            hits = fomc.retrieve.rank("inflation expectations", cx, 5);
            tc.verifyNotEmpty(hits);
            dates = datetime([hits.meetingDate], InputFormat="yyyy-MM-dd");
            tc.verifyTrue(all(dates >= cx.focus.start & dates <= cx.focus.end));
            for h = hits
                rel = allData.meetings.ReleaseDate(allData.meetings.MeetingDate == datetime(h.meetingDate, InputFormat="yyyy-MM-dd"));
                tc.verifyLessThanOrEqual(rel, cx.asOf);
            end
        end

        function aQuestionOfOnlyCommonWordsFindsNothing(tc)
            tc.verifyEmpty(fomc.retrieve.rank("What did they say about the meeting?", tc.ctx, 3));
        end
    end
end

function out = webTurn(tc, reply, question)
% One web turn with a scripted model. SYNTHETIC data.
id = "test-" + string(randi(1e9));
m = fomc.llm.Mock({struct("content", reply)});
s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
fomc.web.store("set", id, s);
cleanup = onCleanup(@() fomc.web.store("remove", id));
if nargin < 3
    question = "What did the Committee decide at its latest meeting?";
end
out = jsondecode(fomc.web.turn(id, question, "", "low", "", ""));
end
