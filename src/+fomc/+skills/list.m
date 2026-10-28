function skills = list()
%LIST List skills with a SKILL.md file and their frontmatter metadata.
%   skills = fomc.skills.list() returns a struct array with name and description.

folder = fomc.skills.root();
entries = dir(folder);
% dir of a string folder returns string names in R2026b, so compare as strings
names = string({entries.name});
entries = entries([entries.isdir] & ~ismember(names, [".", ".."]));
skills = struct("name", {}, "description", {});

for i = 1:numel(entries)
    skillFile = fullfile(folder, entries(i).name, "SKILL.md");
    if ~isfile(skillFile)
        continue
    end
    metadata = fomc.skills.parseFrontmatter(string(skillFile));
    skills(end+1) = metadata; %#ok<AGROW>
end
end