function v = getArg(args, name, default)
%GETARG An argument from the model's JSON object, or a default if absent or blank ([], '' or "").

% Missing, empty or whitespace-only counts as not given
blank = ~isfield(args, name) || isempty(args.(name)) || ...
    ((ischar(args.(name)) || isstring(args.(name))) && all(strlength(strtrim(string(args.(name)))) == 0));
if blank
    v = default;
else
    v = args.(name);
end
end
