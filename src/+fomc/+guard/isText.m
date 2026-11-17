function tf = isText(value)
%ISTEXT True for a char row (or empty char) or a scalar string: what a JSON text field decodes to.
tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value));
end
