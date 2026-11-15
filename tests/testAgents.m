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
            tc.cfg = fomc.config(verbose=false, agents="multi");
            tc.ctx = fomc.context(datetime(2020,3,1), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
        end
    end

    methods (Test)
        % ---- contract ----
        function singleModeIsTheDefault(tc)
            c = fomc.config();
            tc.verifyEqual([c.agents, string(c.parallel), string(c.criticRounds)], ["single" "false" "2"]);
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
            ev = eventsOf(tc.ctx.tracePath);
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

        % ---- the writer sees the same lookups as in single mode ----
        function minutesAndNumbersQuestionsGiveTheSameFirstMessageAsSingleMode(tc)
            for q = ["What did the Fed decide at the latest meeting?" "What is the unemployment rate?" ...
                    "What did the minutes say about unemployment and what is the rate now?"]
                first = strings(1, 2);
                modes = ["single" "multi"];
                for j = 1:2
                    m = fomc.llm.Mock({struct("content", "Ok.")});
                    cfg = fomc.config(verbose=false, agents=modes(j));
                    [~, ~, ~, s] = fomc.runAgent(q, datetime(2020,3,1), Config=cfg, Llm=@m.call, Data=tc.D, ...
                        TracePath=string(tempname) + ".jsonl");
                    first(j) = string(s.history.Messages{1}.content);
                end
                tc.verifyEqual(first(2), first(1), q);
            end
        end

        % ---- trace ----
        function aHouseholdTurnTracesRouteStagesHandoffsThenTheWriter(tc)
            m = fomc.llm.Mock({struct("content", "Ok.")});
            fomc.runAgent("What do the latest Fed minutes mean for my mortgage?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=tc.ctx.tracePath);
            ev = eventsOf(tc.ctx.tracePath);
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

        function singleModeEmitsNoAgentEvents(tc)
            cfg = fomc.config(verbose=false);
            m = fomc.llm.Mock({struct("content", "Ok.")});
            fomc.runAgent("What did the Fed decide?", datetime(2020,3,1), Config=cfg, Llm=@m.call, Data=tc.D, ...
                TracePath=tc.ctx.tracePath);
            types = typesOf(eventsOf(tc.ctx.tracePath));
            tc.verifyFalse(any(ismember(types, ["route" "stage" "handoff" "handback" "critic"])));
        end
    end
end

function r = throwBoom(~, ~)
r = [];
error("boom");
end

function ev = eventsOf(path)
% The trace file as a cell array of events (structs)
lines = readlines(path);
ev = arrayfun(@jsondecode, lines(strlength(lines) > 0), UniformOutput=false);
end

function t = typesOf(ev)
t = cellfun(@(e) string(e.type), ev).';
end
