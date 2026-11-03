function [text, recs] = prefetch(ctx, question, isAnalysis, followsRatePath)
%PREFETCH Lookups the harness does before the model starts: minutes, data, rate path, economy, outlook.
%   [text, recs] = fomc.focus.prefetch(ctx, question, isAnalysis, followsRatePath)
%   The minutes part is below; the data part is fomc.focus.dataPrefetch (figures for series
%   the question is about); the path part is fomc.focus.pathPrefetch (how rates moved, for
%   questions that ask, or for a follow-up when followsRatePath is true; default false); the
%   economy part is fomc.focus.economyPrefetch (the economy against the Fed's goals, for
%   questions about where policy should go); the outlook part is fomc.focus.outlookPrefetch
%   (what the rate path may mean ahead, for questions about its effects; left out when the
%   economy part answers a question only about the next decisions; with it, the data part leaves
%   out the series it gives). All are added to the question, in that order.

if nargin < 4
    followsRatePath = false;
end
[text, recs] = minutesPrefetch(ctx, question, isAnalysis);
[pathText, pathRecs] = fomc.focus.pathPrefetch(ctx, question, followsRatePath);
[economyText, economyRecs] = fomc.focus.economyPrefetch(ctx, question);
% A question about the next decisions gets the economy part alone, unless it also names an effect on
% households: given both, Qwen3 4B blended them, answering "What do current economic conditions and
% the latest Fed minutes mean for the next FOMC meeting?" with earlier runs since 1990 and the
% 2-year yield in place of the next-meeting reading
outlookText = "";
outlookRecs = recs([]);
if economyText == "" || ~onlyAboutDecisions(lower(string(question)))
    [outlookText, outlookRecs] = fomc.focus.outlookPrefetch(ctx, question);
end
% With the outlook evidence, the data part leaves out the series it already gives (and real GDP's
% level): given both, Qwen3 4B quoted spending as raw index levels (16530 to 16955) and called it faster
skip = strings(0, 1);
if outlookText ~= ""
    skip = ["DGS2"; "DGS10"; "MORTGAGE30US"; "BAA10Y"; "PCEC96"; "PCEPILFE"; "MICH"; "TREASURY_AVG_RATE"; "GDPC1"];
end
[dataText, dataRecs] = fomc.focus.dataPrefetch(ctx, question, skip);
[text, recs] = addLookup(text, recs, dataText, dataRecs);
[text, recs] = addLookup(text, recs, pathText, pathRecs);
[text, recs] = addLookup(text, recs, economyText, economyRecs);
[text, recs] = addLookup(text, recs, outlookText, outlookRecs);
end

function tf = onlyAboutDecisions(q)
% The next or future Fed decisions, with no effect on borrowing, spending or prices named
decisions = "(next|future|upcoming|coming) (fomc |fed )?(meetings?|decisions?|moves?|steps?)|" + ...
    "(should|will|would|could|might) the (fed|fomc|committee) (raise|cut|lower|hike|hold|increase|tighten|ease|pause|keep|change|do)|" + ...
    "what (should|will|would|could|might) the (fed|fomc|committee) do";
effects = "mortgage|borrow\w*|loans?(?![a-z])|credit|debt|spending|consum\w*|households?|housing|" + ...
    "(?<![a-z])(house|homes?)(?![a-z])|inflation|(?<![a-z])prices|cost of living|wages?(?![a-z])|jobs?(?![a-z])|unemployment";
tf = ~isempty(regexp(q, decisions, "once")) && isempty(regexp(q, effects, "once"));
end

function [text, recs] = addLookup(text, recs, more, moreRecs)
% Append one lookup's text (on its own line) and its records, if it found anything
if more == ""
    return
end
if text == ""
    text = more;
else
    text = text + newline + more;
end
recs = [recs, moreRecs];
end

function [text, recs] = minutesPrefetch(ctx, question, isAnalysis)
%MINUTESPREFETCH The minutes lookups.
%   [text, recs] = fomc.focus.prefetch(ctx, question, isAnalysis)
%
%   A small model sometimes skips a tool or invents a result, so for minutes questions:
%     decision or vote   the named (or latest) meeting's decision card, or a plain "not
%                        public on the anchor date" if its minutes are not released
%     other              the best matching paragraphs (fomc.retrieve.rank)
%   text is added to the question; recs are tool-call records for the trace and the
%   citation check. Data-only questions get nothing.

% Nothing to do unless prefetch is on and the question is about the minutes
text = "";
recs = struct("name", {}, "args", {}, "result", {}, "ok", {}, "ms", {});
if ~ctx.cfg.prefetch || ~(fomc.focus.aboutMinutes(question) || isAnalysis)
    return
end

% Does the question ask about a decision or vote?
q = lower(string(question));
M = ctx.D.meetings;
decisionIntent = isAnalysis || ~isempty(regexp(q, ...
    "(?<![a-z])(decid\w*|decision|vote\w*|dissent\w*|rais\w*|hike\w*|cut|cuts|lower\w*|hold|held|unchanged)(?![a-z])", "once"));

% Yes: find which meeting it means
if decisionIntent
    [target, found, why] = pickMeeting(q, M, ctx);
    % That meeting's minutes are not public yet: tell the model to say so
    if found == "unreleased"
        latest = latestReleased(M, ctx);
        text = "[" + why + " are not public on the anchor date, so there is no decision to report for it. " + ...
            "The latest minutes available are for the meeting that ended " + fomc.util.fmtDate(latest) + ". Say this plainly.]";
        % The record holds the sentence the reader sees: the harness answers this case itself
        reply = why + " are not public as of " + fomc.util.fmtDate(ctx.asOf) + ", so there is no decision to report for it. " + ...
            "The latest minutes available are for the meeting that ended " + fomc.util.fmtDate(latest) + ".";
        recs(end+1) = struct("name", "prefetchNotice", "args", struct(), "result", reply, "ok", true, "ms", 0);
        return
    % Found: fetch its decision card through the normal tool path (guardrails and trace apply)
    elseif found == "yes"
        [json, rec] = fomc.tools.dispatch(ctx, "getDecision", struct("meetingDate", char(fomc.util.fmtDate(target))));
        recs(end+1) = rec;
        if rec.ok
            text = cardText(jsondecode(json));
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
    fomc.trace.logEvent(ctx, "prefetch", struct("kind", "passages", "ids", [hits.id]));
end
end

function [target, found, why] = pickMeeting(q, M, ctx)
% Which meeting does the question mean? found: "yes", "unreleased" or "none".
target = NaT; found = "none"; why = "";
% Look for a month and year ("March 2020") or an ISO date in the question
mon = regexp(q, "(?<![a-z])(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s*,?\s*(20\d\d)", "tokens", "once");
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
