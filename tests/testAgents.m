classdef testAgents < matlab.unittest.TestCase
    % The multi-agent organizer: contract, routing, stages, trace. SYNTHETIC data, anchor 2020-03-01.
    % A scripted fake model (fomc.llm.Mock) stands in for Ollama, so nothing here costs anything.

    properties
        D
        cfg
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
            tc.cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
        end
    end

    methods (Test)
        % ---- contract ----
        function defaultsAreSet(tc)
            c = fomc.config();
            tc.verifyEqual([string(c.parallel), string(c.criticRounds)], ["false" "2"]);
        end

        function aReportHasEveryContractField(tc)
            r = fomc.agents.report("market", text="x", ids=["a"; "b"]);
            tc.verifyEqual(sort(string(fieldnames(r)).'), sort(["agent" "ok" "text" "ids" "calls" ...
                "meetingDate" "direction" "structured" "error" "ms"]));
            tc.verifyTrue(r.ok);
            tc.verifyEqual(r.agent, "market");
        end

        function everyToolEventCarriesTheAgentLabel(tc)
            tc.ctx.agent = "minutes";
            fomc.tools.dispatch(tc.ctx, "listMeetings", struct());
            lines = readlines(tc.ctx.tracePath);
            ev = jsondecode(lines(1));
            tc.verifyEqual(string(ev.agent), "minutes");
        end

        function noAgentLabelOutsideAnAgent(tc)
            fomc.tools.dispatch(tc.ctx, "listMeetings", struct());
            lines = readlines(tc.ctx.tracePath);
            tc.verifyFalse(isfield(jsondecode(lines(1)), "agent"));
        end

        function aToolOutsideTheWhitelistIsRefusedAndLogged(tc)
            tc.ctx.agent = "minutes";
            tc.ctx.allowedTools = ["getDecision" "searchMinutes"];
            [json, rec] = fomc.tools.dispatch(tc.ctx, "getSeries", struct("seriesIds", "UNRATE"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(string(jsondecode(json).error), "not allowed for the minutes agent");
            lines = readlines(tc.ctx.tracePath);
            block = jsondecode(lines(1));
            tc.verifyEqual([string(block.type) string(block.stage)], ["guardrail_block" "agent_tools"]);
        end

        function aToolInsideTheWhitelistRuns(tc)
            tc.ctx.agent = "minutes";
            tc.ctx.allowedTools = "listMeetings";
            [~, rec] = fomc.tools.dispatch(tc.ctx, "listMeetings", struct());
            tc.verifyTrue(rec.ok);
        end

        % ---- agent files ----
        function everyAgentFileParsesWithRealTools(tc)
            c = fomc.agents.catalog();
            tc.verifyEqual(sort([c.name]), ["consumer" "market" "minutes" "organizer" "scorer"]);
            known = [string({fomc.tools.registry().name}) "readSkill"];
            for a = c(~strcmp([c.name], "organizer"))
                tc.verifyTrue(all(ismember(a.tools, known)), a.name + " names a tool that does not exist");
                tc.verifyNotEmpty(a.fn, a.name + " has no function");
            end
        end

        function theStagesLineNamesKnownAgentsOnce(tc)
            c = fomc.agents.catalog();
            names = strip(split(replace(c([c.name] == "organizer").stages, ">", "+"), "+")).';
            tc.verifyEqual(sort(names), ["consumer" "market" "minutes" "scorer"]);
        end

        % ---- routes ----
        function questionsRouteToTheRightStages(tc)
            cases = ["What did the latest Fed minutes say about inflation?" "other" "minutes+market"
                "What do the latest Fed minutes mean for my mortgage?" "household" "minutes+market > scorer > consumer"
                "Score the March 2020 meeting" "score" "scorer"];
            for i = 1:size(cases, 1)
                [st, name] = fomc.agents.route(cases(i, 1));
                tc.verifyEqual(name, cases(i, 2));
                tc.verifyEqual(join(cellfun(@(x) join([x.name], "+"), st), " > "), cases(i, 3));
            end
        end

        % ---- running agents ----
        function aFailingAgentIsAReportNotAnError(tc)
            bad = struct("name", "minutes", "tools", "listMeetings", "fn", @throwBoom);
            r = fomc.agents.runOne(bad, 1, tc.ctx, struct());
            tc.verifyFalse(r.ok);
            tc.verifySubstring(r.error, "boom");
            ev = traceEvents(tc.ctx.tracePath);
            tc.verifyEqual(typesOf(ev), ["handoff" "handback"]);
            tc.verifyFalse(ev{2}.ok);
        end

        function eachStageGetsTheEarlierReports(tc)
            q = "What do the latest Fed minutes mean for my mortgage?";
            brief = struct("question", q, "isAnalysis", false, "route", "household", ...
                "followsRatePath", false, "reports", struct(), "session", []);
            [st, ~] = fomc.agents.route(q);
            for k = 1:numel(st)
                for r = fomc.agents.runStage(tc.ctx, st{k}, k, brief)
                    brief.reports.(r.agent) = r;
                end
            end
            tc.verifyEqual(string(fieldnames(brief.reports)).', ["minutes" "market" "scorer" "consumer"]);
            tc.verifyTrue(brief.reports.scorer.ok);
            tc.verifyNotEmpty(brief.reports.scorer.direction);
            tc.verifyEqual(brief.reports.consumer.meetingDate, "");
        end

        function aParallelStageGivesTheSameReportsAndAnOrderedTrace(tc)
            tc.assumeTrue(license("test", "Distrib_Computing_Toolbox") == 1, "needs Parallel Computing Toolbox");
            q = "What did the minutes say about unemployment and what is the rate now?";
            brief = struct("question", q, "isAnalysis", false, "route", "other", ...
                "followsRatePath", false, "reports", struct(), "session", []);
            st = fomc.agents.route(q);
            out = cell(1, 2);
            for j = 1:2
                cfg = fomc.config(verbose=false, parallel=(j == 2));
                ctx = fomc.context(datetime(2020,3,1), cfg, tc.D, tracePath=string(tempname) + ".jsonl");
                out{j} = fomc.agents.runStage(ctx, st{1}, 1, brief);
                ev = traceEvents(ctx.tracePath);
                % each agent's handoff and handback stay together, in the stage's order
                types = typesOf(ev);
                tc.verifyEqual(types(ismember(types, ["handoff" "handback"])), ["handoff" "handback" "handoff" "handback"]);
            end
            for f = ["agent" "ok" "text" "ids" "meetingDate" "direction"]
                tc.verifyEqual({out{2}.(f)}, {out{1}.(f)}, f);
            end
        end

        % ---- the writer sees the same lookups as the harness makes ----
        function theOrganizerSendsTheWriterTheSameLookupsAsTheHarnessDoes(tc)
            for q = ["What did the Fed decide at the latest meeting?" "What is the unemployment rate?" ...
                    "What did the minutes say about unemployment and what is the rate now?"]
                first = strings(1, 2);
                for j = 1:2
                    m = fomc.llm.Mock({struct("content", "Ok.")});
                    s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
                    if j == 1
                        s = fomc.runTurn(s, q);          % lookups made inside the loop (fomc.focus.prefetch)
                    else
                        s = fomc.agents.run(s, q);       % lookups made by the specialist agents
                    end
                    first(j) = string(s.history.Messages{1}.content);
                end
                % the organizer ends the lookups with one line on citing; the harness path has none
                tc.verifyEqual(regexprep(first(2), "\n\[Answer in full sentences[^\n]*\]$", ""), first(1), q);
            end
        end

        function theLookupsEndWithAReminderToWriteSentencesWithIdsWhenTheReportsHoldIds(tc)
            m = fomc.llm.Mock({struct("content", "Ok.")});
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
            s = fomc.agents.run(s, "What did the Fed decide at the latest meeting?");
            tc.verifySubstring(string(s.history.Messages{1}.content), "[Answer in full sentences. After each fact, put the id of the paragraph it comes from in square brackets.]");
            s = fomc.newSession(datetime(2020,3,1), tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
            s = fomc.agents.run(s, "What is the unemployment rate?");
            tc.verifyFalse(contains(string(s.history.Messages{1}.content), "Answer in full sentences"), "nothing to cite");
        end

        % ---- trace ----
        function aHouseholdTurnTracesRouteStagesHandoffsThenTheWriter(tc)
            m = fomc.llm.Mock({struct("content", "Ok.")});
            fomc.runAgent("What do the latest Fed minutes mean for my mortgage?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=tc.ctx.tracePath);
            ev = traceEvents(tc.ctx.tracePath);
            types = typesOf(ev);
            order = types(ismember(types, ["route" "stage" "handoff" "handback" "final_answer"]));
            tc.verifyEqual(order(1:3), ["route" "stage" "handoff"]);
            tc.verifyEqual(order(end), "final_answer");
            handoffs = cellfun(@(e) string(e.to), ev(types == "handoff")).';
            tc.verifyEqual(handoffs, ["minutes" "market" "scorer" "consumer"]);
            tc.verifyEqual(sum(types == "handoff"), sum(types == "handback"));
            tools = ev(types == "tool_call" & cellfun(@(e) isfield(e, "agent"), ev).');
            tc.verifyTrue(all(cellfun(@(e) ismember(string(e.agent), ["minutes" "market" "consumer"]), tools)));
        end

        function theHouseholdRouteKeepsTheFirstMessageWithinTheBudget(tc)
            % The first-turn prompt budget is 5,000 tokens (testBudgets: 2,375 for the system prompt and tools)
            m = fomc.llm.Mock({struct("content", "Ok.")});
            [~, ~, ~, s] = fomc.runAgent("What do the latest Fed minutes mean for my mortgage?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname) + ".jsonl");
            tokens = strlength(string(s.history.Messages{1}.content)) / 3.3;
            tc.verifyLessThanOrEqual(tokens, 5000 - 2375);
        end
    end
end

function r = throwBoom(~, ~)
r = [];
error("boom");
end

function t = typesOf(ev)
t = cellfun(@(e) string(e.type), ev).';
end
