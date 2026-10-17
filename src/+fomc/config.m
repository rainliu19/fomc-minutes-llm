function cfg = config(nvp)
%CONFIG Default settings for the agent. cfg = fomc.config(Name=Value) overrides any.
%
%   backend            "ollama" (local, free); the only one built.
%   model              Ollama model name; "fomc-qwen3" is built from models/qwen3/Modelfile.
%   endpoint           Ollama address.
%   timeoutSec         Wait for one model call.
%   maxToolRounds      Tool-call rounds per turn.
%   maxToolChars       Cap on the text one tool returns (about 1.2k tokens).
%   maxResultChars     Hard cap on any encoded tool result.
%   anchorType         "release" or "meeting": which date anchors a meeting.
%   modelCutoff        Model knowledge cutoff (datetime); NaT = unverified.
%   cutoffBufferDays   Margin after the cutoff before a meeting counts as clean.
%   focusYears         Default span of minutes a question looks at (see fomc.focus.window).
%   maxTokens          Cap on tokens written per call; writing is the slow part.
%   maxTokensAnalysis  Cap for the structured analysis call.
%   compactAtTokens    Trim old tool results past this estimate (keep below the 8192 window).
%   prefetch           The harness looks up decision cards or passages itself (fomc.focus.prefetch).
%   prefetchHits       Passages the harness looks up before the model starts (see fomc.effort).
%   temperature        Model randomness; low keeps tool use steady.
%   scorerModel        Model for the rubric scorer, independent of the agent.
%   verbose            Print each tool call as it runs.

arguments
    nvp.backend (1,1) string = "ollama"
    nvp.model (1,1) string = "fomc-qwen3"
    nvp.endpoint (1,1) string = "127.0.0.1:11434"
    nvp.timeoutSec (1,1) double = 600
    nvp.maxToolRounds (1,1) double = 8
    nvp.maxToolChars (1,1) double = 4000
    nvp.maxResultChars (1,1) double = 30000
    nvp.anchorType (1,1) string {mustBeMember(nvp.anchorType,["release","meeting"])} = "release"
    nvp.modelCutoff (1,1) datetime = NaT
    nvp.cutoffBufferDays (1,1) double = 90
    nvp.focusYears (1,1) double = 3
    nvp.prefetch (1,1) logical = true
    nvp.prefetchHits (1,1) double = 3
    nvp.temperature (1,1) double = 0.2
    nvp.maxTokens (1,1) double = 450
    nvp.maxTokensAnalysis (1,1) double = 700
    nvp.compactAtTokens (1,1) double = 5500
    nvp.scorerModel (1,1) string = ""
    nvp.verbose (1,1) logical = true
    nvp.dataDir (1,1) string = ""
    nvp.logDir (1,1) string = ""
end

% Start from the options given, then add the repo root and default folders
cfg = nvp;
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
cfg.root = root;
if cfg.dataDir == ""
    cfg.dataDir = fullfile(root, "data");
end
if cfg.logDir == ""
    cfg.logDir = fullfile(root, "logs");
end
% The scorer uses the agent model unless told otherwise
if cfg.scorerModel == ""
    cfg.scorerModel = cfg.model;
end
end
