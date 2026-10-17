function setup()
%SETUP Put the agent on the MATLAB path (src/). Run once per session from the repo root.
%   >> setup
%   >> fomc.chat()

% The repo root is the folder this file is in; the agent code lives in src/
root = fileparts(mfilename("fullpath"));
addpath(fullfile(root, "src"));
fprintf("FOMC agent ready: src/ added to the path. Try fomc.chat()\n");
end
