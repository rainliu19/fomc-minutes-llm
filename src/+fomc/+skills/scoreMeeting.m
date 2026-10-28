function output = scoreMeeting(s, meetingDate)
%SCOREMEETING Generate and validate one meeting's FOMC-score skill output, one dimension at a time.
%   output = fomc.skills.scoreMeeting(s) scores the latest released meeting.
%   output = fomc.skills.scoreMeeting(s, meetingDate) scores a specific YYYY-MM-DD.
%   output.score contains the model result; output.ok and output.issues report validation;
%   output.attempts is the most attempts any dimension needed (1 to 3); output.calls counts
%   the model calls; output.passages lists, per dimension, the paragraph ids the model read.
%
%   The skill's instructions, all seven rubrics and the full minutes come to about 17,000
%   tokens, and the local models read 8,192 (num_ctx in models/*/Modelfile); Ollama cuts a
%   longer prompt without an error. So each dimension is scored in its own call, with the
%   shared scale, the skill's rules, that dimension's rubric and the paragraphs of the minutes
%   about it: code ranks the paragraphs by the dimension's words, Participants' Views first,
%   and keeps the best that fit. The model quotes the sentences that justify its score; code
%   matches each quote to the closest sentence of the passages (by shared words) and uses that
%   sentence, cut to 40 words, so every quote is word for word from the minutes. Asked to copy
%   quotes exactly, Qwen3 4B reworded them in 4 of 7 dimensions of the September 2026 minutes
%   and repeated the same text on each retry; asked instead to name numbered sentences, it chose
%   poorly (a labor market sentence for inflation) and once wrote "S1999..." without end. The
%   model reads, judges and picks the evidence; code picks what it reads and checks what it
%   returns (fomc.guard.validateScores). A dimension no paragraph mentions is not_discussed
%   without a model call.

ctx = s.ctx;
M = ctx.D.meetings;
available = find(M.ReleaseDate <= ctx.asOf);
if isempty(available)
    error("fomc:skills:noReleasedMeetings", "No meeting minutes were released by the anchor date.");
end
if strlength(strtrim(meetingDate)) == 0
    [~, order] = sort(M.ReleaseDate(available), "descend");
    row = available(order(1));
    meetingDate = fomc.util.fmtDate(M.MeetingDate(row));
else
    d = fomc.util.parseDate(meetingDate);
    if isnat(d)
        error("fomc:skills:invalidMeetingDate", "meetingDate must be written YYYY-MM-DD.");
    end
    row = find(M.MeetingDate == d & M.ReleaseDate <= ctx.asOf, 1);
    if isempty(row)
        error("fomc:skills:meetingUnavailable", ...
            "No minutes for meeting %s are available by anchor date %s.", meetingDate, fomc.util.fmtDate(ctx.asOf));
    end
    meetingDate = fomc.util.fmtDate(d);
end

releaseDate = fomc.util.fmtDate(M.ReleaseDate(row));
P = ctx.D.paras(ctx.D.paras.meetingIdx == row, :);
% Quotes are checked against the whole minutes and every paragraph a passage can come from
minutesText = string(M.Body(row)) + newline + strjoin(string(P.text), newline);
scale = fomc.skills.read("fomc-score", "rubric/00_scale.md");
rules = rulesOf(fomc.skills.read("fomc-score"));
dimSchema = dimensionSchema(fomc.skills.read("fomc-score", "schema.json"));
systemChars = strlength(fomc.systemPrompt());
if isfield(s, "systemPrompt")
    systemChars = strlength(s.systemPrompt);
end
maxOut = 700;
if isfield(ctx, "cfg") && isfield(ctx.cfg, "maxTokensAnalysis")
    maxOut = ctx.cfg.maxTokensAnalysis;
end

dims = dimensionList();
score = struct("meeting_date", meetingDate, "scale", "hawkish_positive", "dimensions", struct());
for i = 1:height(dims)
    score.dimensions.(dims.key(i)) = placeholder();
end
passages = struct();
unscored = strings(0, 1);
maxAttempts = 3;
attemptsUsed = 0;
calls = 0;
for i = 1:height(dims)
    key = dims.key(i);
    rubric = fomc.skills.read("fomc-score", "rubric/" + dims.rubric(i));
    task = "Score one dimension of the FOMC minutes of the meeting that ended " + meetingDate + ...
        " (released " + releaseDate + "): " + dims.title(i) + ". Use only the passages below, which " + ...
        "code selected from these minutes as the ones about this topic, and no later knowledge. Return " + ...
        "only a JSON object for this one dimension that matches the supplied schema: status, score (-1 " + ...
        "to 1 in steps of 0.25, or null when not_discussed), confidence (null when not_discussed), a " + ...
        "rationale of one or two short sentences (under 60 words) about the minutes, and evidence: 1 to 3 quotes of sentences from the passages that justify the score (none " + ...
        "when not_discussed).";
    fixed = task + "SCALE" + scale + "RULES" + rules + "RUBRIC" + rubric;
    % What is left of the window for passages, keeping room for two answers and a retry note
    budget = floor((8192 - 2 * maxOut - 300) * 3.3) - systemChars - strlength(fixed);
    [text, ids, sentences] = selectPassages(P, dims.words(i), dims.sections(i), budget);
    passages.(key) = ids;
    if isempty(ids)
        score.dimensions.(key) = struct("status", "not_discussed", "score", [], "confidence", [], ...
            "rationale", "No paragraph of these minutes is about this topic.", "evidence", {{}});
        continue
    end
    prompt = task + newline + newline + "SCALE" + newline + scale + newline + newline + "RULES" + newline + ...
        rules + newline + newline + "RUBRIC" + newline + rubric + newline + newline + "PASSAGES" + newline + text;
    history = addUserMessage(messageHistory, prompt);
    for attempt = 1:maxAttempts
        t0 = tic;
        [reply, ~, stats] = s.llm(history, false, dimSchema);
        calls = calls + 1;
        content = strtrim(string(reply));
        try
            [candidate, unknown] = withQuotes(jsondecode(content), sentences);
            trial = score;
            trial.dimensions.(key) = candidate;
            failures = fomc.guard.validateScores(trial, minutesText, meetingDate, ctx.D);
            failures = [key + ": " + unknown; failures(contains(failures, key))];
        catch ME
            candidate = struct();
            failures = key + ": the model response was not valid JSON: " + string(ME.message);
            fomc.trace.logEvent(ctx, "skill_score_bad_json", struct("dimension", key, "attempt", attempt, ...
                "start", extractBefore(content, min(strlength(content), 400) + 1), ...
                "end", extractAfter(content, max(strlength(content) - 300, 0))));
        end
        fomc.trace.logEvent(ctx, "skill_score_validation", struct("meetingDate", meetingDate, ...
            "releaseDate", releaseDate, "dimension", key, "attempt", attempt, "ok", isempty(failures), ...
            "issues", failures, "passages", ids, "ms", round(toc(t0) * 1000), "stats", stats));
        if isstruct(candidate) && ~isempty(fieldnames(candidate))
            score.dimensions.(key) = candidate;
        end
        if isempty(failures) || attempt == maxAttempts
            break
        end
        history = addResponseMessage(history, struct("role", "assistant", "content", content));
        history = addUserMessage(history, "These checks failed: " + strjoin(failures, " ") + ...
            " Return the corrected JSON object for this dimension, quoting sentences from the passages.");
    end
    attemptsUsed = max(attemptsUsed, attempt);
    % Every attempt failed to give a usable answer: say so, rather than leave the placeholder
    if ~isempty(failures) && strlength(string(score.dimensions.(key).rationale)) == 0
        unscored(end+1, 1) = key + ": no valid score after " + attempt + " attempts (" + failures(end) + ")"; %#ok<AGROW>
    end
end

failures = [unscored; fomc.guard.validateScores(score, minutesText, meetingDate, ctx.D)];
output = struct("score", score, "ok", isempty(failures), "issues", failures, ...
    "failedDimensions", dimensionsInFailures(failures), "attempts", max(attemptsUsed, 1), ...
    "calls", calls, "passages", passages);
end

function T = dimensionList()
% Each dimension: its key, rubric file, title, the words that mark a paragraph about it, and
% the sections that state the Committee's view of it (read first)
key = ["rate_path"; "inflation"; "labor_market"; "economic_activity"; "financial_conditions"; ...
    "balance_sheet"; "risk_balance"];
rubric = ["ratePath.md"; "inflation.md"; "laborMarket.md"; "economicActivity.md"; ...
    "financialConditions.md"; "balanceSheet.md"; "riskBalance.md"];
title = ["the expected path of the policy rate"; "inflation and inflation expectations"; ...
    "the labor market"; "economic activity: growth, spending and output"; ...
    "financial conditions: markets, credit and financial stability"; ...
    "the balance sheet: asset purchases, runoff and reserves"; "the balance of risks participants emphasized"];
words = ["target range|federal funds rate|policy rate|monetary policy|firming|tightening|easing|accommodat|restrictive|rate increase|rate cut|rate hike"
    "inflation|price|pce|cpi|expectations"
    "labor|employment|unemployment|jobs|job gains|payroll|wage|hiring"
    "gdp|economic activity|growth|spending|investment|output|housing|production|consumer"
    "financial conditions|credit|equity|stock|spread|yield|lending|financial stability|borrowing|dollar"
    "balance sheet|securities holdings|asset purchases|purchases|runoff|reinvest|reserves|soma|mortgage-backed"
    "risk|uncertain|upside|downside|tilted|balanced"];
sections = ["participantsViews|policyAction"; "participantsViews"; "participantsViews"; "participantsViews"; ...
    "participantsViews|financialMarkets"; "participantsViews|policyAction"; "participantsViews"];
T = table(key, rubric, title, words, sections);
end

function [text, ids, sentences] = selectPassages(P, words, sections, budget)
% The paragraphs about a dimension, best first, kept while they fit the budget, then put back in
% the order of the minutes, each after its id. A paragraph counts by how many of the words it
% holds; one in a section that states the Committee's view counts double. sentences: id (S1,
% ...), text and paragraph of every sentence shown, for matching the model's quotes.
text = "";
ids = strings(0, 1);
sentences = table(strings(0, 1), strings(0, 1), strings(0, 1), VariableNames=["id", "text", "paragraph"]);
if isempty(P) || budget <= 0
    return
end
hits = zeros(height(P), 1);
for w = split(words, "|").'
    hits = hits + count(lower(string(P.text)), w);
end
weight = 1 + matches(string(P.section), split(sections, "|"));
rank = hits .* weight;
[~, order] = sort(rank, "descend");
order = order(rank(order) > 0);
keep = false(height(P), 1);
used = 0;
for k = order.'
    piece = strlength(P.text(k)) + strlength(P.id(k)) + 6;
    if used + piece <= budget
        keep(k) = true;
        used = used + piece;
    end
end
if ~any(keep) && ~isempty(order)
    keep(order(1)) = true;    % one long paragraph: give it, cut to the budget
end
idx = find(keep);
ids = string(P.id(idx));
blocks = strings(numel(idx), 1);
n = 0;
for j = 1:numel(idx)
    body = string(P.text(idx(j)));
    if strlength(body) > budget
        body = extractBefore(body, max(budget - 40, 2));
    end
    % A quote or bracket in the lookahead's class stops MATLAB's split, so capitals only
    parts = strtrim(string(regexp(body, "(?<=[.!?])\s+(?=[A-Z])", "split")));
    parts = parts(strlength(parts) > 0);
    labels = "S" + (n + (1:numel(parts))).';
    n = n + numel(parts);
    sentences = [sentences; table(labels, parts(:), repmat(ids(j), numel(parts), 1), ...
        VariableNames=["id", "text", "paragraph"])]; %#ok<AGROW>
    blocks(j) = "[" + ids(j) + "] " + body;
end
text = strjoin(blocks, string(newline) + newline);
end

function [d, unknown] = withQuotes(d, sentences)
% The model's dimension with each quote replaced by the sentence of the passages it matches best
% (by shared words: twice the shared count over both lengths), cut to 40 words, with its
% paragraph id. A quote that shares too little with every sentence (under 0.6) is listed in
% unknown, for a retry.
unknown = strings(0, 1);
named = fomc.util.asCell(d.evidence);
evidence = {};
sentWords = arrayfun(@(t) unique(wordsOf(t)), sentences.text, UniformOutput=false);
for k = 1:numel(named)
    item = named{k};
    if ~(isstruct(item) && isfield(item, "quote"))
        continue
    end
    q = unique(wordsOf(string(item.quote)));
    best = 0;
    row = 0;
    for r = 1:height(sentences)
        f = 2 * numel(intersect(q, sentWords{r})) / max(numel(q) + numel(sentWords{r}), 1);
        if f > best
            best = f;
            row = r;
        end
    end
    if best < 0.6
        unknown(end+1, 1) = "quote " + k + " does not match any sentence of the passages: copy a sentence from them."; %#ok<AGROW>
        continue
    end
    words = split(sentences.text(row));
    evidence{end+1} = struct("quote", strjoin(words(1:min(40, numel(words))), " "), ...
        "paragraph_ref", sentences.paragraph(row)); %#ok<AGROW>
end
d.evidence = evidence;
end

function w = wordsOf(t)
% Lowercase words of a text, punctuation dropped
w = string(regexp(lower(t), "[a-z0-9]+(?:[-'][a-z0-9]+)*", "match"));
end

function d = placeholder()
% A dimension not scored yet: valid for the checks, so each dimension's own issues can be told apart
d = struct("status", "not_discussed", "score", [], "confidence", [], "rationale", "", "evidence", {{}});
end

function r = rulesOf(skill)
% The skill's "Rules that prevent common mistakes" section
r = extractBetween(skill, "## Rules that prevent common mistakes", "## Output");
if isempty(r)
    r = "";
end
r = strtrim(string(r(1)));
end

function out = dimensionSchema(schemaText)
% The schema of one dimension, cut from the skill's full schema as text (decoding and encoding
% it again would turn the null in its enum into an empty array)
schemaText = char(schemaText);
start = strfind(schemaText, '"dimension":');
open = find(schemaText(start:end) == '{', 1) + start - 1;
depth = 0;
for k = open:numel(schemaText)
    depth = depth + (schemaText(k) == '{') - (schemaText(k) == '}');
    if depth == 0
        break
    end
end
out = string(schemaText(open:k));
end

function dimensions = dimensionsInFailures(issues)
allDimensions = ["rate_path", "inflation", "labor_market", "economic_activity", ...
    "financial_conditions", "balance_sheet", "risk_balance"];
dimensions = strings(0, 1);
for name = allDimensions
    if any(contains(issues, name))
        dimensions(end+1, 1) = name; %#ok<AGROW>
    end
end
if ~isempty(issues) && isempty(dimensions)
    dimensions = allDimensions(:);
end
end
