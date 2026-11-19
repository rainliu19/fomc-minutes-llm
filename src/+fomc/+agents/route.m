function [stages, name] = route(question)
%ROUTE Which agents run for a question, in stages, chosen by code.
%   [stages, name] = fomc.agents.route(question)
%   stages: a cell array, one struct array of agents (fomc.agents.catalog entries) per stage,
%   in the order set by the stages line of agents/organizer.md. name: "score", "household" or
%   "other" (see that file for what each runs). The triggers are the harness's own
%   (fomc.focus.wantsScoring, fomc.focus.asksEffectsAhead), so the same questions get the same
%   lookups. A model could choose here later, when the code rules find nothing.

c = fomc.agents.catalog();
order = cellfun(@(g) strip(split(g, "+")).', strip(split(c([c.name] == "organizer").stages, ">")), UniformOutput=false);
if fomc.focus.wantsScoring(question)
    name = "score";
    order = {"scorer"};
elseif fomc.focus.asksEffectsAhead(lower(question))
    name = "household";
else
    name = "other";
    order = order(1);
end
% Keep the agents in the order the stages line gives (the writer sees their texts in that order)
stages = cellfun(@(n) c(cellfun(@(x) find([c.name] == x), cellstr(n))), order, UniformOutput=false);
end
