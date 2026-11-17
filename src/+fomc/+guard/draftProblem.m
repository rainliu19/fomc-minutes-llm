function problem = draftProblem(answer, calls, message)
%DRAFTPROBLEM A draft that cannot stand, found in code: no words, or a fact the decision card contradicts.
%   problem = fomc.guard.draftProblem(answer, calls, message)
%   "" when the draft is usable. Checks, in order: the answer is only paragraph ids or empty (a bare
%   "[2022-06-15/policyAction/3]", an empty reply, "(The model returned no text.)"); then, when a
%   getDecision card was looked up, the vote (unanimous or not) and the direction (raise, cut,
%   hold) against the card, a decision answer with no figure or no direction, and a vote question
%   answered without saying unanimous or naming a dissenter. The critic uses the text
%   as the rewrite request and, if the rewrite fails too, answers from the card (fomc.guard.cardAnswer).

answer = string(answer);
text = regexprep(answer, "\[[^\]]*\]", " ");
% Only ids, nothing, or the writer's "no text" marker (a short plain reply such as "Yes." is left alone)
if contains(answer, "returned no text") || (numel(regexp(text, "[A-Za-z0-9]+", "match")) < 3 && (answer == "" || contains(answer, "[")))
    problem = "The answer has no sentence, only a paragraph id or too few words. Write one or two plain sentences that state the fact, then cite its id after the claim.";
    return
end
% The lookup text, the critic's own request or a list of ids copied back instead of an answer
if ~isempty(regexp(answer, "ANCHOR DATE:|SEARCH MEETINGS|Decision card for the meeting|copy it exactly as written|Rewrite the answer to fix|A checker found a problem|The answer (repeats|has no)", "once")) || ...
        any(strlength(regexp(answer, "\[[^\]]*\]", "match")) > 200)
    problem = "The answer repeats the lookup text instead of answering. Write one or two plain sentences that answer the question, then cite the id after the claim.";
    return
end
c = fomc.guard.cardOf(calls);
problem = "";
if isempty(c)
    return
end
neg = "(?i)(not|n't)\W+(\w+\W+){0,2}unanimous";
claimsUnanimous = ~isempty(regexp(text, "(?i)(?<![a-z])unanimous", "once")) && isempty(regexp(text, neg, "once"));
claimsSplit = ~isempty(regexp(text, neg, "once"));
if isfield(c, "vote") && c.vote.unanimous && claimsSplit
    problem = "The decision card says the vote was unanimous (" + c.vote.nFor + " for, 0 against), but the answer says it was not.";
elseif isfield(c, "vote") && ~c.vote.unanimous && claimsUnanimous
    problem = "The decision card says the vote was not unanimous (" + c.vote.nFor + " for, " + c.vote.nAgainst + " against), but the answer says it was unanimous.";
elseif ~isempty(regexp(text, "(?i)(are|is|were) not (yet )?(available|public|known|released)|not (available|public|known) yet", "once"))
    problem = "The minutes for this meeting are available: the decision card has its facts. Answer from the decision card" + rangeOf(c) + ".";
elseif wrongDirection(text, c)
    problem = "The decision card says the Committee " + c.action + " the target range" + rangeOf(c) + ", but the answer says otherwise.";
elseif isfield(c, "targetRange") && isempty(regexp(text, "\d", "once"))
    problem = "The answer gives no figure. State the target range from the decision card" + rangeOf(c) + ".";
elseif wrongRange(text, c)
    problem = "The answer states a target range that is not the decision card's. The card says" + rangeOf(c) + "; use exactly those figures.";
else
    problem = voteProblem(text, c, lower(string(message)));
end
end

function problem = voteProblem(text, c, q)
% A question about the vote must be answered with the vote: unanimous, or who voted against
problem = "";
if ~isfield(c, "vote") || isempty(regexp(q, "(?<![a-z])(unanimous\w*|vote\w*|dissent\w*|voted against)", "once"))
    return
end
if c.vote.unanimous
    if isempty(regexp(text, "(?i)unanimous|no dissent|all (voted|members)", "once"))
        problem = "The question is about the vote. The decision card says it was unanimous (" + c.vote.nFor + " for, 0 against); say so.";
    end
else
    names = strip(split(string(c.vote.against), ","));
    if ~any(contains(text, names(names ~= ""), IgnoreCase=true))
        problem = "The question is about the vote. The decision card says it was not unanimous: " + c.vote.nFor + " for, " + c.vote.nAgainst + " against (" + c.vote.against + "). Name who voted against, with the name as written there.";
    end
end
end

function tf = wrongRange(text, c)
% The answer quotes quarter-point figures (1-3/4, 4.25) and none of them is one of the card's range ends. An answer that
% also names the earlier range ("up from 4-1/2 to 4-3/4") keeps the card's end among its figures, so it passes.
tf = false;
if ~isfield(c, "targetRange")
    return
end
want = quarters(c.targetRange);
said = quarters(text);
tf = ~isempty(want) && ~isempty(said) && ~any(ismember(said, want));
end

function v = quarters(t)
% Figures such as 1-3/4 (en dashes too), 1 3/4, 3/4, 1.75 as numbers; whole numbers are left out (years, counts, "2 percent inflation")
t = regexprep(string(t), "[" + char(8211) + char(8212) + "]", "-");
parts = regexp(t, "\d+-\d+/\d+|\d+ \d+/\d+|\d+/\d+|\d+\.(?:25|5|75)(?!\d)", "match");
v = zeros(1, numel(parts));
for k = 1:numel(parts)
    q = str2double(regexp(parts(k), "\d+", "match"));
    if contains(parts(k), ".")
        v(k) = str2double(parts(k));
    elseif numel(q) == 2
        v(k) = q(1) / q(2);
    else
        v(k) = q(1) + q(2) / q(3);
    end
end
end

function tf = wrongDirection(text, c)
% The answer names a direction and none of them is the card's
words = struct("raise", "(?<![a-z])(rais|increas|hik)", "cut", "(?<![a-z])(lower|cut|reduc|decreas)", "hold", "(?<![a-z])(maintain|held|hold|unchanged|no change|steady)");
names = fieldnames(words);
named = false(size(names));
for k = 1:numel(names)
    named(k) = ~isempty(regexp(text, words.(names{k}), "once", "ignorecase"));
end
tf = any(named) && ~any(named & strcmp(names, c.action));
end

function t = rangeOf(c)
t = "";
if isfield(c, "targetRange")
    t = " (" + c.targetRange + ")";
end
end
