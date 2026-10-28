function [s, answer, structured, calls] = runTurn(s, userMsg, nvp)
%RUNTURN One user turn: call the model, run its tools, repeat until it answers.
%   [s, answer, structured, calls] = fomc.runTurn(s, userMsg, Format="chat" | "analysis")
%
%   The course's harness loop, by hand: the model asks for tools, this function runs them
%   (through fomc.tools.dispatch, which applies the guardrails), appends each result with
%   its call id, and calls the model again, until it replies without tool calls or after
%   cfg.maxToolRounds. "analysis" then writes and checks the structured analysis
%   (fomc.analysis.structure); structured is [] in chat mode. calls: one record per tool
%   call (name, args, result, ok, ms). A failed turn is rolled back so the session stays valid.

arguments
    s (1,1) struct
    userMsg (1,1) string
    nvp.Format (1,1) string {mustBeMember(nvp.Format, ["chat", "analysis"])} = "chat"
end

% Set up: pick the focus window for this question, and keep the history so a failed turn can be undone
ctx = s.ctx;
ctx.focus = fomc.focus.window(userMsg, ctx.asOf, ctx.cfg);
s.ctx = ctx;
before = s.history;
structured = [];
calls = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});

fomc.trace.logEvent(ctx, "user_message", struct("text", userMsg, ...
    "focusStart", fomc.util.fmtDate(ctx.focus.start), "focusEnd", fomc.util.fmtDate(ctx.focus.end), ...
    "focusReason", ctx.focus.reason));

% Skill-matched scoring requests use the dedicated structured scorer and validation loop.
if fomc.focus.wantsScoring(userMsg)
    [s, answer, structured] = scoreWithSkill(s, userMsg);
    fomc.trace.logEvent(ctx, "final_answer", struct("text", answer, ...
        "nToolCalls", 0, "finished", isstruct(structured) && isfield(structured, "ok") && structured.ok));
    return
end

% Build the message the model will see: the question plus the focus note
question = userMsg + newline + newline + fomc.focus.note(ctx);
% Let the harness look up the decision card or best passages itself, so a small model cannot skip it.
% After a question about how rates moved, a follow-up that only changes the period gets the rate path too.
followsRatePath = isfield(s, "lastUsedRatePath") && s.lastUsedRatePath;
[found, pre] = fomc.focus.prefetch(ctx, userMsg, nvp.Format == "analysis", followsRatePath);
if found ~= ""
    question = question + newline + found;
    for k = 1:numel(pre)
        calls(end+1) = pre(k); %#ok<AGROW>
        s.known = union(s.known, fomc.guard.idsIn(pre(k).result));
    end
end
% Minutes that are not public yet: answer directly. The model is not asked, so it cannot invent a decision.
isNotice = ~isempty(pre) && any(string({pre.name}) == "prefetchNotice");
if isNotice
    answer = pre(find(string({pre.name}) == "prefetchNotice", 1)).result;
    first = userMsg;
    if isempty(s.history.Messages)
        first = s.contextBlock + newline + newline + userMsg;
    end
    s.history = addUserMessage(s.history, first);
    s.history = addResponseMessage(s.history, struct("role", "assistant", "content", answer));
    s.lastUsedRatePath = false;
    fomc.trace.logEvent(ctx, "final_answer", struct("text", answer, "nToolCalls", numel(calls), "finished", true));
    return
end
if nvp.Format == "analysis"
    % The analysis is written in a later call, so skip the free-text draft
    question = question + newline + "(Use the information above and the tools to gather evidence. " + ...
        "Do not write the answer yet: when you have what you need, reply with just: READY)";
end
% On the first message of a session, put the anchor date and data snapshot in front
if isempty(s.history.Messages)
    question = s.contextBlock + newline + newline + question;   % anchor date and data go first
end
% Add the message to the conversation
s.history = addUserMessage(s.history, question);

