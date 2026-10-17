function text = plainEnglish(text)
%PLAINENGLISH Replace machine-style text in an answer with plain words.
%   text = fomc.guard.plainEnglish(text)
%   The model sometimes writes data codes (PCEPILFE), section names (staffOutlook), tool names
%   (getDecision) or other identifiers. This swaps each for everyday words, and drops codes
%   it cannot name, so the reader never sees them. Paragraph ids (full or shortened) are left
%   alone: the page turns them into numbered sources.

text = string(text);

% Protect paragraph ids while the rest is cleaned
idPat = "(?:\d{4}-\d{2}-\d{2}/)?(?:" + strjoin(sectionNames(), "|") + ")/\d+";
saved = regexp(text, idPat, "match");
pieces = regexp(text, idPat, "split");
text = pieces(1);
for k = 1:numel(saved)
    text = text + "@@" + k + "@@" + pieces(k + 1);
end

% 1. Data series codes become their everyday names
T = fomc.data.plainNames();
[~, order] = sort(strlength(T.series_id), "descend");
for i = order.'
    code = T.series_id(i);
    name = T.name(i);
    if contains(text, name, IgnoreCase=true)
        text = regexprep(text, "\s*\(" + code + "\)", "");       % the name is already in the sentence
    end
    text = swapWord(text, code, name);
end

% 2. Tool names and section names become words
text = swapWord(text, "getDecision", "the decision record");
text = swapWord(text, "searchMinutes", "a search of the minutes");
text = swapWord(text, "readMinutes", "the minutes");
text = swapWord(text, "listMeetings", "the meeting list");
text = swapWord(text, "getSeries", "the data");
text = swapWord(text, "describeSeries", "the data description");
text = swapWord(text, "getSnapshot", "the data snapshot");
text = swapWord(text, "scoreConsumerImpact", "the consumer-impact score");
text = swapWord(text, "prefetchPassages", "the passages found");
text = swapWord(text, "prefetchNotice", "the notice");
sections = sectionNames();
words = ["participants' views", "staff outlook", "staff review of the economy", ...
    "staff review of financial conditions", "financial markets", "policy action", "special topics"];
for i = 1:numel(sections)
    text = swapWord(text, sections(i), words(i));
end

% 3. Anything else that still looks like an identifier
text = regexprep(text, "(?<![A-Za-z0-9_@])(?=[A-Z0-9_]*\d)[A-Z][A-Z0-9_]{3,}(?![A-Za-z0-9_@])", "");     % unknown code with digits
text = regexprep(text, "(?<![A-Za-z0-9_@])[a-z]+(?:[A-Z][a-z0-9]+)+(?![A-Za-z0-9_@])", "");                 % camelCase name
text = regexprep(text, "(?<![A-Za-z0-9_@])[a-z]+(?:_[a-z0-9]+)+(?![A-Za-z0-9_@])", "");                    % snake_case name

% 4. Tidy what removing things left behind
text = regexprep(text, "\(\s*[,;]?\s*\)", "");
text = regexprep(text, "\s+([,.;:])", "$1");
text = regexprep(text, "[ \t]{2,}", " ");
text = regexprep(text, "([a-z]+(?: [a-z]+){0,5}) \(\1\)", "$1", "ignorecase");     % "x (x)" -> "x"

% Put the paragraph ids back
for k = numel(saved):-1:1
    text = replace(text, "@@" + k + "@@", saved(k));
end
text = strtrim(text);
end

function names = sectionNames()
names = fomc.data.sections().name;
names = names(names ~= "body");
end

function text = swapWord(text, word, replacement)
% Replace a whole word, with the replacement taken literally.
pat = "(?<![A-Za-z0-9_@])" + word + "(?![A-Za-z0-9_@])";
found = regexp(text, pat, "match");
if isempty(found)
    return
end
pieces = regexp(text, pat, "split");
out = pieces(1);
for k = 1:numel(found)
    out = out + replacement + pieces(k + 1);
end
text = out;
end
