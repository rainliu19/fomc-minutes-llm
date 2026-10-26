function result = readSkill(ctx, args)
%READSKILL Load a skill's instructions or one of its reference files.
%   result = fomc.tools.readSkill(ctx, args) returns content as tool data rather than
%   throwing, so the model can recover from unknown skills and missing files.

MAX_CHARS = 10000;
name = string(fomc.tools.getArg(args, "name", ""));
file = string(fomc.tools.getArg(args, "file", ""));

if strlength(strtrim(name)) == 0
    result = fomc.tools.fail("'name' is required. Call readSkill with a skill name.");
    logRead(ctx, name, file, false, 0, false, result.error);
    return
end

try
    content = fomc.skills.read(name, file);
    truncated = strlength(content) > MAX_CHARS;
    if truncated
        marker = newline + "[Truncated at " + MAX_CHARS + " characters.]";
        content = extractBefore(content, MAX_CHARS - strlength(marker) + 1) + marker;
    end
    result = struct("name", name, "file", defaultFile(file), ...
        "content", content, "truncated", truncated);
    logRead(ctx, name, file, true, strlength(content), truncated, "");
catch ME
    available = availableNames();
    if string(ME.identifier) == "fomc:skills:notFound"
        message = "Unknown skill '" + name + "'.";
    else
        message = "Could not load '" + name + "/" + defaultFile(file) + "': " + string(ME.message);
    end
    if available ~= ""
        message = message + " Available skills: " + available + ".";
    end
    result = fomc.tools.fail(message);
    logRead(ctx, name, file, false, 0, false, message);
end
end

function file = defaultFile(file)
if strlength(strtrim(file)) == 0
    file = "SKILL.md";
end
end

function names = availableNames()
folder = fomc.skills.root();
entries = dir(folder);
entries = entries([entries.isdir] & ~ismember({entries.name}, {".", ".."}));
names = strings(0, 1);
for i = 1:numel(entries)
    if isfile(fullfile(folder, entries(i).name, "SKILL.md"))
        names(end+1, 1) = string(entries(i).name); %#ok<AGROW>
    end
end
if ~isempty(names)
    names = strjoin(names, ", ");
else
    names = "";
end
end

function logRead(ctx, name, file, ok, chars, truncated, message)
fomc.trace.logEvent(ctx, "skill_read", struct( ...
    "name", name, "file", defaultFile(file), "ok", ok, ...
    "chars", chars, "truncated", truncated, "message", message));
end