function issues = checkAsOf(result, releaseDate)
%CHECKASOF Flag rationales that explicitly refer to dates after the minutes release.

issues = strings(0, 1);
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, "dimensions") || ...
        ~isstruct(result.dimensions) || ~isscalar(result.dimensions)
    return
end
if ~isdatetime(releaseDate) || ~isscalar(releaseDate) || isnat(releaseDate)
    return
end
releaseDate = dateshift(releaseDate, "start", "day");
for name = string(fieldnames(result.dimensions)).'
    dim = result.dimensions.(name);
    if ~isstruct(dim) || ~isscalar(dim) || ~isfield(dim, "rationale") || ...
            ~(ischar(dim.rationale) || (isstring(dim.rationale) && isscalar(dim.rationale)))
        continue
    end
    rationale = string(dim.rationale);
    dates = regexp(char(rationale), '\d{4}-\d{2}-\d{2}', 'match');
    for dateText = string(dates)
        d = fomc.util.parseDate(dateText);
        if ~isnat(d) && d > releaseDate
            issues(end+1, 1) = name + ".rationale mentions " + dateText + ...
                ", after the minutes release date " + fomc.util.fmtDate(releaseDate) + "."; %#ok<AGROW>
        end
    end
    years = regexp(char(rationale), '(?<!\d)(?:19|20)\d{2}(?!\d)', 'match');
    for yearText = string(years)
        if str2double(yearText) > year(releaseDate)
            issues(end+1, 1) = name + ".rationale mentions year " + yearText + ...
                ", after the minutes release date " + fomc.util.fmtDate(releaseDate) + "."; %#ok<AGROW>
        end
    end
end
issues = unique(issues, "stable");
end
