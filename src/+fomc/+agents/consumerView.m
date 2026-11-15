function r = consumerView(ctx, brief)
%CONSUMERVIEW The consumer view (stage 3).
%   r = fomc.agents.consumerView(ctx, brief)
%   Today it passes on the consumer-impact tool for the meeting the scorer named, which is
%   still a stub that says no score exists. The household figures come from the market agent's
%   report, which the writer already has. To replace this agent keep this signature and read
%   brief.reports.market and brief.reports.scorer (meetingDate, direction); the contract is
%   in docs/agents.md.

if brief.reports.scorer.meetingDate == ""   % no meeting named, so nothing to read
    r = fomc.agents.report("consumer");
    return
end
[json, rec] = fomc.tools.dispatch(ctx, "scoreConsumerImpact", struct("meetingDate", char(brief.reports.scorer.meetingDate)));
x = jsondecode(json);
if ~rec.ok
    r = fomc.agents.report("consumer", ok=false, calls=rec, error=string(x.error));
elseif isfield(x, "note")
    r = fomc.agents.report("consumer", calls=rec, text="[" + string(x.note) + "]");
else
    r = fomc.agents.report("consumer", calls=rec, text="[Consumer impact of the meeting that ended " + ...
        x.meetingDate + " from the rubric: " + x.direction + ".]");
end
end
