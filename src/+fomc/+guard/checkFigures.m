function bad = checkFigures(answer, sources)
%CHECKFIGURES Fraction-style rate ranges in an answer that are not in its sources.
%   bad = fomc.guard.checkFigures(answer, sources)
%   Catches a small model's miscopy ("1/2 to 13/4 percent" for "1-1/2 to 1-3/4 percent").
%   Only figures with a fraction are checked, to avoid false alarms on decimals.

% Find rate ranges written with fractions, like "1-1/2 to 1-3/4 percent"
num = "\d+(?:-\d+/\d+|/\d+)?";
found = regexp(string(answer), num + "(?:\s+to\s+" + num + ")?\s+percent", "match");
found = unique(string(found));
found = found(contains(found, "/"));
% Each one must appear word for word in the sources the model was given
src = regexprep(join(string(sources(:)), " "), "\s+", " ");
bad = strings(0, 1);
for f = found(:).'
    if ~contains(src, regexprep(f, "\s+", " "))
        bad(end+1, 1) = f; %#ok<AGROW>
    end
end
end
