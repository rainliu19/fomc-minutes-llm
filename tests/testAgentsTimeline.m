classdef testAgentsTimeline < matlab.unittest.TestCase
    % What the page's agent timeline is drawn from: which agent each trace event belongs to, what each model
    % call was sent and what it answered. Scripted model, SYNTHETIC data, anchor 2020-03-01.

    properties
        D
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = syntheticData();
        end
    end

    methods (Test)
        function everyAgentsEventsCarryItsOwnName(tc)
            [ev, ~] = tc.household();
            tc.verifyEqual(agentsOf(ev, "route"), "organizer");
            tc.verifyEqual(agentsOf(ev, "handback"), ["minutes" "market" "scorer" "consumer"]);
            tc.verifyEqual(unique(agentsOf(ev, "model_response")), "writer");
            tc.verifyEqual(unique(agentsOf(ev, "user_message")), "writer");
        end

        function theRouteEventCarriesTheQuestion(tc)
            [ev, q] = tc.household();
            r = ev(typesOf(ev) == "route");
            tc.verifyEqual(string(r{1}.question), q);
        end

        function everyModelCallIsOneModelResponse(tc)
            % the writer's rounds and the critic's rewrite alike, so token counts add up
            [ev, ~, m] = tc.household();
            tc.verifyEqual(nnz(typesOf(ev) == "model_response"), m.Index);
        end

        function aSkippedSpecialistModelSaysWhy(tc)
            [ev, ~] = tc.household("What is the unemployment rate?");
            k = find(typesOf(ev) == "agent_model" & agentsOf(ev) == "market");
            tc.verifyNotEmpty(k);
            tc.verifyTrue(ev{k(1)}.skipped);
            tc.verifySubstring(string(ev{k(1)}.reason), "under");
        end

        function aHandbackCarriesTheReportAndAHandoffNamesWhatTheAgentReads(tc)
            [ev, ~] = tc.household();
            back = ev(typesOf(ev) == "handback");
            tc.verifyTrue(all(cellfun(@(e) isfield(e, "text"), back)));
            tc.verifyNotEmpty(string(back{end}.text));
            hand = ev(typesOf(ev) == "handoff");
            tc.verifyEqual(string(hand{end}.to), "consumer");
            tc.verifyEqual(string(hand{end}.reads(:)).', ["minutes" "market" "scorer"]);
            tc.verifyEmpty(hand{1}.reads);
        end

        function theWritersQuestionSaysWhoseReportsItCarries(tc)
            [ev, ~] = tc.household();
            msgs = ev(typesOf(ev) == "message" & agentsOf(ev) == "writer");
            from = cellfun(@(e) string(e.from(:)).', msgs(cellfun(@(e) isfield(e, "from") && ~isempty(e.from), msgs)), UniformOutput=false);   % only the reports with something to say
            tc.verifyNotEmpty(from);
            tc.verifyEqual(from{1}, ["scorer" "consumer"], "minutes and market had nothing to report");
        end

        function aFreshContextLogsItsSystemPromptAndOnlyOnce(tc)
            [ev, ~] = tc.household();
            sys = ev(isRole(ev, "system"));
            tc.verifyEqual(numel(sys), 1);
            tc.verifyEqual(string(sys{1}.agent), "writer");
            tc.verifyNotEmpty(string(sys{1}.text));
        end

        function aSecondTurnLogsOnlyWhatIsNewAndNotesTheEarlierMessages(tc)
            tp = string(tempname) + ".jsonl";
            m = fomc.llm.Mock({struct("content", "Fine.")});
            [~, ~, ~, s] = fomc.runAgent("Hello there.", datetime(2020,3,1), Config=fomc.config(verbose=false), ...
                Llm=@m.call, Data=tc.D, TracePath=tp);
            before = numel(traceEvents(tp));
            fomc.agents.run(s, "And now?");
            ev = traceEvents(tp);
            ev = ev(before+1:end);
            tc.verifyEmpty(ev(isRole(ev, "system")));
            notes = ev(isRole(ev, "note"));
            tc.verifySubstring(string(notes{1}.text), "earlier messages");
        end

        function aCriticRewriteShowsTheRequestFromTheCriticAndTheReply(tc)
            tp = string(tempname) + ".jsonl";
            m = fomc.llm.Mock({struct("content", "The range is 1-1/2 to 1-3/4 percent."), struct("content", "The Committee held the rate.")});
            fomc.runAgent("Hello there.", datetime(2020,3,1), Config=fomc.config(verbose=false), Llm=@m.call, Data=tc.D, TracePath=tp);
            ev = traceEvents(tp);
            req = ev(typesOf(ev) == "message" & cellfun(@(e) isfield(e, "from") && any(string(e.from) == "critic"), ev(:)).');
            tc.verifyEqual(numel(req), 1);
            tc.verifyEqual(string(req{1}.agent), "writer");
            tc.verifyEqual(string(req{1}.role), "user");
            tc.verifyEqual(nnz(typesOf(ev) == "model_response"), 2);
            critics = ev(typesOf(ev) == "critic");
            tc.verifyEqual(string(critics{1}.agent), "critic");
        end

        function aLongMessageIsCappedInTheLog(tc)
            tp = string(tempname) + ".jsonl";
            ctx = fomc.context(datetime(2020,3,1), fomc.config(verbose=false), tc.D, tracePath=tp);
            m = fomc.llm.Mock({struct("content", "ok")});
            s = struct("ctx", ctx, "llm", @m.call, "systemPrompt", "sys");
            h = addUserMessage(messageHistory, string(repmat('x', 1, 50000)));
            fomc.trace.llmCall(s, h, false, []);
            ev = traceEvents(tp);
            long = ev(cellfun(@(e) isfield(e, "text") && contains(string(e.text), "xxxx"), ev));
            tc.verifyLessThanOrEqual(strlength(string(long{1}.text)), 20003);
        end

        function oneAgentModeIsOneColumnWithNoOrganizerOrCritic(tc)
            tp = string(tempname) + ".jsonl";
            m = fomc.llm.Mock({struct("content", "The range is 1-1/2 to 1-3/4 percent.")});
            s = fomc.newSession(datetime(2020,3,1), fomc.config(verbose=false), Llm=@m.call, Data=tc.D, TracePath=tp);
            s = fomc.agents.run(s, "What do the latest Fed minutes mean for my mortgage?", Team=false);
            ev = traceEvents(tp);
            who = unique(agentsOf(ev));
            tc.verifyEqual(who(who ~= ""), "agent");
            tc.verifyEmpty(ev(ismember(typesOf(ev), ["route" "handoff" "handback" "critic"])));
            tc.verifyEqual(s.lastAgentIssues, "");
            tc.verifyEqual(m.Index, 2, "the writer and its one nudge, and no critic rewrite");
        end
    end

    methods
        function [ev, q, m] = household(tc, q)
            if nargin < 2
                q = "What do the latest Fed minutes mean for my mortgage?";
            end
            tp = string(tempname) + ".jsonl";
            m = fomc.llm.Mock({struct("content", "Rates look steady for mortgages.")});
            fomc.runAgent(q, datetime(2020,3,1), Config=fomc.config(verbose=false), Llm=@m.call, Data=tc.D, TracePath=tp);
            ev = traceEvents(tp);
        end
    end
end

function tf = isRole(ev, role)
% Which message events have this role
tf = cellfun(@(e) string(e.type) == "message" && string(e.role) == role, ev(:)).';
end

function t = typesOf(ev)
t = cellfun(@(e) string(e.type), ev(:)).';
end

function a = agentsOf(ev, type)
% The agent of each event ("" when it has none), only of this type when one is given
a = cellfun(@(e) ifelse(isfield(e, "agent"), @() string(e.agent), @() ""), ev(:)).';
if nargin > 1
    a = a(typesOf(ev) == type);
end
end

function v = ifelse(c, a, b)
if c, v = a(); else, v = b(); end
end