% Loop state: the final answer, whether the model finished, whether we already pushed back
answer = "";
finished = false;
nudged = false;
% Minutes questions need the minutes read, in either mode
aboutMinutes = nvp.Format == "analysis" || fomc.focus.aboutMinutes(userMsg);
% Main loop: ask the model; if it asks for tools, run them and ask again; stop when it answers
try
    for iter = 1:ctx.cfg.maxToolRounds
        % If the conversation is nearing the model's window, swap old tool results for short stubs
        if fomc.history.estimateTokens(s.history, s.systemPrompt) > ctx.cfg.compactAtTokens
            [compacted, nReplaced] = fomc.history.compact(s.history, 1);
            if nReplaced > 0
                s.history = compacted;
                fomc.trace.logEvent(ctx, "compact", struct("replaced", nReplaced));
            end
        end
        % Ask the model, then record what it said and how long it took
        t0 = tic;
        [text, out, stats] = s.llm(s.history, true, []);
        tcs = toolCallsOf(out);
        content = cleanText(string(text));
        fomc.trace.logEvent(ctx, "model_response", struct("round", iter, ...
            "content", content, "nToolCalls", numel(tcs), ...
            "thinking", clip(thinkingOf(out), 4000), "ms", round(toc(t0) * 1000), "stats", stats));

        % Add the model's reply (text and any tool calls) to the conversation
        msg = struct("role", "assistant", "content", content);
        if ~isempty(tcs)
            msg.tool_calls = tcs;
        elseif strlength(content) == 0
            msg.content = "(The model returned no text.)";
            content = msg.content;
        end
        s.history = addResponseMessage(s.history, msg);

        % No tool calls means the model is trying to answer
        if isempty(tcs)
            if ~nudged && aboutMinutes && ~any(ismember(string({calls.name}), ["getDecision", "readMinutes", "searchMinutes", "prefetchPassages", "prefetchNotice"]))
                % A claim about the minutes must rest on minutes the model read: push back once.
                nudged = true;
                s.history = addUserMessage(s.history, "You have not read any minutes yet, so nothing you said " + ...
                    "about them is backed by the text. Use getDecision for a decision or vote, or searchMinutes " + ...
                    "and readMinutes for anything else, then answer only from what you read. " + ...
                    "Do not say anything is unavailable until a tool has told you so.");
                fomc.trace.logEvent(ctx, "nudge", struct("round", iter));
                continue
            end
            answer = content;
            finished = true;
            break
        end
        % The model asked for tools: run each one (guardrails apply) and add its result to the conversation
        for k = 1:numel(tcs)
            [json, rec] = fomc.tools.dispatch(ctx, tcs(k).function.name, tcs(k).function.arguments);
            calls(end+1) = rec; %#ok<AGROW>
            s.known = union(s.known, fomc.guard.idsIn(rec.result));
            s.history = addToolMessage(s.history, tcs(k).id, tcs(k).function.name, json);
        end
    end
    % Analysis mode: now write and check the structured analysis
    if finished && nvp.Format == "analysis"
        [s, structured] = fomc.analysis.structure(s, calls);
    end
    % Remember whether this answer used the rate path (looked up first or called by the model)
    if finished
        s.lastUsedRatePath = any(string({calls.name}) == "getPolicyPath" & [calls.ok]);
    end
    % Ran out of rounds: undo this turn so the session stays usable
    if ~finished
        s.history = before;
        answer = "Sorry, I hit my tool-call limit (" + ctx.cfg.maxToolRounds + " rounds) before finishing. Try a narrower question.";
        fomc.trace.logEvent(ctx, "round_cap", struct("rounds", ctx.cfg.maxToolRounds));
    end
% Any failure (for example Ollama not running): undo the turn and report the error
catch ME
    s.history = before;
    msg = fomc.trace.scrub(string(ME.message));
    answer = "Model call failed: " + clip(msg, 300);
    fomc.trace.logEvent(ctx, "turn_error", struct("identifier", string(ME.identifier), "message", msg));
end
% Record the outcome in the trace
fomc.trace.logEvent(ctx, "final_answer", struct("text", answer, "nToolCalls", numel(calls), "finished", finished));
end

