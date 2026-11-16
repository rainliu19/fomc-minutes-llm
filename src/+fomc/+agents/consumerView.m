function r = consumerView(ctx, brief)
%CONSUMERVIEW The consumer view (stage 3): a household view from the market figures and the scorer's direction.
%   r = fomc.agents.consumerView(ctx, brief)
%   Its evidence is the market agent's report and the scorer's direction for its meeting, plus
%   the consumer-impact tool's answer (still a stub that says no score exists). The sub-agent
%   (fomc.agents.subAgent, prompt in agents/consumer.md) writes what the evidence shows so far.
%   Replace this file when the consumer rubric is settled, keeping this signature (docs/agents.md).

sc = brief.reports.scorer;
if sc.meetingDate == ""   % no meeting named, so nothing to read
    r = fomc.agents.report("consumer");
    return
end
[json, rec] = fomc.tools.dispatch(ctx, "scoreConsumerImpact", struct("meetingDate", char(sc.meetingDate)));
direction = "Minutes direction for the meeting that ended " + sc.meetingDate + ": " + sc.direction + ".";
evidence = strjoin([brief.reports.market.text, direction, "Consumer-impact tool: " + string(json)], newline);
r = fomc.agents.subAgent(ctx, brief, "consumer", evidence, rec);
end
