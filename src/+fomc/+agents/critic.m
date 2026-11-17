function [s, answer] = critic(s, msg, answer, calls)
%CRITIC Check the writer's answer in code; on a failure ask for one rewrite (Generator-Critic call loop).
%   [s, answer] = fomc.agents.critic(s, msg, answer, calls)
%   Each round runs fomc.guard.review (paragraph ids, citations, figures, plain words), which
%   is code only and sees the answer, not the writer's conversation. If it fails, the writer
%   gets agents/organizer.md's "Critic" message once and the rewrite replaces the draft in the
%   history (the message itself is not kept). Rounds are capped by cfg.criticRounds in code: the
%   draft is round 1, so the default 2 allows one rewrite. An answer that still fails is
%   marked unverified in s.lastReview (the critic trace events carry the same), never looped on.
%   The rewrite is the writer's call (it shows in the writer's column, from the critic).

cfg = s.ctx.cfg;
s.lastReview = struct("rounds", 0, "unverified", false, "issues", "", "fromCode", false);
% A turn that failed was rolled back: its message is not the last one, so there is nothing to check
if isempty(s.history.Messages) || string(s.history.Messages{end}.content) ~= answer
    return
end
c = fomc.agents.catalog();
parts = split(strip(c([c.name] == "organizer").body), compose("\n\n"));
for round = 1:cfg.criticRounds
    [~, ~, warning] = fomc.guard.review(answer, s, calls, msg, "chat", []);
    problem = fomc.guard.draftProblem(answer, calls, msg);   % no words, or against the decision card
    if problem ~= ""
        warning = problem;
    end
    voice = s.ctx;
    voice.agent = "critic";
    fomc.trace.logEvent(voice, "critic", struct("round", round, "pass", warning == "", "issues", warning));
    s.lastReview = struct("rounds", round, "unverified", warning ~= "", "issues", warning, "fromCode", false);
    if warning == ""
        return
    end
    if round == cfg.criticRounds
        if problem ~= ""
            [s, answer] = answerFromCode(s, answer, calls, round, voice);
        end
        return
    end
    % One rewrite, asked of a copy of the history so the feedback message is not kept
    h = addUserMessage(s.history, replace(parts(end), "{problem}", warning));
    [text, out] = fomc.trace.llmCall(s, h, true, [], From="critic", Round=round);
    text = fomc.llm.cleanText(string(text));
    % A rewrite sometimes opens by apologising to the critic; the reader should not see that
    text = strip(regexprep(text, "^(Apologies|Sorry|I apologi[sz]e)[^.!\n]*[.!]\s*(Here(?:'s| is) the (?:revised|corrected|updated)[^:\n]*:\s*)?", ""));
    if text == "" || (isfield(out, "tool_calls") && ~isempty(out.tool_calls))
        if problem ~= ""
            [s, answer] = answerFromCode(s, answer, calls, round, voice);
        end
        return   % no usable rewrite: keep the draft, marked unverified
    end
    s.history = addResponseMessage(removeMessage(s.history, numel(s.history.Messages)), ...
        struct("role", "assistant", "content", text));
    answer = text;
end
end

function [s, answer] = answerFromCode(s, answer, calls, round, voice)
% The draft has no words or contradicts the card, and no rewrite fixed it: answer with what the code found
text = fomc.guard.cardAnswer(calls);
if text == ""
    return
end
s.history = addResponseMessage(removeMessage(s.history, numel(s.history.Messages)), struct("role", "assistant", "content", text));
answer = text;
s.lastReview = struct("rounds", round, "unverified", false, "issues", "", "fromCode", true);
fomc.trace.logEvent(voice, "critic", struct("round", round, "pass", true, "issues", "", "fromCode", true));
end