function [s, answer, output] = scoreWithSkill(s, userMsg)
% Route one or more requested meeting dates to the validated score skill.
text = char(userMsg);
dateMatches = regexp(text, '\d{4}-\d{2}-\d{2}', 'match');
dates = unique(string(dateMatches(:)), "stable");
isComparison = any(contains(lower(userMsg), ["compare", "comparison", "versus", " vs "]));
asksLatest = ~isempty(regexpi(text, '(?<![a-z])latest(?![a-z])', 'once'));
if isComparison && asksLatest
    dates = unique([dates(:); latestReleasedMeetingDate(s)], "stable");
end
if isComparison && numel(dates) < 2
    answer = "To compare FOMC scores, include at least two distinct meeting dates (YYYY-MM-DD), or pair one date with 'latest'.";
    output = struct("skill", "fomc-score", "ok", false, "issues", answer, ...
        "failedDimensions", strings(0, 1), "attempts", 0);
else
    try
        if numel(dates) <= 1
            meetingDate = "";
            if ~isempty(dates)
                meetingDate = dates(1);
            end
            output = fomc.skills.scoreMeeting(s, meetingDate);
            output.skill = "fomc-score";
            answer = string(jsonencode(output.score));
        else
            scores = cell(numel(dates), 1);
            validation = cell(numel(dates), 1);
            allIssues = strings(0, 1);
            failedDimensions = strings(0, 1);
            attempts = 0;
            ok = true;
            for i = 1:numel(dates)
                result = fomc.skills.scoreMeeting(s, dates(i));
                scores{i} = result.score;
                validation{i} = struct("meeting_date", string(result.score.meeting_date), ...
                    "ok", result.ok, "issues", result.issues, ...
                    "failedDimensions", result.failedDimensions, "attempts", result.attempts);
                ok = ok && result.ok;
                attempts = attempts + result.attempts;
                allIssues = [allIssues; string(result.score.meeting_date) + ": " + result.issues(:)]; %#ok<AGROW>
                failedDimensions = union(failedDimensions, result.failedDimensions, "stable");
            end
            output = struct("skill", "fomc-score", "scores", {scores}, "validation", {validation}, ...
                "ok", ok, "issues", allIssues, "failedDimensions", failedDimensions, ...
                "attempts", attempts);
            answer = string(jsonencode(output));
        end
    catch ME
        issue = "Scoring failed: " + fomc.trace.scrub(string(ME.message));
        output = struct("skill", "fomc-score", "ok", false, "issues", issue, ...
            "failedDimensions", strings(0, 1), "attempts", 0);
        answer = string(jsonencode(output));
        fomc.trace.logEvent(s.ctx, "skill_score_error", struct("message", issue));
    end
end

s.history = addUserMessage(s.history, userMsg);
s.history = addResponseMessage(s.history, struct("role", "assistant", "content", answer));
end

function meetingDate = latestReleasedMeetingDate(s)
% Resolve "latest" using the same release-date rule as scoreMeeting.
M = s.ctx.D.meetings;
available = find(M.ReleaseDate <= s.ctx.asOf);
if isempty(available)
    error("fomc:skills:noReleasedMeetings", "No meeting minutes were released by the anchor date.");
end
[~, order] = sort(M.ReleaseDate(available), "descend");
meetingDate = fomc.util.fmtDate(M.MeetingDate(available(order(1))));
end

function tcs = toolCallsOf(out)
% Tool calls from the add-on's reply, as a struct array with id and function.
tcs = [];
if ~isfield(out, "tool_calls") || isempty(out.tool_calls)
    return
end
% The add-on may return a cell array: make it a struct array
tcs = out.tool_calls;
if iscell(tcs)
    tcs = [tcs{:}];
end
% Give any call without an id one, so its result can be matched to it
for k = 1:numel(tcs)
    if ~isfield(tcs, "id") || isempty(tcs(k).id)
        tcs(k).id = "call_" + k;
    end
end
end

function t = thinkingOf(out)
% The model's separate 'thinking' text, if it sent any
t = "";
if isfield(out, "thinking") && ~isempty(out.thinking)
    t = string(out.thinking);
end
end

function t = cleanText(t)
% Drop any inline <think>...</think> block.
t = strtrim(regexprep(t, "<think>.*?</think>", ""));
end

function t = clip(t, n)
% Shorten text to n characters for the log
t = string(t);
if strlength(t) > n
    t = extractBefore(t, n + 1) + "...";
end
end
