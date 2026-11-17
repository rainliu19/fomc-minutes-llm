function text = cardAnswer(calls)
%CARDANSWER The answer written by code from what the lookups found, for a draft that failed its check.
%   text = fomc.guard.cardAnswer(calls)
%   From the decision card: the action and target range, the vote with the names, and the dissent,
%   each with its paragraph id. Without a card, the best passage found. "" when there is neither.

c = fomc.guard.cardOf(calls);
if ~isempty(c)
    verb = struct("raise", "raised", "cut", "cut", "hold", "held").(c.action);
    text = "At the meeting that ended " + c.meetingDate + " the Committee " + verb + " the target range for the federal funds rate";
    if isfield(c, "targetRange")
        text = text + " (target range " + c.targetRange + ")";
    end
    if isfield(c, "decision")
        text = text + " [" + c.decision.id + "]";
    end
    text = text + ".";
    if isfield(c, "vote")
        if c.vote.unanimous
            how = "The vote was unanimous: ";
        else
            how = "The vote was not unanimous: ";
        end
        text = text + " " + how + c.vote.nFor + " for, " + c.vote.nAgainst + " against. For: " + c.vote.("for") + ".";
        if c.vote.nAgainst > 0
            text = text + " Against: " + c.vote.against + ".";
        end
        text = text + " [" + c.vote.id + "]";
    end
    if isfield(c, "dissent")
        text = text + " " + c.dissent.text + " [" + c.dissent.id + "]";
    end
    return
end
text = "";
for k = 1:numel(calls)
    if string(calls(k).name) == "prefetchPassages" && calls(k).ok
        hits = jsondecode(char(calls(k).result)).hits;
        if ~isempty(hits)
            text = "The minutes say: " + string(hits(1).snippet) + " [" + string(hits(1).id) + "]";
            return
        end
    end
end
end
