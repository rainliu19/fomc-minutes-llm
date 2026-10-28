function text = read(name, file)
%READ Return the text of a file contained in a named skill directory.
%   text = fomc.skills.read(name) reads SKILL.md.
%   text = fomc.skills.read(name, file) reads a skill-relative file.

arguments
    name (1,1) string
    file (1,1) string = ""
end

if strlength(file) == 0
    file = "SKILL.md";
end

% Names are directory names; file may include nested paths such as rubric/ratePath.md.
if isempty(regexp(char(name), '^[A-Za-z0-9_-]+$', 'once'))
    error("fomc:skills:invalidName", "Skill name must be a single directory name.");
end
segments = split(replace(file, "\", "/"), "/");
if startsWith(file, "/") || any(segments == "" | segments == "." | segments == "..")
    error("fomc:skills:invalidFile", "Skill file must be a relative path inside the skill directory.");
end

skillFolder = fullfile(fomc.skills.root(), name);
if ~isfolder(skillFolder)
    error("fomc:skills:notFound", "Skill '%s' does not exist.", name);
end
parts = cellstr(segments);
path = fullfile(skillFolder, parts{:});
if ~isfile(path)
    error("fomc:skills:fileNotFound", "File '%s' does not exist in skill '%s'.", file, name);
end

text = string(fileread(path));
end