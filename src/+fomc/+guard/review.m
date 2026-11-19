function [answer, cites, warning] = review(answer, s, calls, message, format, structured)
%REVIEW Check a finished answer in code: repair ids, plain words, citations, figures.
%   [answer, cites, warning] = fomc.guard.review(answer, s, calls, message, format, structured)
%   Repairs shortened paragraph ids and puts the text in plain words, builds the cited
%   paragraphs (cites), and chooses a warning for the page, if any: a skill score that was not
%   validated, then figures that appear in no source, then a yes or no (or advice) to a question
%   about the next decision, then missing or unverified citations
%   ("" when all pass). s: the session; calls: the turn's tool-call records; structured: the
%   skill score output or [] . Used by fomc.web.turn and by the critic (fomc.agents.critic),
%   which also runs it on a rewrite, so it is safe to run twice on the same answer.

answer = fomc.guard.expandIds(answer, s.known);
answer = fomc.guard.plainEnglish(answer);
cites = fomc.guard.citations(answer, s.ctx, s.known);
warning = "";
sources = [s.contextBlock; string({calls.result}).'];
if isstruct(structured) && isscalar(structured) && isfield(structured, "skill")
    if ~isfield(structured, "ok") || ~structured.ok
        warning = "FOMC skill score was not validated. Issues: " + ...
            strjoin(string(structured.issues), " ") + ...
            ". Failed dimensions: " + strjoin(string(structured.failedDimensions), ", ") + ...
            ". Do not rely on it as verified.";
    end
    return
end
badFigures = fomc.guard.checkFigures(answer, sources);
if ~isempty(badFigures)
    warning = "Check these figures against the minutes, they do not appear in the sources: " + ...
        strjoin(badFigures, "; ") + ".";
elseif format == "chat" && fomc.focus.asksNextMove(lower(message)) && ...
        ~isempty(regexp(answer, "^\W*(yes|no)(?![a-z])|^[^.]*(?<![a-z])(the fed|the committee|fomc) should(?![a-z])", "once", "ignorecase"))
    warning = "The answer says yes or no, or what the Fed should do. The minutes only show what participants expected, so say that.";
elseif format == "chat" && ~any(string({calls.name}) == "prefetchNotice") && ...
        (fomc.focus.aboutMinutes(message) || asksEffectsWithIds(message, calls))
    if isempty(cites) || ~any([cites.ok])
        warning = "This answer cites no paragraph from the minutes. Treat it as unverified.";
    elseif ~all([cites.ok])
        warning = "Some citations could not be verified.";
    end
end
end

function tf = asksEffectsWithIds(message, calls)
% A question about what the rate path means ahead, when the lookups gave paragraphs to cite (the staff outlook)
tf = fomc.focus.asksEffectsAhead(lower(message)) && ~isempty(fomc.guard.idsIn(string({calls.result})));
end
