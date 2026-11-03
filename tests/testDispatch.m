classdef testDispatch < matlab.unittest.TestCase
    % Tool dispatch and the tools. SYNTHETIC data. Failures return error JSON, never exceptions.

    properties
        ctx
    end

    % Runs once before the tests: make the test helpers and src/ visible, build the test data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    % Runs before every test: a fresh context anchored at 2020-03-01
    methods (TestMethodSetup)
        function makeContext(tc)
            cfg = fomc.config(verbose=false);
            tc.ctx = fomc.context(datetime(2020,3,1), cfg, syntheticData(), ...
                tracePath=string(tempname) + ".jsonl");
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function unknownToolReturnsErrorJson(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "nope", struct());
            tc.verifyTrue(isfield(jsondecode(json), "error"));
            tc.verifyFalse(rec.ok);
        end

        function readSkillIsRegisteredAndExposed(tc)
            reg = fomc.tools.registry();
            i = find(string({reg.name}) == "readSkill", 1);
            tc.verifyNotEmpty(i);
            tc.verifyTrue(reg(i).expose);
        end

        function readSkillLoadsDefaultSkillInstructionsAndLogs(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readSkill", struct("name", "fomc-score"));
            result = jsondecode(json);
            tc.verifyTrue(rec.ok);
            tc.verifyEqual(string(result.file), "SKILL.md");
            tc.verifySubstring(result.content, "FOMC Minutes Scoring");
            events = readlines(tc.ctx.tracePath);
            tc.verifyTrue(any(contains(events, """type"":""skill_read""")));
        end

        function readSkillRejectsMissingName(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readSkill", struct());
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "'name' is required");
        end

        function readSkillReportsUnknownNameAndAvailableSkills(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readSkill", struct("name", "unknown-skill"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "Unknown skill");
            tc.verifySubstring(json, "fomc-score");
        end

        function readSkillCanLoadReferencedFile(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readSkill", ...
                struct("name", "fomc-score", "file", "rubric/ratePath.md"));
            tc.verifyTrue(rec.ok);
            tc.verifySubstring(json, "rate_path");
        end

        function badJsonReturnsErrorJson(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "listMeetings", "{not json");
            tc.verifySubstring(json, "not valid JSON");
            tc.verifyFalse(rec.ok);
        end

        function jsonStringArgumentsAreParsed(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "listMeetings", '{"n": 5}');
            tc.verifyTrue(rec.ok);
            tc.verifyEqual(jsondecode(json).count, 1);   % only the January meeting is public
        end

        function missingRequiredArgumentReturnsGuidance(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", struct("section", "policyAction"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "meetingDate");
        end

        function guardrailBlockIsReturnedToTheModel(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", ...
                struct("meetingDate", "2020-03-18", "section", "policyAction"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "after the anchor date");
        end

        function unreleasedMeetingIsNotListed(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "listMeetings", struct());
            tc.verifyFalse(contains(json, "2020-03-18"));
        end

        function readMinutesReturnsSectionText(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", ...
                struct("meetingDate", "2020-01-29", "section", "policyAction"));
            tc.verifyTrue(rec.ok);
            tc.verifySubstring(json, "maintain the target range");
        end

        function unknownMeetingDateOffersNearestRealOnes(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", ...
                struct("meetingDate", "2020-01-30", "section", "policyAction"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "2020-01-29");
        end

        function longSectionIsPagedByParagraphAndPagesJoinBackToTheOriginal(tc)
            D = syntheticData();
            % Make one section of 60 paragraphs, read it back page by page, and check nothing is lost or repeated
            para = "Paragraph " + (1:60) + " of SYNTHETIC text that repeats to make this section long enough to need pages.";
            minutes = D.meetings;
            minutes.PolicyAction(1) = strjoin(para, newline);
            D2 = fomc.data.build(D.wide, D.vint, D.dict, D.avail, minutes);
            cfg = fomc.config(verbose=false, maxToolChars=1000);
            ctx2 = fomc.context(datetime(2020,3,1), cfg, D2, tracePath=string(tempname) + ".jsonl");
            got = strings(0, 1);
            next = 1;
            for k = 1:100
                [json, rec] = fomc.tools.dispatch(ctx2, "readMinutes", struct("meetingDate", "2020-01-29", ...
                    "section", "policyAction", "startParagraph", next));
                tc.verifyTrue(rec.ok);
                r = jsondecode(json);
                page = fomc.util.asCell(r.paragraphs);
                tc.verifyLessThanOrEqual(strlength(jsonencode(r.paragraphs)), 1000 + 200 * numel(page));
                for i = 1:numel(page), got(end+1, 1) = string(page{i}.text); end %#ok<AGROW>
                if ~isfield(r, "nextParagraph"), break, end
                next = r.nextParagraph;
            end
            tc.verifyEqual(got, para(:));
        end

        function everyParagraphReadCarriesItsId(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "readMinutes", ...
                struct("meetingDate", "2020-01-29", "section", "participantsViews"));
            r = jsondecode(json);
            tc.verifyEqual(string(r.paragraphs(1).id), "2020-01-29/participantsViews/1");
            tc.verifyEqual(r.totalParagraphs, 2);
        end

        function readingPastTheEndGivesGuidance(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", struct("meetingDate", "2020-01-29", ...
                "section", "participantsViews", "startParagraph", 5));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "2 paragraphs");
        end

        function theWholeBodyIsNotOfferedAsASection(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "readMinutes", struct("meetingDate", "2020-01-29", "section", "body"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "participantsViews");
        end

        function getDecisionReturnsTheCard(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "getDecision", struct("meetingDate", "2020-01-29"));
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyEqual(r.action, 'hold');
            tc.verifyEqual(r.decision.id, '2020-01-29/policyAction/1');
        end

        function getDecisionRefusesUnreleasedMinutes(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "getDecision", struct("meetingDate", "2020-03-18"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "after the anchor date");
        end

        function getDecisionForANonMeetingDateOffersRealOnes(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "getDecision", struct("meetingDate", "2020-01-30"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "2020-01-29");
        end

        function searchHitsCarryAnId(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "searchMinutes", struct("query", "trade dispute"));
            r = jsondecode(json);
            tc.verifyEqual(string(r.hits(1).id), "2020-01-29/participantsViews/2");
        end

        function searchFindsOnlyReleasedMinutes(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "searchMinutes", struct("query", "SYNTHETIC"));
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyGreaterThan(r.totalMatches, 0);
            tc.verifyFalse(contains(json, "2020-03-18"));
            tc.verifyFalse(contains(json, "weakened sharply"));
        end

        function searchWithNoMatchGivesAdvice(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "searchMinutes", struct("query", "zzzzqqq"));
            tc.verifySubstring(json, "No paragraphs matched");
        end

        function searchAlternativesAreOr(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "searchMinutes", struct("query", "zzzzqqq|trade dispute"));
            tc.verifyEqual(jsondecode(json).totalMatches, 1);
        end

        function getSeriesParsesCommaSeparatedIds(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "getSeries", struct("seriesIds", "UNRATE, DGS10"));
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyEqual(numel(r.series), 2);
        end

        function getSeriesRespectsAsOfRevision(tc)
            % Anchor 2020-03-01 is before the 2020-03-06 revision of January 2020
            [json, ~] = fomc.tools.dispatch(tc.ctx, "getSeries", struct("seriesIds", "UNRATE"));
            r = jsondecode(json);
            row = r.series.rows;
            tc.verifyEqual(row(1).value, 3.5);
            tc.verifyEqual(numel(row), 1);               % February is not known yet
        end

        function getSeriesExcludedSeriesIsExplained(tc)
            [json, ~] = fomc.tools.dispatch(tc.ctx, "getSeries", struct("seriesIds", "USREC"));
            tc.verifySubstring(json, "excluded");
        end

        function consumerScoreIsAStubAndSaysSo(tc)
            [json, rec] = fomc.tools.dispatch(tc.ctx, "scoreConsumerImpact", struct("meetingDate", "2020-01-29"));
            tc.verifyTrue(rec.ok);
            tc.verifySubstring(json, "not implemented");
        end

        function everyCallIsTraced(tc)
            fomc.tools.dispatch(tc.ctx, "listMeetings", struct());
            fomc.tools.dispatch(tc.ctx, "nope", struct());
            lines = readlines(tc.ctx.tracePath);
            lines(lines == "") = [];
            tc.verifyEqual(numel(lines), 2);
            for l = lines.'
                e = jsondecode(l);
                tc.verifyEqual(e.type, 'tool_call');
            end
        end
    end
end
