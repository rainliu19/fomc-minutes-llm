function r = minutesRetriever(ctx, brief)
%MINUTESRETRIEVER The minutes retriever (stage 1): the decision card or best paragraphs, with ids.
%   r = fomc.agents.minutesRetriever(ctx, brief)
%   RAIN'S AGENT. The code that was in fomc.focus.minutesPrefetch is below, unchanged (the
%   local function lookup and its helpers); this function only wraps it in the agent contract
%   (docs/agents.md). It calls the same pieces as before: fomc.focus.window, fomc.tools.dispatch,
%   fomc.data.* and fomc.guard.*. Replace lookup, or this whole file, keeping this signature:
%   the code finds the paragraphs; the sub-agent (fomc.agents.subAgent, prompt in
%   agents/minutes.md and the page agents/minutes/<topic>.md the lookup chose) summarizes them with their ids. Set meetingDate ("YYYY-MM-DD" or "").
%   Only minutes released by ctx.asOf; every claim carries a paragraph id.

[text, recs, meeting, topic] = lookup(ctx, brief.question, brief.isAnalysis);
date = "";
if ~isnat(meeting)
    date = fomc.util.fmtDate(meeting);
end
r = fomc.agents.subAgent(ctx, brief, "minutes", text, recs, topic);
r.meetingDate = date;
end

function [text, recs, meeting, topic] = lookup(ctx, question, isAnalysis)
%LOOKUP The minutes lookups.
%   [text, recs, meeting, topic] = lookup(ctx, question, isAnalysis)
%
%   A small model sometimes skips a tool or invents a result, so for minutes questions:
%     next decision      what participants expected at the latest released meeting (topic "views")
%     decision or vote   the named (or latest) meeting's decision card (topic "decision"), or a plain
%                        "not public on the anchor date" if its minutes are not released
%     other              the best matching paragraphs, fomc.retrieve.rank (topic "passages")
%   text is added to the question; recs are tool-call records for the trace and the
%   citation check. Data-only questions get nothing. meeting: the meeting the text is about
%   (NaT when none). topic: which page of agents/minutes/ the sub-agent reads with its prompt.
%   This is the minutes retriever's lookup (fomc.agents.minutesRetriever).

% Nothing to do unless prefetch is on and the question is about the minutes
text = "";
meeting = NaT;
topic = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
q = lower(string(question));
M = ctx.D.meetings;
% "In December 2015, what happened to the federal funds rate target?" is about a decision, though it
% says nothing of the Committee; a rate question that names no meeting is a data question
named = ~isempty(regexp(q, monthYear() + "|20\d\d-\d\d-\d\d", "once"));
rateTarget = named && contains(q, ["federal funds rate" "policy rate" "target range" "rate target"]);
if ~ctx.cfg.prefetch || ~(fomc.focus.aboutMinutes(question) || isAnalysis || rateTarget)
    return
end

% A question about the next decision: what participants expected, not the last decision
latest = latestReleased(M, ctx);
if fomc.focus.asksNextMove(q) && ~isempty(latest)
    V = fomc.data.policyViews(ctx.D, find(M.MeetingDate == latest, 1));
    if ~isempty(V.views)
        [text, recs] = viewsLookup(ctx, V);
        meeting = latest;
        topic = "views";
        fomc.trace.logEvent(ctx, "prefetch", struct("kind", "views", "meeting", fomc.util.fmtDate(latest)));
        return
    end
end

% Does the question ask about a decision or vote?
decisionIntent = isAnalysis || rateTarget || ~isempty(regexp(q, ...
    "(?<![a-z])(decid\w*|decision|vote\w*|dissent\w*|rais\w*|hike\w*|cut|cuts|lower\w*|hold|held|unchanged)(?![a-z])", "once"));

% Yes: find which meeting it means
if decisionIntent
    [target, found, why] = pickMeeting(q, M, ctx);
    % That meeting's minutes are not public yet: tell the model to say so
    if found == "unreleased"
        avail = "No minutes have been released yet.";      % before the first release there is no latest meeting
        if ~isempty(latest)
            avail = "The latest minutes available are for the meeting that ended " + fomc.util.fmtDate(latest) + ".";
        end
        text = "[" + why + " are not public on the anchor date, so there is no decision to report for it. " + avail + " Say this plainly.]";
        % The record holds the sentence the reader sees: the harness answers this case itself
        reply = why + " are not public as of " + fomc.util.fmtDate(ctx.asOf) + ", so there is no decision to report for it. " + avail;
        recs(end+1) = struct("name", "prefetchNotice", "args", struct(), "result", reply, "ok", true, "ms", 0);
        return
    % Found: fetch its decision card through the normal tool path (guardrails and trace apply)
    elseif found == "yes"
        [json, rec] = fomc.tools.dispatch(ctx, "getDecision", struct("meetingDate", char(fomc.util.fmtDate(target))));
        recs(end+1) = rec;
        if rec.ok
            text = cardText(jsondecode(json));
            meeting = target;
            topic = "decision";
            fomc.trace.logEvent(ctx, "prefetch", struct("kind", "decision", "meeting", fomc.util.fmtDate(target)));
            return
        end
    end
end

