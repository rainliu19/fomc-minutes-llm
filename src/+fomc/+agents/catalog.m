function c = catalog()
%CATALOG The agents: name, description, tools, stages, summarizeOver, body, pages and function, from agents/*.md.
%   c = fomc.agents.catalog()
%   Read once and kept. summarizeOver: the agent's own evidence length below which its model is not
%   called (NaN: use cfg.agentSummarizeOver). pages: the topic pages in agents/<name>/*.md, a struct of
%   text by file name (the agent's prompt is its body plus the page for the question's topic).
%   The function of each specialist is named here in code, not in the md files, so a compiled app
%   (MATLAB Compiler) can find it. organizer has no function.

persistent cached
if ~isempty(cached)
    c = cached;
    return
end
fns = struct("minutes", @fomc.agents.minutesRetriever, "market", @fomc.agents.marketData, ...
    "scorer", @fomc.agents.rubricScorer, "consumer", @fomc.agents.consumerView);
folder = fullfile(fileparts(fomc.skills.root()), "agents");
files = dir(fullfile(folder, "*.md"));
c = struct("name", {}, "description", {}, "tools", {}, "stages", {}, "summarizeOver", {}, "body", {}, "pages", {}, "fn", {});
for i = 1:numel(files)
    file = string(fullfile(folder, files(i).name));
    m = fomc.skills.parseFrontmatter(file, Keys=["tools" "stages" "summarizeOver"]);
    body = extractAfter(extractAfter(string(fileread(file)), "---" + newline), newline + "---" + newline);
    fn = [];
    if isfield(fns, m.name)
        fn = fns.(m.name);
    end
    pages = struct();
    for p = dir(fullfile(folder, m.name, "*.md")).'
        pages.(erase(p.name, ".md")) = strip(string(fileread(fullfile(p.folder, p.name))));
    end
    c(end+1) = struct("name", m.name, "description", m.description, "tools", strip(split(m.tools, ",")).', ...
        "stages", m.stages, "summarizeOver", str2double(m.summarizeOver), "body", body, "pages", pages, "fn", fn); %#ok<AGROW>
end
cached = c;
end
