function folder = root()
%ROOT Absolute path to the repository's skills directory.
%   folder = fomc.skills.root()

% This file is in <repo>/src/+fomc/+skills, so resolve the skills folder from here.
here = string(fileparts(mfilename("fullpath")));
repo = fileparts(fileparts(fileparts(here)));
folder = fullfile(repo, "skills");
end
