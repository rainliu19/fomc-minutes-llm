function metadata = parseFrontmatter(skillFile)
%PARSEFRONTMATTER Read name and description from a skill's YAML frontmatter.
%   metadata = fomc.skills.parseFrontmatter(skillFile)

arguments
    skillFile (1,1) string
end

if ~isfile(skillFile)
    error("fomc:skills:missingFile", "Skill file does not exist: %s", skillFile);
end

lines = readlines(skillFile);
if ~isempty(lines) && startsWith(lines(1), char(65279))
    lines(1) = extractAfter(lines(1), 1);   % tolerate a UTF-8 byte-order mark
end

if isempty(lines) || strtrim(lines(1)) ~= "---"
    error("fomc:skills:invalidFrontmatter", ...
        "The first line of %s must be '---'.", skillFile);
end

closing = find(strtrim(lines(2:end)) == "---", 1) + 1;
if isempty(closing)
    error("fomc:skills:invalidFrontmatter", ...
        "Skill frontmatter in %s has no closing '---' line.", skillFile);
end

fields = struct("name", "", "description", "");
for i = 2:closing-1
    line = lines(i);
    token = regexp(char(line), '^\s*(name|description)\s*:\s*(.*?)\s*$', 'tokens', 'once');
    if isempty(token)
        continue
    end
    key = string(token{1});
    value = strtrim(string(token{2}));
    chars = char(value);
    if numel(chars) >= 2 && ...
            ((chars(1) == '"' && chars(end) == '"') || ...
             (chars(1) == '''' && chars(end) == ''''))
        value = string(chars(2:end-1));
    end
    fields.(key) = value;
end

if strlength(fields.name) == 0 || strlength(fields.description) == 0
    error("fomc:skills:invalidFrontmatter", ...
        "Skill frontmatter in %s must define non-empty name and description fields.", skillFile);
end
metadata = fields;
end
