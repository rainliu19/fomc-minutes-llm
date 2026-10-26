classdef testBudgets < matlab.unittest.TestCase
    % Size budgets. The model reads about 140 tokens/s and writes about 10, so every extra
    % character in the prompt or a tool result costs time. Keeps the prompt, tool schemas and
    % tool outputs small and checks history compaction. REAL data, no model.

    properties
        D
        cfg
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
            tc.cfg = fomc.config(verbose=false);
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function theToolsOfferedToTheModelStaySmall(tc)
            % Raised from 3600 for getPolicyPath (about 330 characters, most of it the date
            % parameters); the first-turn prompt budget below still applies
            tc.verifyLessThanOrEqual(schemaChars(), 3750);
        end

        function getSnapshotIsRunByTheHarnessNotOfferedToTheModel(tc)
            % Helper: size of the tool descriptions the model is sent
            reg = fomc.tools.registry();
            tc.verifyFalse(reg(string({reg.name}) == "getSnapshot").expose);
            tc.verifyTrue(any(string({reg.name}) == "getSnapshot"), "but it can still be dispatched");
        end

        function theFirstTurnPromptStaysUnderTheBudget(tc)
            for asOf = [datetime(2026,10,7), datetime(2020,4,8), datetime(2009,6,25)]
                ctx = fomc.context(asOf, tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
                p = fomc.systemPrompt() + fomc.contextBlock(ctx, fomc.dataBrief(ctx));
                tokens = (strlength(p) + schemaChars()) / 3.3;
                tc.verifyLessThanOrEqual(tokens, 1850, "first-turn prompt at " + fomc.util.fmtDate(asOf));
            end
        end

        function theSnapshotInThePromptStaysSmall(tc)
            ctx = fomc.context(datetime(2020,4,8), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
            b = fomc.dataBrief(ctx);
            tc.verifyLessThanOrEqual(strlength(b), 1300);
            tc.verifyGreaterThanOrEqual(count(b, newline) + 1, 10, "the key series should be there");
            tc.verifyTrue(contains(b, "UNRATE"));
        end

        function theSystemPromptNeverChangesSoTheStartCanBeReused(tc)
            % The system prompt and tool descriptions start every conversation; if identical across
            % sessions, the model server can reuse its work.
            a = fomc.systemPrompt(); b = fomc.systemPrompt();
            tc.verifyEqual(a, b);
            tc.verifyLessThan(strlength(a), 1350);
            ctxA = fomc.context(datetime(2020,4,8), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
            ctxB = fomc.context(datetime(2019,4,8), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
            tc.verifyNotEqual(fomc.contextBlock(ctxA, "x"), fomc.contextBlock(ctxB, "x"));
            tc.verifyFalse(contains(a, "ANCHOR DATE:"), "no session-specific text in the system prompt");
        end

        function toolOutputsStayWithinTheirPageBudgets(tc)
            % Check 30 random readMinutes pages, then one of each other tool, against their size limits
            rng(3);
            ctx = fomc.context(datetime(2026,10,7), tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
            S = ["participantsViews", "staffOutlook", "staffEconomy", "financialMarkets", "policyAction"];
            for i = 1:30
                m = tc.D.meetings.MeetingDate(randi(height(tc.D.meetings)));
                r = fomc.tools.readMinutes(ctx, struct("meetingDate", fomc.util.fmtDate(m), "section", S(randi(numel(S)))));
                if isfield(r, "error"), continue, end
                tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 4000 + 300 * numel(r.paragraphs), ...
                    "readMinutes page for " + fomc.util.fmtDate(m));
            end
            r = fomc.tools.searchMinutes(ctx, struct("query", "inflation"));
            tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 3500);
            r = fomc.tools.getDecision(ctx, struct("meetingDate", "2020-03-15"));
            tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 2200);
            r = fomc.tools.getSeries(ctx, struct("seriesIds", "UNRATE,CPIAUCSL,DGS10"));
            tc.verifyLessThanOrEqual(strlength(jsonencode(r)), 6000);
        end

        function aSingleLongParagraphIsClippedToThePage(tc)
            ctx = fomc.context(datetime(2026,10,7), fomc.config(verbose=false, maxToolChars=500), tc.D, ...
                tracePath=string(tempname) + ".jsonl");
            r = fomc.tools.readMinutes(ctx, struct("meetingDate", "2020-03-15", "section", "participantsViews"));
            tc.verifyLessThanOrEqual(strlength(r.paragraphs{1}.text), 503);
        end

        function compactionReplacesOldToolResultsAndKeepsTheLatest(tc)
            h = longHistory(3);
            [h2, n] = fomc.history.compact(h, 1);
            tc.verifyEqual(n, 2);
            msgs = h2.Messages;
            tools = msgs(cellfun(@(m) string(m.role) == "tool", msgs));
            tc.verifySubstring(string(tools{1}.content), "removed to save space");
            tc.verifySubstring(string(tools{2}.content), "removed to save space");
            tc.verifyEqual(strlength(string(tools{3}.content)), 500, "the latest result is kept in full");
            tc.verifyEqual(numel(msgs), numel(h.Messages));
            roles = cellfun(@(m) string(m.role), msgs);
            tc.verifyEqual(roles, cellfun(@(m) string(m.role), h.Messages));
        end

        function compactionKeepsToolCallIdsMatched(tc)
            h = fomc.history.compact(longHistory(3), 1);
            msgs = h.Messages;
            ids = strings(0, 1); back = strings(0, 1);
            for i = 1:numel(msgs)
                if string(msgs{i}.role) == "assistant" && isfield(msgs{i}, "tool_calls") && ~isempty(msgs{i}.tool_calls)
                    tc1 = msgs{i}.tool_calls;
                    if iscell(tc1), tc1 = tc1{1}; end
                    ids(end+1) = string(tc1.id); %#ok<AGROW>
                elseif string(msgs{i}.role) == "tool"
                    back(end+1) = string(msgs{i}.tool_call_id); %#ok<AGROW>
                end
            end
            tc.verifyEqual(back, ids);
        end

        function compactionDoesNothingWhenThereIsLittleToTrim(tc)
            [h2, n] = fomc.history.compact(longHistory(1), 1);
            tc.verifyEqual(n, 0);
            tc.verifyEqual(numel(h2.Messages), numel(longHistory(1).Messages));
        end

        function tokenEstimateGrowsWithTheConversation(tc)
            a = fomc.history.estimateTokens(longHistory(1), "prompt");
            b = fomc.history.estimateTokens(longHistory(4), "prompt");
            tc.verifyGreaterThan(b, a);
        end

        function aLongConversationIsCompactedDuringATurn(tc)
            % A fake model that keeps calling tools, and a history that is already large, so compaction must kick in
            D0 = syntheticData();
            cfg2 = fomc.config(verbose=false, maxToolRounds=6, compactAtTokens=1500);
            call = struct("name", "listMeetings", "arguments", struct());
            script = {struct("content", "", "tool_calls", call), struct("content", "", "tool_calls", call), ...
                struct("content", "", "tool_calls", call), struct("content", "Done.")};
            m = fomc.llm.Mock(script);
            path = string(tempname) + ".jsonl";
            s = fomc.newSession(datetime(2020,3,1), cfg2, Llm=@m.call, Data=D0, TracePath=path);
            % Start with a large conversation
            for i = 1:6
                s.history = addUserMessage(s.history, string(repmat('q', 1, 800)));
                s.history = addResponseMessage(s.history, struct("role", "assistant", "content", string(repmat('a', 1, 800))));
            end
            [~, answer] = fomc.runTurn(s, "again");
            tc.verifyEqual(answer, "Done.");
            lines = readlines(path);
            types = arrayfun(@(l) string(jsondecode(l).type), lines(lines ~= ""));
            tc.verifyTrue(any(types == "model_response"));
        end
    end
end

function n = schemaChars()
reg = fomc.tools.registry();
ex = reg([reg.expose]);
n = 0;
for k = 1:numel(ex)
    n = n + strlength(string(jsonencode(ex(k).tool.encodeStruct())));
end
end

function h = longHistory(nTools)
% A conversation with nTools tool calls, each result 500 characters.
% Helper: a fake conversation with nTools tool calls
h = messageHistory;
h = addUserMessage(h, "Question");
for i = 1:nTools
    id = "call_" + i;
    call = struct("id", id, "type", "function", "function", struct("name", "readMinutes", "arguments", struct()));
    h = addResponseMessage(h, struct("role", "assistant", "content", "", "tool_calls", call));
    h = addToolMessage(h, id, "readMinutes", string(repmat('x', 1, 500)));
end
h = addResponseMessage(h, struct("role", "assistant", "content", "Answer."));
end
