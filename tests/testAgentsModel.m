classdef testAgentsModel < matlab.unittest.TestCase
    % Each specialist is a sub-agent: its own prompt and tools, a short model loop on what its code found.
    % Scripted models stand in for Ollama. SYNTHETIC data, anchor 2020-03-01.

    properties
        D
        ctx
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
            tc.ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), tc.D, tracePath=string(tempname) + ".jsonl");
        end
    end

    methods (Test)
        function aSpecialistRunsOnItsOwnPromptAndToolsAndReportsTheModelsText(tc)
            [r, seen] = tc.specialist("market", "UNRATE: 3.5% on 2020-02-07", {struct("content", "Unemployment was 3.5% (UNRATE).")});
            tc.verifyEqual(r.text, "Unemployment was 3.5% (UNRATE).");
            c = fomc.agents.catalog();
            a = c([c.name] == "market");
            tc.verifyEqual(seen.prompt, a.body);
            tc.verifyEqual(seen.tools, a.tools);
            tc.verifyEqual(seen.calls, 1);
        end

        function aReplyWithANumberNoSourceHasFallsBackToTheCodesText(tc)
            evidence = "UNRATE: 3.5% on 2020-02-07";
            r = tc.specialist("market", evidence, {struct("content", "Unemployment was 9.9%.")});
            tc.verifyEqual(r.text, evidence);
            tc.verifySubstring(fileread(tc.ctx.tracePath), '"fallback":true');
        end

        function aReplyWithAnUnknownParagraphIdFallsBack(tc)
            evidence = "Rates held [2020-01-29/policyAction/1].";
            r = tc.specialist("minutes", evidence, {struct("content", "Rates held [2020-01-29/policyAction/9].")});
            tc.verifyEqual(r.text, evidence);
        end

        function aFailingModelFallsBackInsteadOfThrowing(tc)
            tc.ctx.agent = "market";
            brief = struct("question", "Q?", "isAnalysis", false, "llmFor", @(~, ~, ~) @(~, ~, ~) error("model is down"));
            r = fomc.agents.subAgent(tc.ctx, brief, "market", "UNRATE: 3.5%", []);
            tc.verifyEqual(r.text, "UNRATE: 3.5%");
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
            [~, seen] = tc.specialist("market", "UNRATE: 3.5% on 2020-02-07", {struct("content", "Unemployment was 3.5%.")}, false, ...
                "What did the minutes say about unemployment?");
            tc.verifyEqual(seen.calls, 1);
        end

        function theWriterReadsTheSpecialistsReportsAndEachCallIsLabelled(tc)
            reply = fomc.llm.Mock({struct("content", "Short report.")});
            factory = @(~, ~, ~) @(h, t, f) reply.call(h, t, f);
            writer = fomc.llm.Mock({struct("content", "Ok.")});
            tp = string(tempname) + ".jsonl";
            [~, ~, ~, s] = fomc.runAgent("What is the unemployment rate and what did the minutes say about it?", ...
                datetime(2020,3,1), Config=fomc.config(verbose=false), Llm=@writer.call, Data=tc.D, TracePath=tp, AgentLlm=factory);
            tc.verifyGreaterThanOrEqual(numel(reply.Seen), 1);
            tc.verifySubstring(string(s.history.Messages{1}.content), "Short report.");
            tc.verifySubstring(fileread(tp), '"type":"agent_model"');
        end
    end

    methods
        function [r, seen] = specialist(tc, name, evidence, script, isAnalysis, question)
            % Run one specialist on some evidence with a scripted model; seen: its prompt, tools and call count
            if nargin < 5, isAnalysis = false; end
            if nargin < 6, question = "Q?"; end
            c = fomc.agents.catalog();
            a = c([c.name] == name);
            tc.ctx.agent = name;
            tc.ctx.allowedTools = a.tools;
            log = containers.Map({'prompt', 'tools', 'calls'}, {"", strings(1, 0), 0});
            m = fomc.llm.Mock(script);
            factory = @(~, prompt, tools) recorded(log, m, prompt, tools);
            brief = struct("question", question, "isAnalysis", isAnalysis, "llmFor", factory);
            r = fomc.agents.subAgent(tc.ctx, brief, name, evidence, []);
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
