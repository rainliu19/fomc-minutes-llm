function r = searchMinutes(ctx, args)
%SEARCHMINUTES Case-insensitive phrase search over released minutes; | separates alternatives.

% Read and check the arguments
query = strtrim(string(fomc.tools.getArg(args, "query", "")));
if strlength(query) == 0
    r = fomc.tools.fail("'query' is required: a short phrase such as 'balance sheet runoff'.");
    return
end
maxResults = fomc.tools.getArg(args, "maxResults", 5);
if ~isnumeric(maxResults) || ~isscalar(maxResults) || maxResults < 1 || maxResults > 20 || maxResults ~= round(maxResults)
    r = fomc.tools.fail("'maxResults' must be a whole number from 1 to 20.");
    return
end
startDate = fomc.util.parseDate(fomc.tools.getArg(args, "startDate", ""));
endDate = fomc.util.parseDate(fomc.tools.getArg(args, "endDate", ""));

% Use the focus window when no dates were given
[startDate, endDate, isDefault] = fomc.tools.applyWindow(ctx, startDate, endDate);

% Split 'a|b' into alternative search terms
terms = strtrim(split(query, "|"));
terms(terms == "") = [];

% Keep only meetings released by the anchor date and inside the window
M = ctx.D.meetings;
eligible = M.ReleaseDate <= ctx.asOf;
if ~isnat(startDate)
    eligible = eligible & M.MeetingDate >= startDate;
end
if ~isnat(endDate)
    eligible = eligible & M.MeetingDate <= endDate;
end

% Take the paragraphs of those meetings that contain any term, newest meeting first
P = ctx.D.paras;
P.order = (1:height(P)).';
P = P(eligible(P.meetingIdx), :);
P = P(contains(P.text, terms, IgnoreCase=true), :);
P = sortrows(P, ["meetingIdx", "order"], ["descend", "ascend"]);

% Build the result: the top hits, each with a snippet around the match
total = height(P);
P = P(1:min(maxResults, total), :);
hits = cell(height(P), 1);
for i = 1:height(P)
    hits{i} = struct("id", P.id(i), "meetingDate", fomc.util.fmtDate(M.MeetingDate(P.meetingIdx(i))), ...
        "section", P.section(i), "paragraph", P.paraIdx(i), ...
        "snippet", snippetAround(P.text(i), terms, 450));
end
r = struct("query", query, "totalMatches", total, "shown", height(P), ...
    "window", struct("startDate", fomc.util.fmtDate(startDate), "endDate", fomc.util.fmtDate(endDate), ...
    "isDefault", isDefault), "hits", {hits});
% No hits: tell the model how to try again
if total == 0
    r.note = "No paragraphs matched. Try fewer or broader words, or alternatives separated by | such as 'tariff|trade policy'.";
    if isDefault
        r.note = r.note + " Only the default focus window was searched; pass startDate and endDate to search other years.";
    end
end
end

function s = snippetAround(text, terms, maxLen)
% Up to maxLen characters of the paragraph, centered on the first match.
chars = char(text);
if numel(chars) <= maxLen
    s = text;
    return
end
% Find the earliest match of any term
low = lower(chars);
first = inf;
for t = terms.'
    p = strfind(low, char(lower(t)));
    if ~isempty(p)
        first = min(first, p(1));
    end
end
if isinf(first)
    first = 1;
end
% Take a stretch of text around that match, kept inside the paragraph
a = max(1, first - floor(maxLen / 2));
b = min(numel(chars), a + maxLen - 1);
a = max(1, b - maxLen + 1);
s = string(chars(a:b));
if a > 1
    s = "..." + s;
end
if b < numel(chars)
    s = s + "...";
end
end
