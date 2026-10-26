function out = dissentDirections(D, k, change, upperAfter)
%DISSENTDIRECTIONS Which way each dissenter at one meeting wanted the rate to go.
%   out = fomc.data.dissentDirections(D, k, change, upperAfter)
%   k: row of D.meetings. change: the actual change at that meeting (percentage points, 0 for
%   a hold). upperAfter: the top of the target range after it.
%   out: struct array with name (surname), direction and id. direction is "higher" or "lower"
%   (the rate the dissenter preferred, compared with the decision) or "other" (the dissent was
%   about something else, such as statement wording or asset purchases, or its preference
%   could not be read). No model: the preference is read from the vote line and the
%   paragraphs after it.

arguments
    D (1,1) struct
    k (1,1) double
    change (1,1) double
    upperAfter (1,1) double
end

out = struct("name", {}, "direction", {}, "id", {});
c = D.cards(k, :);
if c.unanimous || c.voteId == ""
    return
end

% Surnames of those who voted against
names = surnames(c.votesAgainst);
if isempty(names)
    return
end

% The texts that say what each dissenter preferred: the vote line, then the paragraphs right
% after it that mention a dissent (the same paragraphs the decision card reads)
P = D.paras(D.paras.meetingIdx == k & D.paras.section == "policyAction", :);
v = find(P.id == c.voteId, 1);
blocks = c.votesAgainst;
ids = c.voteId;
for j = v+1:min(v+3, height(P))
    if contains(P.text(j), ["voted against", "preferred", "dissent"], IgnoreCase=true)
        blocks(end+1, 1) = P.text(j); %#ok<AGROW>
        ids(end+1, 1) = P.id(j); %#ok<AGROW>
    end
end

% Each block is cut into segments, one per mention of a dissenter's name. A segment that is
% only a name in a list ("Miran and ") takes the reading of the next segment in its block.
own = strings(numel(names), 1);
ownId = strings(numel(names), 1);
shared = strings(numel(names), 1);
sharedId = strings(numel(names), 1);
pattern = "(?<![A-Za-z])(" + strjoin(names, "|") + ")(?![A-Za-z])";
for b = 1:numel(blocks)
    [starts, hits] = regexp(blocks(b), pattern, "start", "match");
    if isempty(starts)
        continue
    end
    ends = [starts(2:end) - 1, strlength(blocks(b))];
    reading = strings(numel(starts), 1);
    isOwn = false(numel(starts), 1);
    for s = numel(starts):-1:1
        seg = extractBetween(blocks(b), starts(s), ends(s));
        r = readPreference(seg, change, upperAfter);
        if r ~= ""
            reading(s) = r;
            isOwn(s) = true;
        elseif s < numel(starts) && strlength(strtrim(seg)) < 40
            reading(s) = reading(s + 1);
        end
    end
    % Keep each dissenter's first reading: their own wording first, a shared one otherwise
    for s = 1:numel(starts)
        i = find(names == string(hits{s}), 1);
        if reading(s) == ""
            continue
        end
        if isOwn(s) && own(i) == ""
            own(i) = reading(s);
            ownId(i) = ids(b);
        elseif ~isOwn(s) && shared(i) == ""
            shared(i) = reading(s);
            sharedId(i) = ids(b);
        end
    end
end

% One entry per dissenter
for i = 1:numel(names)
    direction = own(i);
    id = ownId(i);
    if direction == ""
        direction = shared(i);
        id = sharedId(i);
    end
    if direction == ""
        direction = "other";
        id = c.voteId;
    end
    out(end+1) = struct("name", names(i), "direction", direction, "id", id); %#ok<AGROW>
end
end

function names = surnames(list)
% Surnames in a vote line. Old format: "Messrs. Fisher and Plosser". Newer: full names,
% sometimes followed by ", who preferred ..." clauses.
list = strtrim(string(list));
if list == "" || startsWith(lower(list), "none")
    names = strings(0, 1);
    return
end
if contains(list, ["Messrs.", "Mses.", "Mr.", "Mrs.", "Ms."])
    parts = strtrim(regexp(list, "\s*(?:,|(?<![A-Za-z])and(?![A-Za-z]))\s*", "split"));
    parts = strtrim(regexprep(parts, "^(Messrs|Mses|Mr|Mrs|Ms|Dr)\.?\s+", ""));
    parts = parts(strlength(parts) > 0);
    names = string(regexp(parts, "[A-Z][a-z]+(?:-[A-Z][a-z]+)?$", "match", "once"));
