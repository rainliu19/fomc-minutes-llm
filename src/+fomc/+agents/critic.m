function [s, answer] = critic(s, msg, answer, calls)
%CRITIC Check the writer's answer in code; on a failure ask for one rewrite (Generator-Critic call loop).
%   [s, answer] = fomc.agents.critic(s, msg, answer, calls)
%   Each round runs fomc.guard.review (paragraph ids, citations, figures, plain words), which
%   is code only and sees the answer, not the writer's conversation. If it fails, the writer
%   gets agents/organizer.md's "Critic" message once and the rewrite replaces the draft in the
%   history (the message itself is not kept). Rounds are capped by cfg.criticRounds in code: the
%   draft is round 1, so the default 2 allows one rewrite. An answer that still fails is
%   marked unverified in s.lastReview (the web page shows it), never looped on.

cfg = s.ctx.cfg;
s.lastReview = struct("rounds", 0, "unverified", false, "issues", "");
% A turn that failed was rolled back: its message is not the last one, so there is nothing to check
if isempty(s.history.Messages) || string(s.history.Messages{end}.content) ~= answer
    return
end
c = fomc.agents.catalog();
parts = split(strip(c([c.name] == "organizer").body), compose("\n\n"));
for round = 1:cfg.criticRounds
    [~, ~, warning] = fomc.guard.review(answer, s, calls, msg, "chat", []);
    fomc.trace.logEvent(s.ctx, "critic", struct("round", round, "pass", warning == "", "issues", warning));
    s.lastReview = struct("rounds", round, "unverified", warning ~= "", "issues", warning);
    if warning == "" || round == cfg.criticRounds
        return
    end
    % One rewrite, asked of a copy of the history so the feedback message is not kept
    h = addUserMessage(s.history, replace(parts(end), "{problem}", warning));
    [text, out] = s.llm(h, true, []);
    text = fomc.llm.cleanText(string(text));
    if text == "" || (isfield(out, "tool_calls") && ~isempty(out.tool_calls))
        return   % no usable rewrite: keep the draft, marked unverified
    end
    s.history = addResponseMessage(removeMessage(s.history, numel(s.history.Messages)), ...
        struct("role", "assistant", "content", text));
    answer = text;
end
end
