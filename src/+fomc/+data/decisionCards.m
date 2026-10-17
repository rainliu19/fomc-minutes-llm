function cards = decisionCards(minutes, paras)
%DECISIONCARDS Each meeting's decision, read from the text by pattern matching.
%   cards = fomc.data.decisionCards(minutes, paras): one row per meeting with
%     action ("raise", "cut", "hold", "unknown"), targetRange ("1-1/2 to 1-3/4 percent"),
%     change ("by 1/4 percentage point"), decisionText (verbatim sentence), decisionId,
%     votesFor, votesAgainst, nFor, nAgainst (counted by code), unanimous, voteId,
%     dissentText, dissentId.
%   No model. Tests check the cards against the actual rate change for every meeting.

% One output column per field, one row per meeting
n = height(minutes);
action = repmat("unknown", n, 1);
targetRange = strings(n, 1); change = strings(n, 1);
decisionText = strings(n, 1); decisionId = strings(n, 1);
votesFor = strings(n, 1); votesAgainst = strings(n, 1); voteId = strings(n, 1);
nFor = zeros(n, 1); nAgainst = zeros(n, 1);
unanimous = false(n, 1);
dissentText = strings(n, 1); dissentId = strings(n, 1);

% MATLAB patterns read \b as backspace, so word edges are written as lookarounds
% For each meeting: find the decision sentence in its policy action section
for i = 1:n
    P = paras(paras.meetingIdx == i & paras.section == "policyAction", :);
    % What was done to the rate, and which sentence says so
    [action(i), decisionText(i), decisionId(i)] = findDecision(P);
    % Pull the target range and the size of the change out of that sentence
    if decisionText(i) ~= ""
        [targetRange(i), change(i)] = targetAndChange(decisionText(i));
    end
    % Read the vote lines: who voted for, who voted against, and counts
    for k = 1:height(P)
        text = P.text(k);
        if startsWith(text, ["Voting for this action", "Votes for this action"], IgnoreCase=true)
            votesFor(i) = afterColon(text);
            nFor(i) = countNames(votesFor(i));
        elseif startsWith(text, ["Voting against this action", "Votes against this action"], IgnoreCase=true)
            votesAgainst(i) = afterColon(text);
            nAgainst(i) = countNames(votesAgainst(i));
            voteId(i) = P.id(k);
            unanimous(i) = startsWith(lower(votesAgainst(i)), "none");
            % Not unanimous: the paragraphs right after the vote say what the dissenters preferred
            if ~unanimous(i)
                % The paragraphs right after the vote say what the dissenters preferred
                parts = strings(0, 1);
                for j = k+1:min(k+3, height(P))
                    if contains(P.text(j), ["voted against", "preferred", "dissent"], IgnoreCase=true)
                        parts(end+1, 1) = P.text(j); %#ok<AGROW>
                        if dissentId(i) == "", dissentId(i) = P.id(j); end
                    end
                end
                dissentText(i) = clip(strjoin(parts, " "), 900);
            end
        end
    end
end
% Put the columns together as the card table
cards = table(action, targetRange, change, decisionText, decisionId, votesFor, votesAgainst, ...
    nFor, nAgainst, unanimous, voteId, dissentText, dissentId);
end

function [action, sentence, id] = findDecision(P)
% The sentence stating what was done to the rate target. Pass 1: an explicit raise or cut.
% Pass 2: hold wording (maintain, keep, leave, reaffirm).
% Two passes over the sentences: first an explicit raise or cut, then hold wording
% A sentence counts only if it is about the rate target
action = "unknown"; sentence = ""; id = "";
% Patterns: "decided to raise/lower the target...", and hold words such as maintain
move = "(?i)(?<![A-Za-z])(?:decided|agreed|voted)(?:\s+today)?\s+to\s+(?:\w+ly\s+)?(raise|increase|lower|reduce|decrease|cut|establish)\s+(?:the\s+|its\s+|a\s+)?(?:target|federal)";
hold = "(?i)(?<![A-Za-z])(maintain|keep|leave|reaffirm)\w*(?![A-Za-z])";
% Go through each paragraph and sentence; stop at the first match
for pass = 1:2
    for k = 1:height(P)
        for sentence_ = splitSentences(P.text(k)).'
            if ~isRateSentence(sentence_)
                continue
            end
            if pass == 1
                tok = regexp(sentence_, move, "tokens", "once");
                if ~isempty(tok)
                    action = classify(tok{1}); sentence = sentence_; id = P.id(k);
                    return
                end
            elseif ~isempty(regexp(sentence_, hold, "once")) && ...
                    isempty(regexp(sentence_, "(?i)(?<![A-Za-z])(raise|increase|lower|reduce|decrease|cut)(?![A-Za-z])", "once"))
                action = "hold"; sentence = sentence_; id = P.id(k);
                return
            end
        end
    end
