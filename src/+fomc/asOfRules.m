function t = asOfRules()
%ASOFRULES The point-in-time rules the model reads, from agents/shared/asof.md (read once and kept).
%   t = fomc.asOfRules()
%   One file feeds the writer's system prompt (rule 8), each specialist's prompt and, with
%   fomc.anchorLine, the date line of the first message, so a change to the wording is made once.
%   The file is not under agents/*.md or agents/<name>/, so fomc.agents.catalog does not take it for an agent.

persistent cached
if isempty(cached)
    cached = strip(string(fileread(fullfile(fileparts(fomc.skills.root()), "agents", "shared", "asof.md"))));
end
t = cached;
end
