function issues = checkQuotes(result, minutesText)
%CHECKQUOTES Require each evidence quote to be short and present verbatim in the minutes.

issues = strings(0, 1);
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, "dimensions") || ...
        ~isstruct(result.dimensions) || ~isscalar(result.dimensions)
    return
end
haystack = normalize(minutesText);
for name = string(fieldnames(result.dimensions)).'
    dim = result.dimensions.(name);
    if ~isstruct(dim) || ~isscalar(dim) || ~isfield(dim, "evidence")
        continue
    end
    evidence = fomc.util.asCell(dim.evidence);
    for k = 1:numel(evidence)
        item = evidence{k};
        if ~isstruct(item) || ~isscalar(item) || ~isfield(item, "quote") || ...
                ~(ischar(item.quote) || (isstring(item.quote) && isscalar(item.quote)))
            continue
        end
        quote = strtrim(normalize(string(item.quote)));
        if numel(split(quote)) > 40
            issues(end+1, 1) = name + ": quote " + k + " exceeds 40 words."; %#ok<AGROW>
        elseif strlength(quote) == 0 || ~contains(haystack, quote)
            issues(end+1, 1) = name + ": quote " + k + " not found in the minutes."; %#ok<AGROW>
        end
    end
end
end

function text = normalize(text)
text = string(text);
text = replace(text, char(8216), "'");
text = replace(text, char(8217), "'");
text = replace(text, char(8220), '"');
text = replace(text, char(8221), '"');
text = replace(text, char(8211), "-");
text = replace(text, char(8212), "-");
text = replace(text, char(8722), "-");
text = replace(text, char(160), " ");
text = replace(text, char(8239), " ");
text = lower(regexprep(text, "\s+", " "));
end
