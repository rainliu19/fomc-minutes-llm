classdef testEconomy < matlab.unittest.TestCase
    % The economy against the Fed's goals and what the latest minutes say about future meetings
    % (assessEconomy), and the lookup that adds it to a question. REAL data, no model. Expected
    % values were worked out from the data as known on each date, and expected leans read by
    % hand from the minutes, not from memory.

    properties
        D
        cfg
    end

    % Runs once before the tests: make the test helpers and src/ visible, load the real data
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
        function theEconomyInOctober2026(tc)
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,7));
            tc.verifyEqual([r.inflation.value, r.inflation.gap], [3.01, 1.01], AbsTol=0.01);
            tc.verifyEqual(r.inflation.trend, "falling");
            tc.verifyEqual([r.unemployment.value, r.unemployment.normal, r.unemployment.gap], [4.2, 4.39, -0.19], AbsTol=0.01);
            tc.verifyEqual(r.outputGap.quarter, "2026 Q2");
            tc.verifyEqual(r.outputGap.value, 1.40, AbsTol=0.01);
            tc.verifyEqual(r.targetRange, "3-3/4 to 4 percent");
            tc.verifyEqual(r.market.suggests, "increases");
            tc.verifyEqual(r.market.aboveMiddleOfRange, 0.92, AbsTol=0.01);
        end

        function thePolicyRulesUseTheTextbookFormula(tc)
            % Neutral real rate + inflation + 0.5 x (inflation - 2) + b x output gap; b = 0.5 or 1
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,7));
            values = cellfun(@(x) x.value, r.rules).';
            tc.verifyEqual(values, [4.71, 6.21, 5.41, 6.91], AbsTol=0.02);
            tc.verifyEqual(r.rulesVsRange, "above");
            tc.verifySubstring(r.summary, "below all four");
        end

        function inMarch2022TheRulesWereFarAboveTheRange(tc)
            % Two weeks before the first increase of 2022: inflation 5.2%, the range at 0 to 1/4
            r = fomc.data.economyAssessment(tc.D, datetime(2022,3,1));
            tc.verifyEqual(r.inflation.value, 5.21, AbsTol=0.01);
            tc.verifyEqual(r.targetRange, "0 to 1/4 percent");
            values = cellfun(@(x) x.value, r.rules);
            tc.verifyGreaterThan(min(values), 6.5);
            tc.verifyEqual(r.rulesVsRange, "above");
        end

        function in2009ARuleBelowZeroIsSaidToBeImpossible(tc)
            % The CBO's normal unemployment rate is only in the data from February 2011
            r = fomc.data.economyAssessment(tc.D, datetime(2009,6,1));
            tc.verifyFalse(isfield(r.unemployment, "normal"));
            tc.verifySubstring(r.summary, "not in this data before February 2011");
            tc.verifySubstring(r.summary, "cannot set the range lower than 0 to 1/4 percent");
            tc.verifyEqual(r.rulesVsRange, "mixed");
        end

        function trendsAndMixedRulesAreDescribedExactly(tc)
            % January 2019: unemployment 3.9% against 3.7% three months earlier (rising),
            % inflation 1.88% against 1.95% (within 0.1 point: steady)
            r = fomc.data.economyAssessment(tc.D, datetime(2019,1,31));
            tc.verifyEqual([r.unemployment.trend, r.inflation.trend], ["rising", "steady"]);
            % January 2009: three rules above the range of 0 to 1/4 percent and one inside it
            r = fomc.data.economyAssessment(tc.D, datetime(2009,1,6));
            tc.verifyEqual(r.rulesVsRange, "mixed");
            tc.verifySubstring(r.summary, "with 3 rules above it and 1 within it");
        end

        function beforeCorePCEDataThereAreNoRules(tc)
            % Core PCE vintages start in 2000; before December 2008 the target was one number
            r = fomc.data.economyAssessment(tc.D, datetime(1999,6,1));
            tc.verifyEmpty(r.rules);
            tc.verifySubstring(r.summary, "Policy rules cannot be worked out");
            tc.verifySubstring(r.summary, "The target is 4-3/4 percent");
        end

        function atEveryReleaseDateNothingIsLaterAndNothingIsMissing(tc)
            for asOf = tc.D.meetings.ReleaseDate.'
                ctx = context(tc, asOf);
                r = fomc.data.economyAssessment(tc.D, asOf);
                json = string(jsonencode(r));
                g = fomc.guard.checkToolOutput(ctx, r, json);
                tc.verifyTrue(g.ok, g.message);
                tc.verifyFalse(contains(r.summary, ["NaN", "Inf", "  "]), fomc.util.fmtDate(asOf) + ": " + r.summary);
                tc.verifyNotEmpty(r.rules, fomc.util.fmtDate(asOf));
                % It quotes up to two sentences of the minutes, so it is longer than the figures alone
                tc.verifyLessThanOrEqual(strlength(json), 6500);
            end
        end

        function theViewsOnFutureMeetingsMatchAReadingByHand(tc)
            % Every meeting of 2022 and every meeting since January 2025, read by hand from Participants' Views
            % and the Committee Policy Action: what most participants expected for the rate
            expected = [
                "2022-01-26", "increases"            % "it would soon be appropriate to raise"
                "2022-03-16", "increases"            % "ongoing increases ... would be warranted"
                "2022-05-04", "increases"            % 50 basis point increases at the next couple of meetings
                "2022-06-15", "increases"
                "2022-07-27", "increases"
                "2022-09-21", "increases"
                "2022-11-02", "increases"            % ongoing increases, at a pace taking lags into account
                "2022-12-14", "increases"            % and no participant expected cuts in 2023
                "2025-01-29", "depends on the data"  % hold if strong, ease if the labor market weakened
                "2025-03-19", "hold"                 % well positioned to wait for more clarity
                "2025-05-07", "hold"
                "2025-06-18", "cuts"                 % most: some reduction this year
                "2025-07-30", "depends on the data"  % tighter if tariffs lift inflation, easier if jobs weaken
                "2025-09-17", "cuts"                 % most: ease further over the remainder of the year
                "2025-10-29", "hold"                 % many: keep the range unchanged for the rest of the year
                "2025-12-10", "hold"
                "2026-01-28", "hold"                 % hold the policy rate steady for some time
                "2026-03-18", "divided"              % most: cuts if the conflict softens jobs; many: increases if oil persists
                "2026-04-29", "hold"
                "2026-06-17", "divided"              % many within or below the range by year end, many others above
                "2026-07-29", "increases"
                "2026-09-16", "increases"];          % most: another increase by year end
            for i = 1:height(expected)
                k = find(tc.D.meetings.MeetingDate == datetime(expected(i, 1)));
                V = fomc.data.policyViews(tc.D, k);
                tc.verifyEqual(V.lean, expected(i, 2), expected(i, 1));
                tc.verifyTrue(all(cellfun(@(v) startsWith(v.id, expected(i, 1) + "/"), V.views)), expected(i, 1));
            end
        end

        function theViewsSkipDissentsTheStatementAndThisMeeting(tc)
            % March 2017: the dissenting member's view; 2012: the quoted statement; September
            % 2026: "all participants supported raising ... at this meeting"
            V = fomc.data.policyViews(tc.D, find(tc.D.meetings.MeetingDate == datetime(2017,3,15)));
            tc.verifyFalse(any(cellfun(@(v) contains(v.text, ["That member", "Kashkari"]), V.views)));
            V = fomc.data.policyViews(tc.D, find(tc.D.meetings.MeetingDate == datetime(2012,8,1)));
            tc.verifyFalse(any(cellfun(@(v) endsWith(v.text, """"), V.views)));
            V = fomc.data.policyViews(tc.D, find(tc.D.meetings.MeetingDate == datetime(2026,9,16)));
            tc.verifyFalse(any(cellfun(@(v) contains(v.text, "at this meeting"), V.views)));
            tc.verifyEqual(V.views{1}.id, "2026-09-16/participantsViews/11");
            tc.verifyEqual(V.views{1}.share, "most");
        end

        function inOctober2026TheMinutesLeanTowardAnotherIncrease(tc)
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,7));
            tc.verifyEqual([r.minutes.meetingDate, r.minutes.releaseDate, r.minutes.lean], ...
                ["2026-09-16", "2026-10-07", "increases"]);
            % The AI scored the rate path of the September minutes +0.75 (data/scores)
            tc.verifyEqual([r.minutes.directionSource, string(r.minutes.aiRatePathScore)], ["ai", "0.75"]);
            tc.verifySubstring(r.summary, "the AI scored the rate path +0.75 on its scale from -1 (dovish) to +1 (hawkish), a lean toward further increases.");
            tc.verifySubstring(r.summary, "maintaining ample reserves in the banking..."" [2026-09-16/policyAction/1]");
            tc.verifySubstring(r.note, "the AI's score of their rate path");
            tc.verifySubstring(r.summary, "another increase in the target range for the federal funds rate would likely be appropriate by year end."" [2026-09-16/participantsViews/11]");
            tc.verifySubstring(r.summary, "revised its inflation forecast higher [2026-09-16/staffOutlook/1]");
            tc.verifySubstring(r.summary, "revised its growth and spending forecast stronger [2026-09-16/staffOutlook/2]");
            % Payrolls 158,892 thousand in June and 159,044 in September: 51,000 a month
            tc.verifyEqual(r.payrolls.averageMonthlyChangeThousands, 51);
            tc.verifySubstring(r.summary, "Payrolls rose by an average of 51,000 a month over the three months to September 2026.");
            tc.verifyEqual([r.gdpGrowth.quarter, string(r.gdpGrowth.annualRate)], ["2026 Q2", "2.2"]);
            % The 6-month bill at 4.28%, 0.40 above the effective fed funds rate of 3.88%
            tc.verifyEqual([r.market.sixMonthBill, r.market.effectiveRate, r.market.billAboveEffectiveRate], [4.28, 3.88, 0.4], AbsTol=1e-9);
            tc.verifyEqual(r.market.billSuggests, "an increase soon");
        end

        function nearZeroALeanToCutsMeansMoreSupportAndALaterMeetingIsNamed(tc)
            % October 2012: the range at 0 to 1/4 percent; the September 13 meeting has been
            % held but its minutes come out on October 4
            r = fomc.data.economyAssessment(tc.D, datetime(2012,10,1));
            tc.verifyEqual(r.minutes.meetingDate, "2012-08-01");
            tc.verifySubstring(r.summary, "lean toward more support for the economy, by means other than the rate");
            tc.verifyEqual(r.minutes.laterMeeting, "2012-09-13");
            tc.verifySubstring(r.summary, "minutes are not public until 2012-10-04");
        end

        function questionsAboutWherePolicyShouldGoGetIt(tc)
            for q = ["Should the Fed raise rates at the next meeting?", "What will the Fed do next?", ...
                    "What do current economic conditions mean for future FOMC meeting decisions?", ...
                    "What could happen at the next Fed meeting?", "Will interest rates go down?", ...
                    "Is the Fed behind the curve?", "Is policy too tight?", "Are rates still restrictive?", ...
                    "What does the Taylor rule say?", "Is the economy overheating?", ...
                    "How far is inflation from the Fed's target?", "Do markets expect more rate cuts?"]
                [text, recs] = fomc.focus.economyPrefetch(context(tc, datetime(2026,10,7)), q);
                tc.verifySubstring(text, "How the economy compares with the Fed's goals", q);
                tc.verifyEqual(recs.name, "assessEconomy", q);
            end
        end

        function aQuestionAboutTheNextDecisionGetsTheEconomyLookupAlone(tc)
            % Given getOutlook too, Qwen3 4B answered with earlier runs since 1990 and the 2-year
            % yield in place of the next-meeting reading. A question that also names an effect on
            % households gets both.
            ctx = context(tc, datetime(2026,10,7));
            [~, recs] = fomc.focus.prefetch(ctx, "What do current economic conditions and the latest Fed minutes mean for the next FOMC meeting?", false);
            tc.verifyTrue(any(string({recs.name}) == "assessEconomy"));
            tc.verifyFalse(any(string({recs.name}) == "getOutlook"));
            [~, recs] = fomc.focus.prefetch(ctx, "Will the Fed raise rates at the next meeting, and what would that mean for mortgage rates?", false);
            tc.verifyTrue(all(ismember(["assessEconomy", "getOutlook"], string({recs.name}))));
            [~, recs] = fomc.focus.prefetch(ctx, "What do the Fed's recent rate increases mean for mortgage rates and consumer spending?", false);
            tc.verifyTrue(any(string({recs.name}) == "getOutlook"));
            tc.verifyFalse(any(string({recs.name}) == "assessEconomy"));
        end

        function otherQuestionsGetNothing(tc)
            for q = ["What did the Committee decide at its March 2020 meeting?", ...
                    "How have interest rates changed over the past year?", "What is the unemployment rate?", ...
                    "What did participants say about inflation?", "Who dissented in 2022?", "Tell me something interesting."]
                [text, recs] = fomc.focus.economyPrefetch(context(tc, datetime(2026,10,7)), q);
                tc.verifyEqual(text, "", q);
                tc.verifyEmpty(recs, q);
            end
        end

        function itIsTheLastLookupAndItsFiguresCanBeCited(tc)
            % fomc.focus.prefetch adds it last; a High-effort answer may cite the series it lists
            ctx = context(tc, datetime(2026,10,7));
            [text, recs] = fomc.focus.prefetch(ctx, "Should the Fed raise rates at the next meeting?", false);
            names = string({recs.name});
            tc.verifyEqual(names(end), "assessEconomy");
            tc.verifyTrue(endsWith(strtrim(text), "]"));
            tc.verifySubstring(text, "How the economy compares with the Fed's goals");
            ok = @(s, d, v) ~any(startsWith(fomc.guard.checkGrounding(struct("evidence", {{}}, ...
                "dataCited", {{struct("series", s, "date", d, "value", v)}}), ctx, recs).failures, "Data item"));
            tc.verifyTrue(ok("PCEPILFE", "2026-08-01", 3.01), "core inflation, 12-month change");
            tc.verifyTrue(ok("UNRATE", "2026-09-01", 4.2));
            tc.verifyTrue(ok("NROU", "2026-07-01", 4.39));
            tc.verifyTrue(ok("PAYEMS", "2026-09-01", 159044));
            tc.verifyTrue(ok("A191RL1Q225SBEA", "2026-04-01", 2.2));
            tc.verifyTrue(ok("DGS6MO", "2026-10-06", 4.28));
            tc.verifyFalse(ok("UNRATE", "2026-09-01", 5.2), "a wrong value");
            % The minutes it quotes count as returned by a tool, so an answer may cite them
            tc.verifyTrue(ismember("2026-09-16/participantsViews/11", fomc.guard.idsIn(recs(end).result)));
        end

        function itEndsByAskingForTheMinutesIds(tc)
            % Qwen3 4B answered "What could happen at the next Fed meeting?" in February 2026 from
            % the quotes without citing them, when the ask was only at the start
            text = fomc.focus.economyPrefetch(context(tc, datetime(2026,2,23)), "What could happen at the next Fed meeting?");
            tc.verifyTrue(endsWith(text, "cite the minutes you use with their ids, such as [2026-01-28/participantsViews/9], " + ...
                "and say what participants expected, not what the Fed should or will do.]"));
        end

        function theNextMeetingReadingTakesDirectionFromTheMinutesAndTimingFromTheBill(tc)
            % October 2026: the minutes lean to increases and the 6-month bill is 0.40 above the
            % effective rate, so both point up. August 2024: the bill is 0.41 below the effective
            % rate (4.92 against 5.33), so it points to a cut; the 3-month bill used before was only
            % 0.09 below the middle of the range and read as no change.
            r = fomc.data.economyAssessment(tc.D, datetime(2026,10,7));
            tc.verifyEqual([r.nextMeeting.minutesWay, r.nextMeeting.marketWay], ["up", "up"]);
            tc.verifyTrue(startsWith(r.summary, "Next meeting: the minutes and the 6-month bill both point to an increase over the next few meetings."));
            % The word rules read the July minutes' lean to cuts; the AI scored their rate path 0.00,
            % a hold, so the reading says participants expected to hold and markets a cut. The
            % AI missed this one: the next meeting cut.
            r = fomc.data.economyAssessment(tc.D, datetime(2024,8,25));
            tc.verifyEqual([r.nextMeeting.minutesWay, r.nextMeeting.marketWay, r.nextMeeting.ruleWay], ["hold", "down", "down"]);
            tc.verifySubstring(r.summary, "participants expected to hold for now, but the 6-month bill suggests markets expect a cut");
            % February 2026: both point to no change
            r = fomc.data.economyAssessment(tc.D, datetime(2026,2,23));
            tc.verifyEqual([r.nextMeeting.minutesWay, r.nextMeeting.marketWay], ["hold", "hold"]);
            % Near zero a lean to cuts means support by other means: the rate itself holds
            r = fomc.data.economyAssessment(tc.D, datetime(2012,10,1));
            tc.verifyEqual(r.nextMeeting.minutesWay, "hold");
            % The policy rules and the 2-year yield come last, as background
            tc.verifyLessThan(strfind(r.summary, "Background on where policy may go over the next year or two"), ...
                strfind(r.summary, "Policy rules put"));
            tc.verifyLessThan(strfind(r.summary, "Background on where policy may go"), strfind(r.summary, "The 2-year Treasury yield"));
        end

        function theNextMeetingHistoryCountsOnlyMeetingsHeldByThen(tc)
            % Early on few pairs are known; the counts grow with the anchor and add up
            early = fomc.data.economyAssessment(tc.D, datetime(2008,4,1)).nextMeeting.history;
            late = fomc.data.economyAssessment(tc.D, datetime(2026,10,7)).nextMeeting.history;
            heldBy2008 = sum(tc.D.meetings.MeetingDate(2:end) <= datetime(2008,4,1));
            tc.verifyLessThanOrEqual(early.n, heldBy2008);
            tc.verifyGreaterThanOrEqual(late.n, late.raised + late.held + late.cut, "decisions read as unknown are not counted");
            tc.verifyEqual([late.raised, late.held, late.cut], [15, 2, 0], "both up, October 2026");
            r = fomc.data.economyAssessment(tc.D, datetime(2008,4,1));
            tc.verifySubstring(r.summary, "Too few earlier meetings in this data had this pattern to compare.");
        end

        function aQuestionAboutWhatIsLikelyIsAnsweredFromTheReading(tc)
            % August 2024: Qwen3 4B quoted the July minutes' lean toward a cut and still said "No";
            % told then to answer from the minutes alone, it was right, but the minutes' lean is
            % right about the next decision only 69% of the time
            text = fomc.focus.economyPrefetch(context(tc, datetime(2024,8,25)), "Is the Fed likely to cut rates at its next meeting?");
            tc.verifySubstring(text, "answer from the next-meeting reading at the start, and say what it rests on");
            tc.verifyFalse(contains(text, "answer it first from the minutes"));
        end

        function aShouldQuestionIsAnsweredWithWhatParticipantsJudged(tc)
            % July 2022: Qwen3 4B answered "Yes, the Fed should raise rates at the next meeting"
            ctx = context(tc, datetime(2022,7,11));
            text = fomc.focus.economyPrefetch(ctx, "Should the Fed raise rates at the next meeting?");
            tc.verifyTrue(endsWith(text, "begin with what participants judged appropriate, such as ""Participants judged " + ...
                "that further increases would be appropriate"", and cite it.]"));
            text = fomc.focus.economyPrefetch(ctx, "What will the Fed do at the next meeting?");
            tc.verifyFalse(contains(text, "The question asks what the Fed should do"));
        end

        function theModelIsOfferedItAsATool(tc)
            reg = fomc.tools.registry();
            tc.verifyTrue(reg([reg.name] == "assessEconomy").expose);
            ctx = context(tc, datetime(2026,10,7));
            [json, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct());
            tc.verifyTrue(rec.ok);
            tc.verifyEqual(string(jsondecode(json).summary), fomc.data.economyAssessment(tc.D, datetime(2026,10,7)).summary);
        end

        function anEarlierEndDateShowsItAsItStoodThen(tc)
            % As of 2026-10-07, asking for 2024-08-25 gives the July 2024 minutes; a date after the
            % anchor, a bad date or one before the rate data is refused
            ctx = context(tc, datetime(2026,10,7));
            [json, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct("endDate", "2024-08-25"));
            tc.verifyTrue(rec.ok);
            r = jsondecode(json);
            tc.verifyEqual([string(r.anchorDate), string(r.minutes.meetingDate), string(r.minutes.lean)], ...
                ["2024-08-25", "2024-07-31", "cuts"]);
            [json, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct("endDate", "2027-01-01"));
            tc.verifyFalse(rec.ok);
            tc.verifySubstring(json, "after the anchor date");
            [~, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct("endDate", "1989-06-01"));
            tc.verifyFalse(rec.ok);
            [~, rec] = fomc.tools.dispatch(ctx, "assessEconomy", struct("endDate", "last summer"));
            tc.verifyFalse(rec.ok);
        end

        function prefetchOffMeansNoLookup(tc)
            cfg2 = fomc.config(verbose=false, prefetch=false);
            ctx = fomc.context(datetime(2026,10,7), cfg2, tc.D, tracePath=string(tempname) + ".jsonl");
            tc.verifyEqual(fomc.focus.economyPrefetch(ctx, "Should the Fed raise rates at the next meeting?"), "");
        end
    end
end

function ctx = context(tc, asOf)
% Helper: a session context at an anchor date, on the real data
ctx = fomc.context(asOf, tc.cfg, tc.D, tracePath=string(tempname) + ".jsonl");
end
