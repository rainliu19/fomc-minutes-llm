function [s, structured] = structure(s, calls)
%STRUCTURE Write the structured analysis from the conversation and check it.
%   [s, structured] = fomc.analysis.structure(s, calls)
%
%   One model call (no tools, JSON schema) after the tool loop. The model cites paragraph
%   ids; fomc.guard.checkGrounding checks them and the figures, and the harness fills in
%   each paragraph's exact text. A failed check goes back to the model once; if it still
%   fails, the result has groundingOk false and the failures listed.

% Set up and give the model its instruction
ctx = s.ctx;
schema = fomc.analysis.schema();
maxAttempts = 2;

instruction = "Now write your findings as the required JSON, in under 250 tokens. " + ...
    "evidence: 1 to 4 items, each a claim plus the id of the paragraph that supports it, taken from a tool result. " + ...
    "dataCited: at most 4 figures from the data above or a tool, with series id and observation date. " + ...
    "summary: at most 80 words, only what the cited paragraphs say; give no reason for the decision unless a cited paragraph does. Put gaps in caveats. " + ...
    "Use only information available on " + fomc.util.fmtDate(ctx.asOf) + ".";
s.history = addUserMessage(s.history, instruction);

% Ask for the JSON, check it, and on failure ask once more with the problems listed
structured = [];
failures = strings(0, 1);
for attempt = 1:maxAttempts
    t0 = tic;
    % One model call with the JSON schema (no tools)
    [text, ~, stats] = s.llm(s.history, false, schema);
    content = string(text);
    structured = [];
    failures = strings(0, 1);
    % Read the reply as JSON
    try
        structured = jsondecode(content);
    catch
        failures = "The reply was not valid JSON for the required schema.";
    end
    % If it is valid JSON, check the cited ids and figures
    if isempty(failures)
        g = fomc.guard.checkGrounding(structured, ctx, calls, s.known);
        failures = g.failures;
    end
    fomc.trace.logEvent(ctx, "grounding_check", struct("attempt", attempt, ...
        "ok", isempty(failures), "failures", failures, "reply", content, ...
        "ms", round(toc(t0) * 1000), "stats", stats));

    if strlength(content) == 0
        content = "(empty)";
    end
    s.history = addResponseMessage(s.history, struct("role", "assistant", "content", content));
    % Passed: add the anchor date, the exact quotes, and the stance from the decision card
    if isempty(failures) || attempt == maxAttempts
        break
    end
    s.history = addUserMessage(s.history, "That did not pass the checks: " + strjoin(failures, " ") + ...
        " Write the JSON again and fix only these problems.");
end

% Make sure we always return a struct
if isempty(structured) || ~isstruct(structured)
    structured = struct();
end
if isempty(failures)
    structured.anchorDate = fomc.util.fmtDate(ctx.asOf);
    structured.evidence = withQuotes(structured.evidence, ctx);
    structured = stanceFromCard(structured, ctx);
end
% Record whether it passed, and the failures if not
structured.groundingOk = isempty(failures);
if ~isempty(failures)
    structured.groundingFailures = failures;
end
end

function structured = stanceFromCard(structured, ctx)
% Stance comes from the decision card (cut = easing, raise = tightening, hold = neutral);
% a small model mislabeled a cut.
% Find the meeting and map its action to a stance
d = fomc.util.parseDate(structured.meetingDate);
M = ctx.D.meetings;
k = find(M.MeetingDate == d & M.ReleaseDate <= ctx.asOf, 1);
if isempty(k)
    return
end
switch ctx.D.cards.action(k)
    case "cut",   stance = "easing";
    case "raise", stance = "tightening";
    case "hold",  stance = "neutral";
    otherwise,    return
end
structured.policyStance = stance;
structured.policyStanceSource = "decision card";
end

function out = withQuotes(evidence, ctx)
% Add the exact paragraph text, meeting and section to each cited id.
% Look up each cited id and attach the meeting, section and exact text
items = fomc.util.asCell(evidence);
out = cell(size(items));
for i = 1:numel(items)
    e = items{i};
    r = fomc.guard.resolveId(ctx, e.id);
    e.meetingDate = r.meetingDate;
    e.section = r.section;
    e.paragraph = r.paragraph;
    e.quote = r.text;
    out{i} = e;
end
end
