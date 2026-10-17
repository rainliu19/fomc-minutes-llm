classdef testAnalysisMock < matlab.unittest.TestCase
    % Analysis mode (structured output, grounding retry) with a scripted model.
    % SYNTHETIC data, anchor 2020-03-01.

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
            tc.D = syntheticData();
            tc.cfg = fomc.config(verbose=false, prefetch=false);
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function groundedAnalysisIsReturnedAndAnchorIsOverwritten(tc)
            m = fomc.llm.Mock({struct("content", "", "tool_calls", struct("name", "readMinutes", "arguments", struct("meetingDate", "2020-01-29", "section", "participantsViews"))), struct("content", "Draft findings."), struct("content", analysisJson("2020-01-29/participantsViews/1"))});
            [~, structured] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyTrue(structured.groundingOk);
            tc.verifyEqual(string(structured.anchorDate), "2020-03-01");
            tc.verifyEqual(string(structured.policyStance), "neutral");
            tc.verifyFalse(m.Seen(3).useTools, "the structuring call must not offer tools");
            tc.verifyNotEmpty(m.Seen(3).format);
        end

        function theHarnessFillsInTheExactQuote(tc)
            m = fomc.llm.Mock({struct("content", "", "tool_calls", struct("name", "readMinutes", "arguments", struct("meetingDate", "2020-01-29", "section", "participantsViews"))), struct("content", "Draft."), struct("content", analysisJson("2020-01-29/participantsViews/1"))});
            [~, structured] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            e = structured.evidence{1};
            tc.verifyEqual(string(e.quote), "Participants agreed that SYNTHETIC inflation was running below target.");
            tc.verifyEqual(string(e.meetingDate), "2020-01-29");
            tc.verifyEqual(string(e.section), "participantsViews");
        end

        function failedGroundingIsRetriedWithFeedback(tc)
            m = fomc.llm.Mock({struct("content", "", "tool_calls", struct("name", "readMinutes", "arguments", struct("meetingDate", "2020-01-29", "section", "participantsViews"))), struct("content", "Draft."), ...
                struct("content", analysisJson("2020-01-29/policyAction/1")), ...
                struct("content", analysisJson("2020-01-29/participantsViews/1"))});
            [~, structured, ~, s] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(numel(m.Seen), 4);          % tool call, draft, two structuring attempts
            tc.verifyTrue(structured.groundingOk);
            feedback = s.history.Messages{end-1};
            tc.verifySubstring(string(feedback.content), "did not pass the checks");
        end

        function persistentFailureIsFlaggedNotAccepted(tc)
            m = fomc.llm.Mock({struct("content", "", "tool_calls", struct("name", "readMinutes", "arguments", struct("meetingDate", "2020-01-29", "section", "participantsViews"))), struct("content", "Draft."), ...
                struct("content", analysisJson("2020-01-29/policyAction/1"))});
            [~, structured] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(numel(m.Seen), 4);            % tool call, draft, two attempts
            tc.verifyFalse(structured.groundingOk);
            tc.verifyNotEmpty(structured.groundingFailures);
        end

        function replyThatIsNotJsonIsFlagged(tc)
            m = fomc.llm.Mock({struct("content", "", "tool_calls", struct("name", "readMinutes", "arguments", struct("meetingDate", "2020-01-29", "section", "participantsViews"))), struct("content", "Draft."), struct("content", "I think rates stay.")});
            [~, structured] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyFalse(structured.groundingOk);
        end

        function analysisWithoutAnyToolCallIsNudgedOnce(tc)
            read = struct("name", "readMinutes", "arguments", ...
                struct("meetingDate", "2020-01-29", "section", "participantsViews"));
            m = fomc.llm.Mock({struct("content", "I cannot find that meeting."), ...
                struct("content", "", "tool_calls", read), ...
                struct("content", "Inflation was below target."), ...
                struct("content", analysisJson("2020-01-29/participantsViews/1"))});
            [~, structured, calls, s] = fomc.runAgent("Analyze.", datetime(2020,3,1), Format="analysis", ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(numel(calls), 1);
            tc.verifyTrue(structured.groundingOk);
            contents = cellfun(@(x) string(x.content), s.history.Messages);
            tc.verifyTrue(any(contains(contents, "You have not read any minutes yet")));
        end

        function chatQuestionAboutTheCommitteeIsNudgedUntilMinutesAreRead(tc)
            read = struct("name", "readMinutes", "arguments", ...
                struct("meetingDate", "2020-01-29", "section", "policyAction"));
            m = fomc.llm.Mock({struct("content", "They held rates."), ...
                struct("content", "", "tool_calls", read), ...
                struct("content", "The Committee decided to maintain the target range.")});
            [answer, ~, calls] = fomc.runAgent("What did the Committee decide?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual([calls.name], "readMinutes");
            tc.verifyEqual(answer, "The Committee decided to maintain the target range.");
        end

        function listingMeetingsAloneDoesNotCountAsReadingThem(tc)
            list = struct("name", "listMeetings", "arguments", struct());
            m = fomc.llm.Mock({struct("content", "", "tool_calls", list), ...
                struct("content", "They held rates."), struct("content", "Still no reading.")});
            [~, ~, ~, s] = fomc.runAgent("What did the Committee decide?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            contents = cellfun(@(x) string(x.content), s.history.Messages);
            tc.verifyTrue(any(contains(contents, "You have not read any minutes yet")));
        end

        function gettingTheDecisionCountsAsReadingTheMinutes(tc)
            get = struct("name", "getDecision", "arguments", struct("meetingDate", "2020-01-29"));
            m = fomc.llm.Mock({struct("content", "", "tool_calls", get), ...
                struct("content", "The Committee decided to hold.")});
            [answer, ~, calls, s] = fomc.runAgent("What did the Committee decide?", datetime(2020,3,1), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual([calls.name], "getDecision");
            tc.verifyEqual(answer, "The Committee decided to hold.");
            tc.verifyEqual(numel(m.Seen), 2, "no nudge, so only two model calls");
            contents = cellfun(@(x) string(x.content), s.history.Messages);
            tc.verifyFalse(any(contains(contents, "You have not read any minutes yet")));
        end

        function chatModeIsNotNudged(tc)
            m = fomc.llm.Mock({struct("content", "No tools needed.")});
            [answer, ~, calls] = fomc.runAgent("Hi", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(answer, "No tools needed.");
            tc.verifyEmpty(calls);
            tc.verifyEqual(numel(m.Seen), 1);
        end

        function chatModeNeverStructures(tc)
            m = fomc.llm.Mock({struct("content", "Plain answer.")});
            [answer, structured] = fomc.runAgent("Hi", datetime(2020,3,1), Config=tc.cfg, ...
                Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifyEqual(answer, "Plain answer.");
            tc.verifyEmpty(structured);
            tc.verifyEqual(numel(m.Seen), 1);
        end

        function schemaHasTheSpecifiedFields(tc)
            sc = jsondecode(fomc.analysis.schema());
            want = ["meetingDate","summary","policyStance","keyDrivers","evidence","dataCited","caveats"];
            tc.verifyEqual(sort(string(sc.required)).', sort(want));
            tc.verifyFalse(sc.additionalProperties);
        end

        function meetingFocusIsAddedToTheQuestion(tc)
            m = fomc.llm.Mock({struct("content", "ok")});
            [~, ~, ~, s] = fomc.runAgent("What drove it?", datetime(2020,3,1), MeetingDate=datetime(2020,1,29), ...
                Config=tc.cfg, Llm=@m.call, Data=tc.D, TracePath=string(tempname)+".jsonl");
            tc.verifySubstring(string(s.history.Messages{1}.content), "ended on 2020-01-29");
        end
    end
end

function j = analysisJson(id)
% A valid analysis in JSON, citing the paragraph id given
ev = struct("claim", "Inflation was low.", "id", id);
s = struct("meetingDate", "2020-01-29", "summary", "Synthetic summary.", ...
    "policyStance", "neutral", "keyDrivers", {{"low inflation"}}, ...
    "evidence", {{ev}}, ...
    "dataCited", {{struct("series", "UNRATE", "value", 3.5, "date", "2020-01-01")}}, ...
    "caveats", {{"synthetic data"}});
j = string(jsonencode(s));
end