% Otherwise: the best matching paragraphs
% Build the lookup record that is traced and used to verify citations
t0 = tic;
hits = fomc.retrieve.rank(question, ctx, ctx.cfg.prefetchHits);
if ~isempty(hits)
    lines = strings(numel(hits), 1);
    for i = 1:numel(hits)
        lines(i) = sprintf("%d. [%s] %s", i, hits(i).id, hits(i).snippet);
    end
    text = "[Passages found by code in the minutes (cite their ids; call searchMinutes or readMinutes for more):" + ...
        newline + strjoin(lines, newline) + "]";
    recs(end+1) = struct("name", "prefetchPassages", "args", struct("query", string(question)), ...
        "result", string(jsonencode(struct("hits", {num2cell(hits)}))), "ok", true, "ms", round(toc(t0) * 1000));
    topic = "passages";
    fomc.trace.logEvent(ctx, "prefetch", struct("kind", "passages", "ids", [hits.id]));
end
end

function [text, recs] = viewsLookup(ctx, V)
% What participants expected for the next meetings, the most widely held views first, each with its id.
% Recorded like passages found by code, so the citation check accepts their ids.
n = min(numel(V.views), ctx.cfg.prefetchHits);
hits = struct("id", cell(1, n), "snippet", "");
lines = strings(n, 1);
for i = 1:n
    v = V.views{i};
    hits(i) = struct("id", v.id, "snippet", v.text);
    lines(i) = sprintf("- Held by %s (leans: %s): %s [%s]", v.share, v.lean, v.text, v.id);
end
text = "[What participants said about future rate moves at the meeting that ended " + V.meetingDate + ", read from the minutes by code (the lean: " + ...
    V.lean + "). Cite their ids; never answer yes or no:" + newline + strjoin(lines, newline) + "]";
recs = struct("name", "prefetchPassages", "args", struct("query", "views"), "result", string(jsonencode(struct("hits", {num2cell(hits)}))), "ok", true, "ms", 0);
end

function p = monthYear()
% A month and a year in a question ("March 2020"): the month's first letters, then the year
p = "(?<![a-z])(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s*,?\s*(20\d\d)";
end

function [target, found, why] = pickMeeting(q, M, ctx)
% Which meeting does the question mean? found: "yes", "unreleased" or "none".
target = NaT; found = "none"; why = "";
% Look for a month and year ("March 2020") or an ISO date in the question
mon = regexp(q, monthYear(), "tokens", "once");
iso = regexp(q, "20\d\d-\d\d-\d\d", "match", "once");
% An exact date was given
if strlength(string(iso)) > 0          % a string input returns "" (not empty) when nothing matches
    d = fomc.util.parseDate(iso);
    k = find(M.MeetingDate == d, 1);
    if ~isempty(k)
        target = M.MeetingDate(k);
        found = ternary(M.ReleaseDate(k) <= ctx.asOf, "yes", "unreleased");
        why = "The minutes of the meeting that ended " + fomc.util.fmtDate(d);
    end
% A month and year was given: find the meeting in that month
elseif ~isempty(mon)
    months = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"];
    m = find(months == extractBefore(string(mon{1}) + "   ", 4), 1);
    y = str2double(mon{2});
    k = find(month(M.MeetingDate) == m & year(M.MeetingDate) == y, 1);
    if ~isempty(k)
        target = M.MeetingDate(k);
        found = ternary(M.ReleaseDate(k) <= ctx.asOf, "yes", "unreleased");
        why = "The minutes of the " + datestr(M.MeetingDate(k), "mmmm yyyy") + " meeting"; %#ok<DATST>
    end
% No date, or "latest": the most recent released meeting
elseif ~isempty(regexp(q, "(latest|last|most recent|current|newest|recent)", "once")) || isempty(regexp(q, "20\d\d", "once"))
    target = latestReleased(M, ctx);
    found = "yes";
end
end

function d = latestReleased(M, ctx)
d = max(M.MeetingDate(M.ReleaseDate <= ctx.asOf));
end

function v = ternary(cond, a, b)
if cond, v = a; else, v = b; end
end

function t = cardText(r)
% The decision card as a few short lines for the model.
% Turn the decision result into a few short lines
action = r.action;
if isfield(r, "targetRange")
    action = action + " (target range " + r.targetRange + ", copy it exactly as written)";
end
lines = "[Decision card for the meeting that ended " + r.meetingDate + ", read from the minutes by code (cite the ids):";
lines(end+1) = "- Action: " + action;
if isfield(r, "decision")
    lines(end+1) = "- Decision sentence: " + r.decision.text + " [" + r.decision.id + "]";
end
if isfield(r, "vote")
    unan = "";
    if r.vote.unanimous, unan = " (unanimous)"; end
    lines(end+1) = "- Vote: " + r.vote.nFor + " for, " + r.vote.nAgainst + " against" + unan + ". For: " + ...
        r.vote.for + ". Against: " + r.vote.against + " [" + r.vote.id + "]";
end
if isfield(r, "dissent")
    lines(end+1) = "- Dissent: " + r.dissent.text + " [" + r.dissent.id + "]";
end
t = strjoin(lines, newline) + "]";
end
