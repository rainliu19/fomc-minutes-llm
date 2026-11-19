classdef testAgentsModel < matlab.unittest.TestCase
    % Each specialist is a sub-agent: its own prompt and tools, a short model loop on what its code found.
    % Scripted models stand in for Ollama. SYNTHETIC data, anchor 2020-03-01.

    properties
        D
        ctx
        Pad = string(repmat(' ', 1, 6000))   % market evidence shorter than its own limit (agents/market.md) never reaches its model
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
        end
    end

    methods (TestMethodSetup)
        function makeContext(tc)
            tc.ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false, agentSummarizeOver=0), tc.D, tracePath=string(tempname) + ".jsonl");
        end
    end

    methods (Test)
        function aSpecialistRunsOnItsOwnPromptAndToolsAndReportsTheModelsText(tc)
            [r, seen] = tc.specialist("market", "UNRATE: 3.5% on 2020-02-07" + tc.Pad, {struct("content", "Unemployment was 3.5% (UNRATE).")});
            tc.verifyEqual(r.text, "Unemployment was 3.5% (UNRATE).");
            c = fomc.agents.catalog();
            a = c([c.name] == "market");
            tc.verifyEqual(seen.prompt, a.body + newline + newline + fomc.asOfRules());
            tc.verifyEqual(seen.tools, a.tools);
            tc.verifyEqual(seen.calls, 1);
        end

        function aReplyWithANumberNoSourceHasFallsBackToTheCodesText(tc)
            evidence = "UNRATE: 3.5% on 2020-02-07";
            r = tc.specialist("market", evidence + tc.Pad, {struct("content", "Unemployment was 9.9%.")});
            tc.verifyEqual(strip(r.text), evidence);
            tc.verifySubstring(fileread(tc.ctx.tracePath), '"fallback":true');
        end

        function aNumberThatOnlyAppearsInsideAnotherNumberFallsBack(tc)
            evidence = "UNRATE: 3.5% on 2020-02-07, up from 15% in 2020-04";
            r = tc.specialist("market", evidence + tc.Pad, {struct("content", "Unemployment was 5%.")});
            tc.verifyEqual(strip(r.text), evidence);
        end

        function aReplyWithAnUnknownParagraphIdFallsBack(tc)
            evidence = "Rates held [2020-01-29/policyAction/1].";
            r = tc.specialist("minutes", evidence, {struct("content", "Rates held [2020-01-29/policyAction/9].")});
            tc.verifyEqual(r.text, evidence);
        end

        function aFailingModelFallsBackInsteadOfThrowing(tc)
            tc.ctx.agent = "minutes";
            brief = struct("question", "Q?", "isAnalysis", false, "llmFor", @(~, ~, ~) @(~, ~, ~) error("model is down"));
            r = fomc.agents.subAgent(tc.ctx, brief, "minutes", "Rates held [2020-01-29/policyAction/1].", []);
            tc.verifyEqual(r.text, "Rates held [2020-01-29/policyAction/1].");
            tc.verifySubstring(fileread(tc.ctx.tracePath), '"reason":"model"');
        end

        function noEvidenceNoFactoryOrAnAnalysisTurnMeansNoModelCall(tc)
            [r1, seen] = tc.specialist("market", "", {struct("content", "x")});
            tc.verifyEqual(r1.text, "");
            brief = struct("question", "Q?", "isAnalysis", false);
            tc.verifyEqual(fomc.agents.subAgent(tc.ctx, brief, "market", "E", []).text, "E");
            [r2, seen2] = tc.specialist("market", "E", {struct("content", "x")}, true);
            tc.verifyEqual(r2.text, "E");
            tc.verifyEqual([seen.calls seen2.calls], [0 0]);
        end

        function aSpecialistMayCallItsOwnToolsButNotAnotherAgents(tc)
            own = struct("content", "", "tool_calls", struct("name", "listMeetings", "arguments", struct()));
            other = struct("content", "", "tool_calls", struct("name", "getSeries", "arguments", struct("seriesIds", "UNRATE")));
            r = tc.specialist("minutes", "Rates held [2020-01-29/policyAction/1].", {own, other, struct("content", "Rates held [2020-01-29/policyAction/1].")});
            tc.verifyEqual([r.calls.name], ["listMeetings" "getSeries"]);
            tc.verifyEqual([r.calls.ok], [true false], "getSeries is not a minutes tool");
        end

        function aMarketSpecialistIsNotNudgedToReadMinutes(tc)
            [~, seen] = tc.specialist("market", "UNRATE: 3.5% on 2020-02-07" + tc.Pad, {struct("content", "Unemployment was 3.5%.")}, false, ...
                "What did the minutes say about unemployment?");
            tc.verifyEqual(seen.calls, 1);
        end

        function aQuestionBeforeAnyMinutesWereReleasedGetsAPlainNotice(tc)
            % Anchor before the first release: there is no "latest released meeting" to name
            ctx = fomc.context(datetime(2000,1,1), fomc.config(verbose=false), tc.D, tracePath=string(tempname) + ".jsonl");
            brief = struct("question", "What did the Committee decide at its January 2020 meeting?", "isAnalysis", false, "followsRatePath", false);
            r = fomc.agents.minutesRetriever(ctx, brief);
            tc.verifySubstring(r.text, "No minutes have been released yet.");
            tc.verifyTrue(r.ok);
        end

        function evidenceShorterThanTheLimitGoesToTheWriterUnchanged(tc)
            tc.ctx.cfg.agentSummarizeOver = 100;
            id = "Rates held [2020-01-29/policyAction/1].";
            [short, s1] = tc.specialist("minutes", id, {struct("content", "x")});
            [long, s2] = tc.specialist("minutes", id + " " + strjoin(repmat("More.", 1, 30)), {struct("content", id)});
            tc.verifyEqual(short.text, id);
            tc.verifyEqual([s1.calls s2.calls], [0 1]);
            tc.verifyEqual(long.text, id);
        end

        function aSummaryThatDropsEveryParagraphIdFallsBack(tc)
            evidence = "Rates held [2020-01-29/policyAction/1]. Inflation was elevated [2020-01-29/inflation/2].";
            kept = tc.specialist("minutes", evidence, {struct("content", "Rates held [2020-01-29/policyAction/1].")});
            dropped = tc.specialist("minutes", evidence, {struct("content", "Rates held and inflation was elevated.")});
            tc.verifyEqual(kept.text, "Rates held [2020-01-29/policyAction/1].");
            tc.verifyEqual(dropped.text, evidence);
            tc.verifySubstring(fileread(tc.ctx.tracePath), '"reason":"no paragraph id kept"');
        end

        function aMarketReportBelowItsOwnLimitReachesTheWriterAsWritten(tc)
            % agents/market.md sets summarizeOver: the code's text already carries the writer's instructions
            evidence = "[Outlook, cite the staff forecast with its ids [2020-01-29/staffOutlook/1]." + strjoin(repmat("Figure.", 1, 200)) + "]";
            [r, seen] = tc.specialist("market", evidence, {struct("content", "Short.")});
            tc.verifyEqual(r.text, evidence);
            tc.verifyEqual(seen.calls, 0);
        end

        function aSpecialistPromptIsItsRoleAndTheTopicPageItWasGiven(tc)
            c = fomc.agents.catalog();
            a = c([c.name] == "minutes");
            tc.verifyEqual(sort(string(fieldnames(a.pages))).', ["decision" "passages" "views"]);
            id = "Rates held [2020-01-29/policyAction/1].";
            [~, withPage] = tc.specialist("minutes", id, {struct("content", id)}, false, "Q?", "views");
            [~, noPage] = tc.specialist("minutes", id, {struct("content", id)}, false, "Q?", "no such page");
            rules = string(newline) + newline + fomc.asOfRules();      % every specialist's prompt ends with the point-in-time rules
            tc.verifyEqual(withPage.prompt, a.body + newline + a.pages.views + rules);
            tc.verifyEqual(noPage.prompt, a.body + rules);
        end

        function aNextMoveQuestionGetsTheParticipantsViewsNotTheDecisionCard(tc)
            r = fomc.agents.minutesRetriever(tc.ctxWithViews(), tc.brief("Should the Fed raise rates at the next meeting?"));
            tc.verifySubstring(r.text, "[2020-01-29/participantsViews/9]");
            tc.verifySubstring(r.text, "hold");
            tc.verifyFalse(contains(r.text, "Decision card"));
            tc.verifyEqual(r.meetingDate, "2020-01-29");
        end

        function aRateTargetQuestionThatNamesAMeetingGetsItsDecisionCard(tc)
            r = fomc.agents.minutesRetriever(tc.ctx, tc.brief("In January 2020, what happened to the federal funds rate target?"));
            tc.verifySubstring(r.text, "Decision card for the meeting that ended 2020-01-29");
            q = fomc.agents.minutesRetriever(tc.ctx, tc.brief("What was the federal funds rate in 2019?"));
            tc.verifyEqual(q.text, "", "a data question that names no meeting gets no minutes");
        end

        function theConsumerReportHoldsTheDirectionAndTheToolNoteButNotTheMarketFiguresAgain(tc)
            brief = tc.brief("What do the latest minutes mean for my mortgage?");
            brief.reports = struct("scorer", fomc.agents.report("scorer", meetingDate="2020-01-29", direction="hold"), ...
                "market", fomc.agents.report("market", text="UNRATE: 3.5% on 2020-02-07"));
            r = fomc.agents.consumerView(tc.ctx, brief);
            tc.verifySubstring(r.text, "hold");
            tc.verifySubstring(r.text, "not implemented");
            tc.verifyFalse(contains(r.text, "UNRATE"), "the writer already reads the market report");
        end

        function theWriterReadsTheSpecialistsReportsAndEachCallIsLabelled(tc)
            reply = fomc.llm.Mock({struct("content", "Short report [2020-01-29/policyAction/1].")});
            factory = @(~, ~, ~) @(h, t, f) reply.call(h, t, f);
            writer = fomc.llm.Mock({struct("content", "Ok.")});
            tp = string(tempname) + ".jsonl";
            [~, ~, ~, s] = fomc.runAgent("What did the Committee decide at the latest meeting?", ...
                datetime(2020,3,1), Config=fomc.config(verbose=false, agentSummarizeOver=0), Llm=@writer.call, Data=tc.D, TracePath=tp, AgentLlm=factory);
            tc.verifyGreaterThanOrEqual(numel(reply.Seen), 1);
            tc.verifySubstring(string(s.history.Messages{1}.content), "Short report [2020-01-29/policyAction/1].");
            tc.verifySubstring(fileread(tp), '"type":"agent_model"');
        end
    end

    methods
        function b = brief(~, question)
            b = struct("question", question, "isAnalysis", false, "followsRatePath", false);
        end

        function ctx = ctxWithViews(tc)
            % Meeting 1 (released by the anchor) gets one sentence about future rate moves, as policyViews reads them
            D = tc.D;
            D.paras(end+1, :) = {1, "participantsViews", 9, "Several participants judged that it would likely be appropriate to hold the " + ...
                "target range for the federal funds rate steady at coming meetings.", "2020-01-29/participantsViews/9"};
            ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), D, tracePath=string(tempname) + ".jsonl");
        end

        function [r, seen] = specialist(tc, name, evidence, script, isAnalysis, question, topic)
            % Run one specialist on some evidence with a scripted model; seen: its prompt, tools and call count
            if nargin < 5, isAnalysis = false; end
            if nargin < 6, question = "Q?"; end
            if nargin < 7, topic = ""; end
            c = fomc.agents.catalog();
            a = c([c.name] == name);
            tc.ctx.agent = name;
            tc.ctx.allowedTools = a.tools;
            log = containers.Map({'prompt', 'tools', 'calls'}, {"", strings(1, 0), 0});
            m = fomc.llm.Mock(script);
            factory = @(~, prompt, tools) recorded(log, m, prompt, tools);
            brief = struct("question", question, "isAnalysis", isAnalysis, "llmFor", factory);
            r = fomc.agents.subAgent(tc.ctx, brief, name, evidence, [], topic);
            seen = struct("prompt", log('prompt'), "tools", log('tools'), "calls", log('calls'));
        end
    end
end

function f = recorded(log, m, prompt, tools)
% A model factory like the real one (cfg, prompt, tools in; model function out) that notes what it was given
log('prompt') = prompt;
log('tools') = tools;
f = @(h, t, fm) counted(log, m, h, t, fm);
end

function [text, out, stats] = counted(log, m, h, t, fm)
log('calls') = log('calls') + 1;
[text, out, stats] = m.call(h, t, fm);
end
