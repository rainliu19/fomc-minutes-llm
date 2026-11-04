function issues = checkRationaleSign(result)
%CHECKRATIONALESIGN Dimensions whose rationale calls them dovish or hawkish but whose score has the other sign.
%   issues = fomc.guard.checkRationaleSign(result)
%
%   On the skill's scale +1 is hawkish and -1 dovish. Qwen3 4B scored the asset purchases of
%   2020-03-15 at +0.25 with the rationale "... so it reflects a dovish stance on balance sheet
%   size": the words and the number disagree. A rationale that says only "dovish" with a score
%   above 0, or only "hawkish" with a score below 0, is an issue, so the scorer can retry. A word
%   after "not", "less", "more" or "no longer" is a comparison, not a verdict, and is skipped.

issues = strings(0, 1);
if ~(isstruct(result) && isfield(result, "dimensions") && isstruct(result.dimensions))
    return
end
for name = string(fieldnames(result.dimensions)).'
    dim = result.dimensions.(name);
    if ~(isfield(dim, "score") && isnumeric(dim.score) && isscalar(dim.score) && isfield(dim, "rationale"))
        continue
    end
    text = lower(string(dim.rationale));
    saysDovish = said(text, "dovish");
    saysHawkish = said(text, "hawkish");
    if saysDovish && ~saysHawkish && dim.score > 0
        issues(end+1, 1) = name + ": the rationale calls it dovish but the score is " + dim.score + ...
            "; on this scale dovish is negative (-1) and hawkish positive (+1)."; %#ok<AGROW>
    elseif saysHawkish && ~saysDovish && dim.score < 0
        issues(end+1, 1) = name + ": the rationale calls it hawkish but the score is " + dim.score + ...
            "; on this scale hawkish is positive (+1) and dovish negative (-1)."; %#ok<AGROW>
    end
end
end

function tf = said(text, word)
% The word as a verdict: present, and not right after a word that makes it a comparison
tf = ~isempty(regexp(text, "(?<!not |less |more |longer )(?<![a-z])" + word, "once"));
end
