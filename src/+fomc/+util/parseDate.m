function d = parseDate(s)
%PARSEDATE Parse a yyyy-MM-dd string into a datetime; NaT if invalid.
%   The one place that decides what counts as a valid date in tool arguments.

% Only a text value shaped like 2020-03-15 is accepted
d = NaT;
if isempty(s) || ~(ischar(s) || (isstring(s) && isscalar(s)))
    return
end
s = strtrim(string(s));
if ~matches(s, digitsPattern(4) + "-" + digitsPattern(2) + "-" + digitsPattern(2))
    return
end
% Reject impossible dates such as 2020-02-31
try
    d = datetime(s, InputFormat="yyyy-MM-dd");
catch
    d = NaT;
end
end
