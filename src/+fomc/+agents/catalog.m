function c = catalog()
%CATALOG The agents: name, description, tools, stages, body and function, from agents/*.md.
%   c = fomc.agents.catalog()
%   Read once and kept. The function of each specialist is named here in code, not in the md
%   files, so a compiled app (MATLAB Compiler) can find it. organizer has no function.

persistent cached
if ~isempty(cached)
    c = cached;
    return
end
fns = struct("minutes", @fomc.agents.minutesRetriever, "market", @fomc.agents.marketData, ...
    "scorer", @fomc.agents.rubricScorer, "consumer", @fomc.agents.consumerView);
folder = fullfile(fileparts(fomc.skills.root()), "agents");
files = dir(fullfile(folder, "*.md"));
c = struct("name", {}, "description", {}, "tools", {}, "stages", {}, "body", {}, "fn", {});
for i = 1:numel(files)
    file = string(fullfile(folder, files(i).name));
    m = fomc.skills.parseFrontmatter(file, Keys=["tools" "stages"]);
    body = extractAfter(extractAfter(string(fileread(file)), "---" + newline), newline + "---" + newline);
    fn = [];
    if isfield(fns, m.name)
        fn = fns.(m.name);
    end
    c(end+1) = struct("name", m.name, "description", m.description, ...
        "tools", strip(split(m.tools, ",")).', "stages", m.stages, "body", body, "fn", fn); %#ok<AGROW>
end
cached = c;
end