else
    list = regexprep(list, "(Vice\s+)?Chair(man)?", "");
    full = regexp(list, "[A-Z][a-z]+(?:\s+[A-Z]\.)?(?:\s+[A-Z][a-z]+(?:-[A-Z][a-z]+)?)+", "match");
    names = string(regexp(string(full), "[A-Z][a-z]+(?:-[A-Z][a-z]+)?$", "match", "once"));
end
names = unique(names(~ismissing(names) & names ~= ""), "stable");
names = names(:);
end

function r = readPreference(seg, change, upperAfter)
% "higher", "lower" or "other" from the first sentence in a segment that states a view; ""
% if the segment states none. Only a preference about the rate target counts as higher or
% lower, compared with what the Committee actually did.
r = "";
cue = "(?i)(preferr|prefers|favor|supported|believed|judged|dissent|voted against|would have)";
rateWords = "(?i)(target range|federal funds rate|funds rate|target rate|federal funds target|setting of (monetary )?policy)";
% At a cut: "favored easing policy less aggressively" (2008), "did not see a clear and
% compelling case for additional accommodation" or "policy was already accommodative" (2019)
% mean a smaller cut or none
smallerCut = "(?i)(less aggressive|already accommodative|" + ...
    "(?<![A-Za-z])(not|no)(?![A-Za-z])[^.]{0,60}additional (policy |monetary )?accommodation|" + ...
    "additional (policy |monetary )?accommodation (was|is|would be) not)";
for s = splitSentences(seg).'
    if isempty(regexp(s, cue, "once"))
        continue
    end
    if change < 0 && ~isempty(regexp(s, smallerCut, "once"))
        r = "higher";
        return
    end
    if isempty(regexp(s, rateWords, "once"))
        r = "other";
        return
    end
    r = compareWithDecision(s, change, upperAfter);
    return
end
end

function r = compareWithDecision(s, change, upperAfter)
% Work out the rate the sentence prefers and compare it with the decision
verb = regexp(s, "(?i)(?<![A-Za-z])(raise|raising|increase|increasing|lower|lowering|reduce|reducing|reduction|cut|cutting|decrease|maintain|maintaining|unchanged|no change|leave|leaving|keep|keeping)(?![A-Za-z])", "match", "once");
if isempty(verb)
    r = "other";
    return
end
verb = lower(string(verb));
% The way the dissenter wanted to move the rate: up (1), down (-1) or not at all (0)
if any(verb == ["raise", "raising", "increase", "increasing"])
    way = 1;
elseif any(verb == ["lower", "lowering", "reduce", "reducing", "reduction", "cut", "cutting", "decrease"])
    way = -1;
else
    way = 0;
end

% A stated size ("by 1/2 percentage point", "25 basis points") or target range
% ("to 1/2 to 3/4 percent"). Only the range form counts as a target, so "inflation ... to 2
% percent" in the same sentence is not read as one.
num = "\d+(?:-\d+/\d+|/\d+|\.\d+)?";
pts = regexp(s, "(?i)by\s+(" + num + ")\s+percentage\s+points?", "tokens", "once");
bps = regexp(s, "(?i)(\d+)\s+basis[\s-]+points?", "tokens", "once");
target = regexp(s, "(?i)(?<![A-Za-z])to\s+" + num + "\s+to\s+(" + num + ")\s+percent", "tokens", "once");

if way ~= 0 && ~isempty(pts)
    diffToDecision = way * toNumber(pts{1}) - change;
elseif way ~= 0 && ~isempty(bps)
    diffToDecision = way * str2double(bps{1}) / 100 - change;
elseif way ~= 0 && ~isempty(target)
    diffToDecision = toNumber(target{1}) - upperAfter;
elseif way == 0
    diffToDecision = -change;
elseif way * change <= 0
    diffToDecision = way;    % a move the Committee did not make at all
else
    diffToDecision = 0;      % same direction, size not stated: cannot tell
end

if diffToDecision > 1e-9
    r = "higher";
elseif diffToDecision < -1e-9
    r = "lower";
else
    r = "other";
end
end

function x = toNumber(t)
% "1-1/2" -> 1.5, "3/4" -> 0.75, "0.5" -> 0.5, "2" -> 2
t = string(t);
parts = split(t, "-");
x = 0;
for p = parts.'
    if contains(p, "/")
        f = split(p, "/");
        x = x + str2double(f(1)) / str2double(f(2));
    else
        x = x + str2double(p);
    end
end
end

function s = splitSentences(text)
% Split after a full stop that is followed by a capital letter or an opening quote
s = string(regexp(text, "(?<=[a-z0-9\)%""'])\.\s+(?=[A-Z""])", "split")).';
end
