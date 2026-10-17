function c = asCell(x)
%ASCELL A decoded JSON array as a column cell array.
%   jsondecode returns a struct array or a cell array depending on the data; this makes both alike.

% Empty, cell, struct array or a single value: all become a column cell array
if isempty(x)
    c = {};
elseif iscell(x)
    c = x(:);
elseif isstruct(x)
    c = num2cell(x(:));
else
    c = {x};
end
end
