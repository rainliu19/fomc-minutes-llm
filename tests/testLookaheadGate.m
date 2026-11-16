classdef testLookaheadGate < matlab.unittest.TestCase
    % The data side of look-ahead bias, on REAL data, no model: for anchors across 2008 to 2026, no tool result and
    % no session text carries a date after the anchor, and the fixed texts the model reads (system prompt, tool
    % descriptions, agent and skill files) name no year from 2008 on, since a fixed year is later than some anchor.
    % What the model remembers from its training is not tested here (tests/bench_lookahead.py measures it).

    properties
        D
        cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
            tc.D = fomc.data.load();
            tc.cfg = fomc.config(verbose=false);
        end
    end

    methods (Test)
        function theFixedTextsTheModelReadsNameNoYearFrom2008On(tc)
            % The prompt's id example is the first meeting, before every anchor (the first release is 2008-02-20)
            texts = fixedTexts();
            first = min(tc.D.meetings.ReleaseDate);
            for name = fieldnames(texts).'
                body = erase(texts.(name{1}), regexp(texts.(name{1}), "(?<!\d)\d{4}-\d{2}-\d{2}(?!\d)", "match"));
                kept = laterDates(texts.(name{1}), first);       % ISO dates after the first release
                tc.verifyEmpty([regexp(body, YEAR, "match") kept], "year in " + name{1});
            end
        end

        function noToolResultCarriesALaterDate(tc)
            anchors = datetime([2008 3 1; 2009 6 1; 2011 1 15; 2013 3 10; 2015 5 20; 2017 3 1; 2018 10 1; ...
                2019 10 15; 2020 6 1; 2022 3 1; 2023 9 1; 2025 2 1]);
            wide = struct("endDate", "2030-12-31", "startDate", "1990-01-01");
            for asOf = anchors.'
                ctx = fomc.context(asOf, tc.cfg, tc.D);
                calls = {"listMeetings", struct("n", 50, "endDate", wide.endDate)
                    "searchMinutes", struct("query", "inflation labor market policy", "endDate", wide.endDate, "maxResults", 10)
                    "searchMinutes", struct("query", "federal funds rate target range decision")
                    "getPolicyPath", wide
                    "getOutlook", struct("endDate", wide.endDate)
                    "assessEconomy", struct("endDate", wide.endDate)
                    "getSeries", struct("seriesIds", "UNRATE,CPIAUCSL,PCEPILFE,GDPC1,PAYEMS", "startDate", wide.startDate, "endDate", wide.endDate)};
                for k = 1:size(calls, 1)
                    json = fomc.tools.dispatch(ctx, calls{k, 1}, calls{k, 2});
                    tc.verifyEmpty(setdiff(laterDates(json, asOf), laterDates(jsonencode(calls{k, 2}), asOf)), calls{k, 1} + " as of " + string(asOf, "yyyy-MM-dd"));
                end
                % the first message of a session: the data brief the model reads before any question
                tc.verifyEmpty(laterDates(fomc.contextBlock(ctx, fomc.dataBrief(ctx)), asOf), "context block as of " + string(asOf, "yyyy-MM-dd"));
            end
        end

        function theAsOfRulesReachTheWriterTheContextAndTheSpecialists(tc)
            rules = fomc.asOfRules();
            tc.verifyNotEmpty(rules);
            tc.verifySubstring(fomc.systemPrompt(), rules);
            ctx = fomc.context(datetime(2020,3,1), tc.cfg, syntheticData());
            tc.verifySubstring(fomc.contextBlock(ctx, "x"), "nothing after it is known");
            tc.verifySubstring(string(fomc.anchorLine(datetime(2020,3,1))), "nothing after it is known");
            % a specialist's own prompt: the body of its file, then these rules
            box = containers.Map();
            m = fomc.llm.Mock({struct("content", "Summary.")});
            brief = struct("question", "What is the market doing?", "isAnalysis", false, "llmFor", @(cfg, prompt, tools) remember(box, prompt, m));
            cfg = fomc.config(verbose=false);
            fomc.agents.subAgent(fomc.context(datetime(2020,3,1), cfg, syntheticData()), brief, "market", string(repmat('x', 1, 60000)), struct([]));
            tc.verifySubstring(string(box("prompt")), rules);
        end
    end
end

function f = remember(box, prompt, m)
% A model factory that keeps the prompt it was given
box("prompt") = prompt;
f = @m.call;
end

function re = YEAR()
re = "(?<!\d)(200[89]|20[12]\d|203\d)(?!\d)";
end

function texts = fixedTexts()
% Everything fixed the model reads, by name: the prompt, each tool's description, the agent and skill files
texts = struct("systemPrompt", fomc.systemPrompt());
reg = fomc.tools.registry();
for t = reg(:).'
    s = string(t.tool.Description);
    for p = string(fieldnames(t.tool.Parameters)).'
        s = s + " " + string(t.tool.Parameters.(p).description);
    end
    texts.("tool_" + t.name) = s;
end
cat = fomc.agents.catalog();
for a = cat(:).'
    texts.("agent_" + a.name) = a.body + " " + strjoin(string(struct2cell(a.pages)), " ");
end
root = fullfile(fileparts(fomc.skills.root()), "skills");
for f = dir(fullfile(root, "**", "*.md")).'
    texts.("skill_" + matlab.lang.makeValidName(f.name) + "_" + numel(fieldnames(texts))) = string(fileread(fullfile(f.folder, f.name)));
end
end

function bad = laterDates(text, asOf)
% ISO dates in the text that are after the anchor
d = regexp(string(text), "(?<!\d)\d{4}-\d{2}-\d{2}(?!\d)", "match");
bad = strings(1, 0);
for x = d
    v = datetime(x, InputFormat="yyyy-MM-dd", TimeZone="");
    if ~isnat(v) && v > asOf
        bad(end+1) = x; %#ok<AGROW>
    end
end
end
