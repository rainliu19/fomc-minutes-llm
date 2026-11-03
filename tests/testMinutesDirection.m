classdef testMinutesDirection < matlab.unittest.TestCase
    % The minutes' direction from the AI's saved rate-path scores (fomc.data.minutesDirection),
    % the saved scores themselves (data/scores, fomc.skills.scoreCache) and the backtest of the
    % direction against the next decision. No model: the scores were made by
    % pipeline/score_minutes.m with Qwen3 4B, so rescoring a meeting can change the counts here;
    % the counts are the ones reported in docs/agent_interface.md.

    properties
        D
        model
    end

    % Runs once before the tests: make the test helpers and src/ visible, load the real data
    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
            tc.model = fomc.config(verbose=false).model;
        end
    end

    % Each test below is named for what it checks
    methods (Test)
        function everyMeetingHasASavedRatePathScore(tc)
            saved = fomc.skills.scoreCache("list", tc.model);
            tc.verifyEqual(saved, fomc.util.fmtDate(tc.D.meetings.MeetingDate), ...
                "run pipeline/score_minutes.m for the meetings without a score");
        end

        function everySavedScoreThatPassedStillPassesTheSkillsChecks(tc)
            % Read back from disk, each score marked ok passes Aarya's checks against its own
            % minutes again: schema, quarter-point scores, quotes word for word, the rate path
            % against the decision, no dates after the release. Its quotes come from its own minutes.
            M = tc.D.meetings;
            for k = 1:height(M)
                meeting = fomc.util.fmtDate(M.MeetingDate(k));
                saved = fomc.skills.scoreCache("read", tc.model, meeting);
                tc.assertNotEmpty(saved, meeting);
                tc.verifyEqual([string(saved.meetingDate), string(saved.model)], [meeting, tc.model], meeting);
                tc.verifyTrue(any(string(saved.dimensionsScored) == "rate_path"), meeting);
                if ~saved.ok
                    tc.verifyNotEmpty(saved.issues, meeting + ": a failed score says why");
                    continue
                end
                text = string(M.Body(k)) + newline + strjoin(tc.D.paras.text(tc.D.paras.meetingIdx == k), newline);
                tc.verifyEmpty(fomc.guard.validateScores(saved.score, text, meeting, tc.D), meeting);
                d = saved.score.dimensions.rate_path;
                if string(d.status) == "scored"
                    tc.verifyTrue(abs(d.score) <= 1 && mod(d.score * 4, 1) == 0, meeting);
                    for e = fomc.util.asCell(d.evidence)
                        tc.verifyTrue(ismember(string(e{1}.paragraph_ref), tc.D.paras.id), meeting);
                        tc.verifyTrue(startsWith(string(e{1}.paragraph_ref), meeting + "/"), meeting);
                    end
                end
            end
        end

        function eightScoresFailedTheirChecksAndUseTheWordRules(tc)
            % Four said "not discussed" with a score, one had no quotes, and three rationales named
            % 2014 or 2013, which the 2011-2012 minutes themselves gave as the date in the
            % Committee's guidance; the check reads any later year as a leak
            failed = ["2008-06-25", "2010-08-10", "2011-06-22", "2011-08-09", "2012-03-13", ...
                "2012-04-25", "2012-06-20", "2012-08-01"];
            M = tc.D.meetings;
            got = strings(1, 0);
            for k = 1:height(M)
                meeting = fomc.util.fmtDate(M.MeetingDate(k));
                if ~fomc.skills.scoreCache("read", tc.model, meeting).ok
                    got(end+1) = meeting; %#ok<AGROW>
                    [~, levels] = fomc.data.ratePath(tc.D, M.ReleaseDate(k));
                    tc.verifyEqual(fomc.data.minutesDirection(tc.D, k, levels(end, :)).source, "rules", meeting);
                end
            end
            tc.verifyEqual(got, failed);
            r = fomc.data.economyAssessment(tc.D, datetime(2012,10,1));
            tc.verifyEqual(r.minutes.directionSource, "rules");
            tc.verifyFalse(contains(r.summary, "the AI scored"));
            tc.verifySubstring(r.note, "read by code from their wording");
        end

        function aScoreIsUsedOnlyOnceItsMinutesArePublic(tc)
            % The September 2026 minutes came out on 2026-10-07: the day before, the reading is
            % the July minutes' score (+0.50); that day, September's (+0.75)
            n = fomc.data.nextMeetingReading(tc.D, datetime(2026,10,6));
            tc.verifyEqual([n.minutesSource, string(n.ratePathScore)], ["ai", "0.5"]);
            n = fomc.data.nextMeetingReading(tc.D, datetime(2026,10,7));
            tc.verifyEqual([n.minutesSource, string(n.ratePathScore)], ["ai", "0.75"]);
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,6));
            tc.verifyEqual(r.minutes.meetingDate, "2026-07-29");
            tc.verifyFalse(contains(r.summary, "2026-09-16/"), "nothing from minutes not yet public");
        end

        function theAIsDirectionMatchesAReadingByHandFor16Of18Meetings(tc)
            % The 22 meetings read by hand for the word rules (testEconomy): every 2022 meeting and
            % every meeting since January 2025. Four are "depends on the data" or "divided", with no
            % one direction. Of the other 18 the AI agrees on 16; the two it misses:
            %   2022-11-02 +0.25 (hold): "ongoing increases" were expected
            %   2025-06-18 +0.25 (hold): most expected some reduction that year
            hand = [
                "2022-01-26", "up"; "2022-03-16", "up"; "2022-05-04", "up"; "2022-06-15", "up"
                "2022-07-27", "up"; "2022-09-21", "up"; "2022-11-02", "up"; "2022-12-14", "up"
                "2025-03-19", "hold"; "2025-05-07", "hold"; "2025-06-18", "down"; "2025-09-17", "down"
                "2025-10-29", "hold"; "2025-12-10", "hold"; "2026-01-28", "hold"; "2026-04-29", "hold"
                "2026-07-29", "up"; "2026-09-16", "up"];
            missed = strings(1, 0);
            for i = 1:height(hand)
                k = find(tc.D.meetings.MeetingDate == datetime(hand(i, 1)));
                [~, levels] = fomc.data.ratePath(tc.D, tc.D.meetings.ReleaseDate(k));
                m = fomc.data.minutesDirection(tc.D, k, levels(end, :));
                tc.verifyEqual(m.source, "ai", hand(i, 1));
                if m.way ~= hand(i, 2)
                    missed(end+1) = hand(i, 1); %#ok<AGROW>
                end
            end
            tc.verifyEqual(missed, ["2022-11-02", "2025-06-18"]);
        end

        function theBacktestMatchesWhatTheDocsReport(tc)
            % Each set of minutes against the next decision, as known the day the minutes came out.
            % The cutoff 0.5 was chosen on 2008-2018 and tested unchanged on 2019 on.
            T = backtest(tc.D);
            train = T(T.next < datetime(2019,1,1), :);
            test = T(T.next >= datetime(2019,1,1), :);
            tc.verifyEqual([height(train), height(test), sum(test.action ~= "hold")], [87, 62, 22]);
            tc.verifyEqual(sum(train.source == "ai"), 79, "8 failed scores use the word rules");
            % Right, moves caught, and moves called that did not happen
            tc.verifyEqual(tally(train.ai, train.action), [75, 9, 8], "AI, 2008-2018");
            tc.verifyEqual(tally(train.rules, train.action), [62, 11, 23], "word rules, 2008-2018");
            tc.verifyEqual(tally(test.ai, test.action), [50, 14, 4], "AI, 2019 on");
            tc.verifyEqual(tally(test.rules, test.action), [47, 18, 11], "word rules, 2019 on");
            tc.verifyEqual(tally(test.bill, test.action), [52, 14, 2], "6-month bill, 2019 on");
            tc.verifyEqual(sum(test.action == "hold"), 40, "a hold every time: 65%");
        end

        function theCutoffDecidesTheDirection(tc)
            % Scores written by hand into a temporary folder, on the synthetic minutes
            D = syntheticData();
            folder = string(tempname);
            range = table(1, 1.25, VariableNames=["lower", "upper"]);
            zero = table(0, 0.25, VariableNames=["lower", "upper"]);
            cases = {0.75, range, "up"; 0.5, range, "up"; 0.25, range, "hold"; 0, range, "hold"
                -0.25, range, "hold"; -0.5, range, "down"; -1, range, "down"; -1, zero, "hold"};
            for i = 1:height(cases)
                save1(folder, "2020-03-18", cases{i, 1});
                m = fomc.data.minutesDirection(D, 2, cases{i, 2}, Model="mock", Folder=folder);
                tc.verifyEqual([m.source, m.way], ["ai", cases{i, 3}], string(cases{i, 1}));
                tc.verifyEqual(m.score, cases{i, 1});
            end
            save1(folder, "2020-03-18", 0.25);
            m = fomc.data.minutesDirection(D, 2, range, Model="mock", Folder=folder, Cutoff=0.25);
            tc.verifyEqual(m.way, "up", "a lower cutoff");
            m = fomc.data.minutesDirection(D, 2, range, Model="mock", Folder=folder, UseAI=false);
            tc.verifyEqual(m.source, "rules");
            tc.verifyTrue(isnan(m.score));
            tc.verifyEqual(m.way, m.ruleWay);
        end

        function aScoreThatCannotBeTrustedFallsBackToTheWordRules(tc)
            D = syntheticData();
            folder = string(tempname);
            range = table(1, 1.25, VariableNames=["lower", "upper"]);
            bad = {struct("ok", false), struct("status", "not_discussed"), ...
                struct("dimensionsScored", "inflation"), struct("score", [])};
            for i = 1:numel(bad)
                save1(folder, "2020-03-18", -0.5, bad{i});
                m = fomc.data.minutesDirection(D, 2, range, Model="mock", Folder=folder);
                tc.verifyEqual(m.source, "rules", string(fieldnames(bad{i})));
                tc.verifyEmpty(m.evidence);
            end
            % No score saved at all
            m = fomc.data.minutesDirection(D, 1, range, Model="mock", Folder=folder);
            tc.verifyEqual(m.source, "rules");
        end

        function theCacheReadsNothingWhereNothingIsSaved(tc)
            folder = string(tempname);
            tc.verifyEmpty(fomc.skills.scoreCache("list", "mock", Folder=folder));
            tc.verifyEmpty(fomc.skills.scoreCache("read", "mock", "2020-01-29", Folder=folder));
            tc.verifyFalse(isfolder(folder), "reading makes no folder");
        end

        function aCutQuoteIsMarkedInTheAssessment(tc)
            % The skill keeps quotes to 40 words; the September 2026 decision sentence is longer
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,7));
            tc.verifySubstring(r.summary, "in the banking..."" [2026-09-16/policyAction/1]");
            tc.verifySubstring(r.summary, "by year end."" [2026-09-16/participantsViews/11]");
            tc.verifyFalse(contains(r.summary, "year end...."), "a whole sentence is not marked");
        end

        function theMemoryGuardStopsOnlyWhenMemoryIsShort(tc)
            % pressure (1 normal, 2 warning, 4 critical), swap in MB, stop?
            cases = [1 1000 0; 1 3800 0; 2 3000 0; 2 3800 1; 4 500 1; 1 6100 1];
            for i = 1:height(cases)
                tc.verifyEqual(fomc.util.memoryShort(cases(i, 1), cases(i, 2)), logical(cases(i, 3)), ...
                    sprintf("pressure %d, swap %d", cases(i, 1), cases(i, 2)));
            end
        end
    end