end
end

function tf = isRateSentence(s)
% About the rate target, not the balance sheet.
% True if the sentence mentions the rate target and not purchases or holdings
tf = contains(s, ["target range", "target for the federal funds rate", "federal funds rate target", ...
        "target federal funds rate", "target rate"], IgnoreCase=true) && ...
    ~contains(s, ["purchases", "reinvest", "holdings", "securities"], IgnoreCase=true);
end

function n = countNames(list)
% People named in a vote line ("None" is 0). Old format: titles and surnames, counted by
% splitting. Newer: full names, sometimes with "Chair" or a ", who preferred..." clause,
% counted by matching the names.
% Two name formats, so two ways of counting (see above)
list = strtrim(string(list));
if list == "" || startsWith(lower(list), "none")
    n = 0;
    return
end
if contains(list, ["Messrs.", "Mses.", "Mr.", "Mrs.", "Ms."])
    parts = strtrim(regexp(list, "\s*(?:,|(?<![A-Za-z])and(?![A-Za-z]))\s*", "split"));
    parts = strtrim(regexprep(parts, "^(Messrs|Mses|Mr|Mrs|Ms|Dr)\.?\s+", ""));
    n = sum(strlength(parts) > 0);
else
    list = regexprep(list, "(Vice\s+)?Chair(man)?", "");
    n = numel(regexp(list, "[A-Z][a-z]+(?:\s+[A-Z]\.)?(?:\s+[A-Z][a-z]+(?:-[A-Z][a-z]+)?)+", "match"));
end
end

function s = splitSentences(text)
% Split after a full stop that is followed by a capital letter or an opening quote.
% Cut after a full stop that is followed by a capital letter or a quote
s = regexp(text, "(?<=[a-z0-9\)%""'])\.\s+(?=[A-Z""])", "split").';
s = string(s);
end

function a = classify(verb)
% Turn the verb found into raise, cut or hold
switch lower(verb)
    case {"raise", "increase"}
        a = "raise";
    case {"lower", "reduce", "decrease", "cut", "establish"}   % "establish a target range" is the Dec 2008 cut to 0 to 1/4
        a = "cut";
    otherwise
        a = "hold";
end
end

function [target, change] = targetAndChange(sentence)
% A number as written in the minutes, such as 2, 1-1/2, 1/4 or 0.25
num = "(?:\d+(?:-\d+/\d+|/\d+|\.\d+)?)";
% Target range: the last "to/at X percent" or "X to Y percent" in the sentence
t = regexp(sentence, "(?i)(?:to|at)\s+(" + num + "(?:\s+to\s+" + num + ")?\s+percent)", "tokens");
target = "";
if ~isempty(t)
    target = string(t{end}{1});
end
% Size of the change, in percentage points or basis points
c = regexp(sentence, "(?i)(by\s+[\d\-/\.]+\s+percentage\s+points?|[\d\-/\.]+\s+basis\s+points?)", "tokens", "once");
change = "";
if ~isempty(c)
    change = string(c{1});
end
end

function t = afterColon(text)
t = strtrim(extractAfter(text, ":"));
t = regexprep(t, "\.$", "");
end

function t = clip(t, n)
if strlength(t) > n
    t = extractBefore(t, n + 1) + "...";
end
end
