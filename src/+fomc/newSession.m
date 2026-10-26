function s = newSession(asOf, cfg, nvp)
%NEWSESSION Start a conversation anchored at a date.
%   s = fomc.newSession(asOf, cfg, Llm=f)
%   Builds the context, runs the data brief and connects the model. s is a plain struct:
%   pass it to fomc.runTurn and keep the one it returns. The anchor date and data go in
%   s.contextBlock, which fomc.runTurn puts before the first question. Llm: a function
%   f(history, useTools, format) used instead of Ollama, for tests (fomc.llm.Mock).

arguments
    asOf (1,1) datetime
    cfg (1,1) struct = fomc.config()
    nvp.Llm = []
    nvp.Data = []
    nvp.TracePath (1,1) string = ""
end

% Load the data (cached), unless a test passed its own
if isempty(nvp.Data)
    D = fomc.data.load(cfg.dataDir);
else
    D = nvp.Data;
end
% Per-run state, the data snapshot, and the block that goes before the first question
ctx = fomc.context(asOf, cfg, D, tracePath=nvp.TracePath);
brief = fomc.dataBrief(ctx);
prompt = fomc.systemPrompt();
block = fomc.contextBlock(ctx, brief);

% Connect the local model, unless a test passed a fake one (ownsLlm records which)
if isempty(nvp.Llm)
    llm = fomc.llm.ollama(cfg, prompt);
else
    llm = nvp.Llm;
end

% The session is a plain struct: pass it to runTurn and keep the one it returns. known: paragraph
% ids returned by tools so far, for the citation check. lastUsedRatePath: the last answered
% question used getPolicyPath, so a follow-up that only changes the period gets it too.
s = struct("ctx", ctx, "history", messageHistory, "llm", llm, "systemPrompt", prompt, "contextBlock", block, ...
    "known", strings(0, 1), "ownsLlm", isempty(nvp.Llm), "effort", "low", "lastUsedRatePath", false);
% Record the start of the session in the trace
fomc.trace.logEvent(ctx, "session_start", struct("model", cfg.model, "backend", cfg.backend, ...
    "briefChars", strlength(brief), "maxToolRounds", cfg.maxToolRounds));
end
