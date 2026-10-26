function reg = registry()
%REGISTRY The tools: name, implementation, schema, and whether the model is offered it.
%   reg = fomc.tools.registry(): struct array with name, fn (f(ctx, args) returning a
%   struct), tool (openAIFunction) and expose (false for getSnapshot, which the harness
%   runs, keeping the prompt small).
%   Descriptions are short because the model reads them on every call. The anchor date is
%   never a parameter; the harness holds it.

% Build the list once and reuse it
persistent cached
if ~isempty(cached)
    reg = cached;
    return
end

% Allowed values for the section and group parameters
S = fomc.data.sections();
sections = S.name(S.name ~= "body").';
G = fomc.data.coreGroups();
groups = [unique(G.group, "stable"); "all"];

% One entry per tool: name, function, the schema the model sees, and whether the model is offered it
specs = {};

t = openAIFunction("listMeetings", ...
    "List meetings with released minutes, newest first, with meeting and release dates. Covers the focus window given with the question unless you pass dates.");
t = addParameter(t, "n", "type", "integer", "description", "How many, 1 to 50. Default 30.", RequiredParameter=false);
t = addParameter(t, "startDate", "type", "string", "description", "YYYY-MM-DD.", RequiredParameter=false);
t = addParameter(t, "endDate", "type", "string", "description", "YYYY-MM-DD.", RequiredParameter=false);
specs{end+1} = {"listMeetings", @fomc.tools.listMeetings, t, true};

t = openAIFunction("getDecision", ...
    "What the Committee decided at one meeting: raise, cut or hold, the target range, the vote and any dissent with reasons. Use this first for any question about a decision or vote.");
t = addParameter(t, "meetingDate", "type", "string", "description", "Last day of the meeting, YYYY-MM-DD, from listMeetings.");
specs{end+1} = {"getDecision", @fomc.tools.getDecision, t, true};

t = openAIFunction("searchMinutes", ...
    "Find paragraphs in the minutes mentioning a word or phrase, newest first, each with an id. Matches words, not meaning, so try several wordings. Searches the focus window unless you pass dates.");
t = addParameter(t, "query", "type", "string", "description", "A short phrase such as 'balance sheet runoff'. Use | for alternatives: 'tariff|trade policy'.");
t = addParameter(t, "startDate", "type", "string", "description", "YYYY-MM-DD.", RequiredParameter=false);
t = addParameter(t, "endDate", "type", "string", "description", "YYYY-MM-DD.", RequiredParameter=false);
t = addParameter(t, "maxResults", "type", "integer", "description", "1 to 20. Default 5.", RequiredParameter=false);
specs{end+1} = {"searchMinutes", @fomc.tools.searchMinutes, t, true};

t = openAIFunction("readMinutes", ...
    "Read paragraphs of one section of one meeting's minutes, a page at a time, each with an id. Use it to read around a search hit.");
t = addParameter(t, "meetingDate", "type", "string", "description", "Last day of the meeting, YYYY-MM-DD.");
t = addParameter(t, "section", "type", "string", "enum", sections, "description", ...
    "participantsViews is the Committee's discussion and risks.");
t = addParameter(t, "startParagraph", "type", "integer", "description", ...
    "Paragraph number to start from (a hit's paragraph, or nextParagraph). Default 1.", RequiredParameter=false);
specs{end+1} = {"readMinutes", @fomc.tools.readMinutes, t, true};

t = openAIFunction("getSeries", ...
    "History of up to 5 data series as known on the anchor date, including revisions as first published.");
t = addParameter(t, "seriesIds", "type", "string", "description", "Ids separated by commas, 1 to 5, such as 'UNRATE,PAYEMS'.");
t = addParameter(t, "startDate", "type", "string", "description", "YYYY-MM-DD. If omitted, the latest 24 observations.", RequiredParameter=false);
t = addParameter(t, "endDate", "type", "string", "description", "YYYY-MM-DD.", RequiredParameter=false);
t = addParameter(t, "transform", "type", "string", "enum", ["level","diff_1","yoy_pct"], "description", ...
    "yoy_pct is the percent change from a year earlier, best for price indexes and activity. Default level.", RequiredParameter=false);
specs{end+1} = {"getSeries", @fomc.tools.getSeries, t, true};

t = openAIFunction("describeSeries", ...
    "What a data series measures, its units, and how long after its period each value becomes public.");
t = addParameter(t, "seriesId", "type", "string", "description", "Series id such as UNRATE or DGS10.");
specs{end+1} = {"describeSeries", @fomc.tools.describeSeries, t, true};

t = openAIFunction("scoreConsumerImpact", ...
    "Rubric score of whether one meeting's direction is positive or negative for the US consumer. Only when the user asks about consumer impact.");
t = addParameter(t, "meetingDate", "type", "string", "description", "Last day of the meeting, YYYY-MM-DD.");
specs{end+1} = {"scoreConsumerImpact", @fomc.tools.scoreConsumerImpact, t, true};

t = openAIFunction("readSkill", ...
    "Load instructions or a reference file for a skill. Call with name alone for SKILL.md; pass file for a referenced file, such as rubric/inflation.md.");
t = addParameter(t, "name", "type", "string", "description", "Skill name, such as fomc-score.");
t = addParameter(t, "file", "type", "string", "description", ...
    "Optional relative path inside the skill, such as rubric/inflation.md.", RequiredParameter=false);
specs{end+1} = {"readSkill", @fomc.tools.readSkill, t, true};

t = openAIFunction("getSnapshot", "Latest known value of the core series (run by the harness).");
t = addParameter(t, "group", "type", "string", "enum", groups.', "description", "Which group. Default all.", RequiredParameter=false);
specs{end+1} = {"getSnapshot", @fomc.tools.getSnapshot, t, false};

% Turn the list into a struct array
reg = struct("name", cellfun(@(s) string(s{1}), specs, UniformOutput=false), ...
    "fn", cellfun(@(s) s{2}, specs, UniformOutput=false), ...
    "tool", cellfun(@(s) s{3}, specs, UniformOutput=false), ...
    "expose", cellfun(@(s) s{4}, specs, UniformOutput=false));
cached = reg;
end
