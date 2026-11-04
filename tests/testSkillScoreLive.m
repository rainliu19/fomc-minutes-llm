classdef testSkillScoreLive < matlab.unittest.TestCase
    % The scoring skill with the REAL local model: are the scores sensible and stable?
    % Scores go through fomc.skills.scoreByDimension, as chat's do: one model call per
    % dimension, since the one-call scorer's prompt does not fit the local models' window.
    % Opt-in and slow (many model calls). Needs Ollama running with the fomc-qwen3 model.
    %
    %   setenv("FOMC_LIVE", "1"); runtests("tests/testSkillScoreLive.m")
    %
    % Without FOMC_LIVE=1 (as in "buildtool test") every test here is skipped (Incomplete).
    % Each meeting is scored once and reused across tests; the stability test scores again.

    properties
        S          % session at the latest anchor, connected to Ollama
        Cache      % meeting date -> scoreByDimension output (a handle, so it persists across tests)
    end

    properties (Constant)
        StabilityRuns = 3      % scores of the same meeting compared by the stability test
        StabilityTolerance = 0.25
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.assumeEqual(string(getenv("FOMC_LIVE")), "1", ...
                "Live model tests are opt-in: setenv(""FOMC_LIVE"", ""1"").");
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            cfg = fomc.config(verbose=false);
            try
                tags = webread("http://" + cfg.endpoint + "/api/tags", weboptions(Timeout=5));
                names = string({tags.models.name});
            catch
                names = strings(0);
            end
            tc.assumeNotEmpty(names, "Ollama is not running at " + cfg.endpoint + ".");
            tc.assumeTrue(any(startsWith(names, cfg.model)), ...
                "Model " + cfg.model + " is not built (see models/qwen3/Modelfile).");
            D = fomc.data.load();
            tc.S = fomc.newSession(fomc.latestAnchor(D), cfg, Data=D, ...
                TracePath=string(tempname) + ".jsonl");
            tc.Cache = containers.Map();
        end
    end

    methods (Test)
        % --- 1. Basic scoring ---

        function june2022ScoresStronglyHawkish(tc)
            % End to end through the chat router. 75 bp hike with inflation well above target.
            [~, answer, structured] = fomc.runTurn(tc.S, "Score the FOMC minutes for 2022-06-15.");
            tc.Cache("2022-06-15") = structured;
            tc.logResult("2022-06-15", structured);
            tc.verifyTrue(structured.ok, strjoin(structured.issues, " "));
            decoded = jsondecode(answer);
            tc.verifyGreaterThanOrEqual(scoreOf(decoded, "rate_path"), 0.75);
            tc.verifyGreaterThanOrEqual(scoreOf(decoded, "inflation"), 0.5);
        end

        function latestMeetingScores(tc)
            r = fomc.skills.scoreByDimension(tc.S);
            tc.logResult("latest", r);
            tc.verifyTrue(r.ok, strjoin(r.issues, " "));
            M = tc.S.ctx.D.meetings;
            [~, i] = max(M.ReleaseDate(M.ReleaseDate <= tc.S.ctx.asOf));
            tc.verifyEqual(string(r.score.meeting_date), fomc.util.fmtDate(M.MeetingDate(i)));
        end

        % --- 2. rate_path magnitude follows the decision ---

        function ratePathFollowsTheDecision(tc)
            % date, lowest allowed, highest allowed
            cases = { ...
                "2015-12-16",  0.25,  1;      % first hike after years at zero: above 0
                "2019-07-31", -1,    -0.25;   % cut: below 0
                "2024-09-18", -1,    -0.5;    % 50 bp cut: clearly below 0
                "2008-12-16", -1,    -0.75 }; % cut to near zero: near -1
            for i = 1:height(cases)
                [date, lo, hi] = cases{i, :};
                r = tc.scored(date);
                tc.verifyTrue(r.ok, date + ": " + strjoin(r.issues, " "));
                v = scoreOf(r.score, "rate_path");
                tc.verifyGreaterThanOrEqual(v, lo, date + " rate_path");
                tc.verifyLessThanOrEqual(v, hi, date + " rate_path");
            end
        end

        % --- 3. Balance sheet and not_discussed ---

        function march2020EmergencyIsStronglyDovish(tc)
            % Cut to zero plus large asset purchases
            r = tc.scored("2020-03-15");
            tc.verifyTrue(r.ok, strjoin(r.issues, " "));
            tc.verifyLessThanOrEqual(scoreOf(r.score, "rate_path"), -0.75);
            tc.verifyEqual(statusOf(r.score, "balance_sheet"), "scored");
            tc.verifyLessThanOrEqual(scoreOf(r.score, "balance_sheet"), -0.75);
        end

        function endOfQe3ScoresTheBalanceSheet(tc)
            % The Committee ended QE3 purchases: the balance sheet was clearly discussed
            r = tc.scored("2014-10-29");
            tc.verifyTrue(r.ok, strjoin(r.issues, " "));
            tc.verifyEqual(statusOf(r.score, "balance_sheet"), "scored");
        end

        function quietMeetingUsesNotDiscussedCorrectly(tc)
            % Exploratory: logs which dimensions came back not_discussed. Each one must have
            % null score and confidence and no evidence, never a guessed 0.
            r = tc.scored("2019-07-31");
            tc.verifyTrue(r.ok, strjoin(r.issues, " "));
            names = string(fieldnames(r.score.dimensions)).';
            quiet = names(arrayfun(@(n) statusOf(r.score, n) == "not_discussed", names));
            tc.log(1, "2019-07-31 not_discussed: " + strjoin([quiet, "(none)"], ", "));
            for n = quiet
                dim = r.score.dimensions.(n);
                tc.verifyEmpty(dim.score, n + ".score");
                tc.verifyEmpty(dim.confidence, n + ".confidence");
                tc.verifyEmpty(dim.evidence, n + ".evidence");
            end
        end

        % --- 4. Comparisons ---

        function extremesDifferSharply(tc)
            easy = tc.scored("2008-12-16");
            tight = tc.scored("2022-06-15");
            tc.verifyTrue(easy.ok && tight.ok, "both meetings should validate");
            tc.verifyGreaterThanOrEqual(scoreOf(tight.score, "rate_path") - scoreOf(easy.score, "rate_path"), 1, ...
                "rate_path should differ by at least 1 point");
            tc.verifyGreaterThan(meanScore(tight.score), meanScore(easy.score) + 0.5, ...
                "the average stance should be clearly more hawkish in June 2022");
        end

        % --- 7. Stability ---

        function sameMeetingScoresConsistently(tc)
            % Score one meeting several times; each dimension's spread must be at most 0.25
            % and its status (scored / not_discussed) must not change.
            date = "2022-06-15";
            runs = cell(1, tc.StabilityRuns);
            runs{1} = tc.scored(date);
            for k = 2:tc.StabilityRuns
                runs{k} = fomc.skills.scoreByDimension(tc.S, date);
                tc.logResult(date + " run " + k, runs{k});
            end
            for k = 1:numel(runs)
                tc.verifyTrue(runs{k}.ok, "run " + k + ": " + strjoin(runs{k}.issues, " "));
            end
            for n = string(fieldnames(runs{1}.score.dimensions)).'
                statuses = cellfun(@(r) statusOf(r.score, n), runs);
                values = cellfun(@(r) scoreOf(r.score, n), runs);
                tc.log(1, sprintf("%s: %s", n, strjoin(compose("%g", values), ", ")));
                tc.verifyEqual(numel(unique(statuses)), 1, n + " status changed between runs");
                if all(statuses == "scored")
                    tc.verifyLessThanOrEqual(max(values) - min(values), tc.StabilityTolerance, ...
                        n + " moved by more than " + tc.StabilityTolerance + ": " + strjoin(compose("%g", values), ", "));
                end
            end
        end
    end

    methods
        function r = scored(tc, date)
            % Score a meeting once and reuse the result in later tests
            if ~isKey(tc.Cache, date)
                r = fomc.skills.scoreByDimension(tc.S, date);
                tc.Cache(date) = r;
                tc.logResult(date, r);
            end
            r = tc.Cache(date);
        end

        function logResult(tc, label, r)
            parts = strings(0);
            if isfield(r, "score") && isstruct(r.score) && isfield(r.score, "dimensions")
                for n = string(fieldnames(r.score.dimensions)).'
                    parts(end+1) = n + "=" + compose("%g", scoreOf(r.score, n)); %#ok<AGROW>
                end
            end
            tc.log(1, sprintf("%s: ok=%d attempts=%d %s", label, r.ok, r.attempts, strjoin(parts, " ")));
        end
    end
end

function v = scoreOf(score, name)
% The dimension's score, or NaN if missing or not_discussed (so comparisons fail clearly)
v = NaN;
if isstruct(score) && isfield(score, "dimensions") && isfield(score.dimensions, name)
    s = score.dimensions.(name).score;
    if isnumeric(s) && isscalar(s)
        v = double(s);
    end
end
end

function s = statusOf(score, name)
s = "missing";
if isstruct(score) && isfield(score, "dimensions") && isfield(score.dimensions, name) && ...
        isfield(score.dimensions.(name), "status")
    s = string(score.dimensions.(name).status);
end
end

function m = meanScore(score)
names = string(fieldnames(score.dimensions)).';
values = arrayfun(@(n) scoreOf(score, n), names);
m = mean(values(~isnan(values)));
end
