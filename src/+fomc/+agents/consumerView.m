function r = consumerView(ctx, brief)
%CONSUMERVIEW The consumer view (stage 3): the scorer's direction and what the consumer-impact tool says.
%   r = fomc.agents.consumerView(ctx, brief)
%   Its evidence is the scorer's direction for its meeting and the consumer-impact tool's note (still
%   a stub that says no score exists). The market figures are not repeated: the writer reads the market
%   report itself, and repeating them cost a model call and a longer prompt for nothing new. The
%   sub-agent (fomc.agents.subAgent, prompt in agents/consumer.md) writes what the evidence shows when
%   it is long enough to need it (a future rubric).
%   Replace this file when the consumer rubric is settled, keeping this signature (docs/agents.md).

sc = brief.reports.scorer;
if sc.meetingDate == ""   % no meeting named, so nothing to read
    r = fomc.agents.report("consumer");
    return
end
[json, rec] = fomc.tools.dispatch(ctx, "scoreConsumerImpact", struct("meetingDate", char(sc.meetingDate)));
direction = "Minutes direction for the meeting that ended " + sc.meetingDate + ": " + sc.direction + ".";
tool = jsondecode(json);
note = string(json);
if isfield(tool, "note")
    note = string(tool.note);
end
evidence = strjoin([direction, "Consumer-impact tool: " + note], newline);
r = fomc.agents.subAgent(ctx, brief, "consumer", evidence, rec);
end
