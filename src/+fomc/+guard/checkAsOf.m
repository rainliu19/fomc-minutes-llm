function issues = checkAsOf(result, releaseDate, minutesText)
%CHECKASOF Flag rationales that explicitly refer to dates after the minutes release.
%   issues = fomc.guard.checkAsOf(result, releaseDate)
%   issues = fomc.guard.checkAsOf(result, releaseDate, minutesText)
%
%   A date or year after the release is hindsight, unless the minutes themselves give it: the
%   2011-2012 minutes put the Committee's guidance at "mid-2013", "late 2014" and "mid-2015",
%   and the 2020-2021 minutes give the projections through 2023. With minutesText, a year or date
%   the minutes name is allowed; without it, any later year or date is an issue.

arguments
    result
    releaseDate
    minutesText (1,1) string = ""
end

issues = strings(0, 1);
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, "dimensions") || ...
        ~isstruct(result.dimensions) || ~isscalar(result.dimensions)
    return
end
if ~isdatetime(releaseDate) || ~isscalar(releaseDate) || isnat(releaseDate)
    return
end
releaseDate = dateshift(releaseDate, "start", "day");
named = string(regexp(char(minutesText), '(?<!\d)(?:19|20)\d{2}(?!\d)', 'match'));
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
        if ~isnat(d) && d > releaseDate && ~contains(minutesText, dateText)
            issues(end+1, 1) = name + ".rationale mentions " + dateText + ...
                ", after the minutes release date " + fomc.util.fmtDate(releaseDate) + "."; %#ok<AGROW>
        end
    end
    years = regexp(char(rationale), '(?<!\d)(?:19|20)\d{2}(?!\d)', 'match');
    for yearText = string(years)
        if str2double(yearText) > year(releaseDate) && ~any(named == yearText)
            issues(end+1, 1) = name + ".rationale mentions year " + yearText + ...
                ", after the minutes release date " + fomc.util.fmtDate(releaseDate) + "."; %#ok<AGROW>
        end
    end
end
issues = unique(issues, "stable");
end