end

function save1(folder, meeting, score, change)
% Save a rate-path score for the synthetic meeting by hand; change overrides fields
if nargin < 4
    change = struct();
end
d = struct("status", "scored", "score", score, "confidence", "high", "rationale", "Made up.", ...
    "evidence", {{struct("quote", "Made up.", "paragraph_ref", meeting + "/policyAction/1")}});
rec = struct("meetingDate", meeting, "model", "mock", "ok", true, "issues", {{}}, ...
    "dimensionsScored", "rate_path", "score", struct("dimensions", struct("rate_path", d)));
for f = string(fieldnames(change)).'
    if f == "status" || f == "score"
        rec.score.dimensions.rate_path.(f) = change.(f);
    else
        rec.(f) = change.(f);
    end
end
if ~isfolder(fullfile(folder, "mock"))
    mkdir(fullfile(folder, "mock"));
end
writelines(jsonencode(rec), fullfile(folder, "mock", meeting + ".json"));
end

function T = backtest(D)
% For each set of minutes but the last: the next meeting, its decision, and the decision each
% signal points to on the day the minutes came out
M = D.meetings;
n = height(M) - 1;
[source, ai, rules, bill] = deal(strings(n, 1));
toAction = @(w) replace(replace(replace(w, "unclear", "hold"), "up", "raise"), "down", "cut");
for k = 1:n
    [~, levels] = fomc.data.ratePath(D, M.ReleaseDate(k));
    m = fomc.data.minutesDirection(D, k, levels(end, :));
    b = fomc.data.billSignal(D, M.ReleaseDate(k), levels(end, :));
    source(k) = m.source;
    ai(k) = toAction(m.way);
    rules(k) = toAction(m.ruleWay);
    bill(k) = "hold";
    if ~isempty(fieldnames(b))
        bill(k) = toAction(string(b.way));
    end
end
T = table(M.MeetingDate(2:end), string(D.cards.action(2:end)), source, ai, rules, bill, ...
    VariableNames=["next", "action", "source", "ai", "rules", "bill"]);
end

function t = tally(predicted, actual)
% [right, moves caught, moves called that did not happen]
moves = actual ~= "hold";
t = [sum(predicted == actual), sum(predicted == actual & moves), sum(predicted ~= "hold" & ~moves)];
end
