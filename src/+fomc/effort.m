function [cfg, format] = effort(cfg, level)
%EFFORT Settings for a reasoning-effort level: "low", "medium" or "high".
%   [cfg, format] = fomc.effort(cfg, level)
%   The model has no thinking switch, so effort is how much work the agent does:
%     low     short answer, 3 passages looked up first (about 12 s)
%     medium  longer answer, 5 passages, more tool rounds
%     high    medium plus the structured analysis with quote and figure checks (format "analysis")
%   Only the settings below change; everything else in cfg is kept.

arguments
    cfg (1,1) struct
    level (1,1) string {mustBeMember(level, ["low", "medium", "high"])}
end

d = fomc.config();
switch level
    case "low"
        cfg.maxTokens = d.maxTokens;
        cfg.maxToolRounds = d.maxToolRounds;
        cfg.prefetchHits = d.prefetchHits;
    otherwise
        cfg.maxTokens = 700;
        cfg.maxToolRounds = 10;
        cfg.prefetchHits = 5;
end
format = "chat";
if level == "high"
    format = "analysis";
end
end
