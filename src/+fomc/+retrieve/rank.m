function hits = rank(question, ctx, k)
%RANK The released paragraphs that best match a question.
%   hits = fomc.retrieve.rank(question, ctx, k): up to k hits, best first, each with id,
%   meetingDate, section, paragraph, snippet and score. For a question about change over
%   time, the best paragraph of each year comes first.
%
%   BM25 term weighting, no model: rarer question words count more, adjacent word pairs
%   like "labor market" count extra, and words match on their first six letters. Searches
%   only minutes released by the anchor date, inside the focus window if one is set.

arguments
    question (1,1) string
    ctx (1,1) struct
    k (1,1) double = 3
end

% Common words that carry no meaning for matching
stop = ["the","and","for","are","was","were","what","how","did","does","say","said","about","their","they", ...
    "them","with","from","that","this","have","has","had","which","who","when","where","why","would","could", ...
    "should","into","over","than","then","there","these","those","any","all","its","not","but","can","you", ...
    "tell","explain","describe","described","discuss","discussed","meeting","meetings","committee","minutes","fomc"];
% Split the question into content words
ordered = lower(string(regexp(lower(question), "[a-z]{3,}", "match")));
keep = ~ismember(ordered, stop);
words = unique(ordered(keep), "stable");
hits = struct("id", {}, "meetingDate", {}, "section", {}, "paragraph", {}, "snippet", {}, "score", {});
if isempty(words)
    return
end
% Match on word stems (first six letters) so "inflationary" matches "inflation"
stems = strtrim(arrayfun(@(w) extractBefore(w + "      ", 7), words));      % first six letters

% Only paragraphs of meetings released by the anchor date and inside the focus window may score
P = ctx.D.paras;
M = ctx.D.meetings;
eligible = M.ReleaseDate <= ctx.asOf;
if ~isnat(ctx.focus.start)
    eligible = eligible & M.MeetingDate >= ctx.focus.start & M.MeetingDate <= ctx.focus.end;
end
% BM25 score: each word adds more if it is rare overall and appears often in a short paragraph
low = lower(P.text);
len = strlength(P.text);
avgLen = mean(len);
k1 = 1.2; b = 0.75;                                       % standard BM25 settings
N = height(P);
score = zeros(N, 1);
% Add up the score of every question word for every paragraph
for s = stems.'
    tf = count(low, s);
    df = sum(tf > 0);
    if df > 0
        idf = log(1 + (N - df + 0.5) / (df + 0.5));
        score = score + idf * (tf * (k1 + 1)) ./ (tf + k1 * (1 - b + b * len / avgLen));
    end
end
% Adjacent question words ("labor market") count extra when they sit together in a paragraph
pairs = strings(0, 1);
kept = ordered(keep);
for i = 1:numel(kept) - 1
    pairs(end+1, 1) = kept(i) + " " + kept(i + 1); %#ok<AGROW>
end
for ph = unique(pairs).'
    score = score + 3 * contains(low, ph);
end
% Paragraphs that are not allowed to be seen score zero
score(~eligible(P.meetingIdx)) = 0;
% Among near-equal matches, prefer newer meetings
lo = find(eligible, 1, "first"); hi = find(eligible, 1, "last");
if ~isempty(lo)
    recency = min(max((P.meetingIdx - lo) / max(1, hi - lo), 0), 1);
    score(score > 0) = score(score > 0) + 0.5 * recency(score > 0);
end
% Best first; drop paragraphs with no match
[~, order] = sort(score, "descend");
order = order(score(order) > 0);
% For change-over-time questions: the best paragraph of each year first, then by score.
if ~isempty(order) && (numel(regexp(lower(question), "20\d\d", "match")) > 1 || ...
        contains(lower(question), ["change", "evolv", "compar", "between", "versus", "since", "over time", "shift", "trend"]))
    yrs = year(M.MeetingDate(P.meetingIdx(order)));
    [~, firstOfYear] = unique(yrs, "stable");
    chosen = order(sort(firstOfYear));
    rest = setdiff(order, chosen, "stable");
    order = [chosen; rest];
    k = max(k, min(numel(unique(yrs)), 4));
end
% Keep the top k and shorten the text to a snippet
order = order(1:min(k, numel(order)));
for i = order.'
    text = P.text(i);
    if strlength(text) > 350
        text = extractBefore(text, 351) + "...";
    end
    hits(end+1) = struct("id", P.id(i), "meetingDate", fomc.util.fmtDate(M.MeetingDate(P.meetingIdx(i))), ...
        "section", P.section(i), "paragraph", P.paraIdx(i), "snippet", text, "score", score(i)); %#ok<AGROW>
end
end
