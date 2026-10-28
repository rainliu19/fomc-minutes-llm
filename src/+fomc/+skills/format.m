function text = format()
%FORMAT Render discovered skills as a short system-prompt section.
%   text = fomc.skills.format() includes frontmatter names and descriptions.

skills = fomc.skills.list();
lines = [
    "## Skills"
    ""
    "When a skill matches the request, call readSkill with the skill's name before answering"
    "and follow its instructions. Load referenced files only when directed."
    ""
    "Available skills:"
    ""
    ];

for i = 1:numel(skills)
    description = strtrim(skills(i).description);
    wrapped = wrap(description, 76);
    lines(end+1, 1) = "- " + skills(i).name + ": " + wrapped(1); %#ok<AGROW>
    for j = 2:numel(wrapped)
        lines(end+1, 1) = "  " + wrapped(j); %#ok<AGROW>
    end
end

if isempty(skills)
    lines(end+1, 1) = "- (none)";
end
lines(end+1, 1) = "";
lines(end+1, 1) = "Do not answer scoring requests from memory. Load the skill first.";
text = strjoin(lines, newline);
end

function lines = wrap(text, width)
words = split(text);
lines = strings(0, 1);
line = "";
for i = 1:numel(words)
    candidate = strtrim(line + " " + words(i));
    if strlength(candidate) > width && line ~= ""
        lines(end+1, 1) = line; %#ok<AGROW>
        line = words(i);
    else
        line = candidate;
    end
end
if line ~= ""
    lines(end+1, 1) = line;
end
if isempty(lines)
    lines = "";
end
end
