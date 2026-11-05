function output = scoreByDimension(s, meetingDate, nvp)
%SCOREBYDIMENSION Score one meeting with the fomc-score skill, one dimension per model call.
%   output = fomc.skills.scoreByDimension(s) scores the latest released meeting.
%   output = fomc.skills.scoreByDimension(s, meetingDate) scores a specific YYYY-MM-DD.
%   output = fomc.skills.scoreByDimension(s, meetingDate, Dimensions=["rate_path"]) scores only
%   those dimensions; the others are not_discussed with "Not scored in this run" as rationale.
%   A variant of fomc.skills.scoreMeeting (Aarya's one-call scorer) for the local models'
%   window; chat's scoring requests (fomc.runTurn) and the saved scores both use this one.
%   It uses the skill as written (skills/fomc-score: the scale, the rules in SKILL.md, the
%   rubrics, the dimension schema) and the same checks
%   (fomc.guard.validateScores), and returns the same score object, plus calls and passages.
%   output.score contains the model result; output.ok and output.issues report validation;
%   output.attempts is the most attempts any dimension needed (1 to 3); output.calls counts
%   the model calls; output.passages lists, per dimension, the paragraph ids the model read.
%
%   The skill's instructions, all seven rubrics and the full minutes come to about 17,000
%   tokens, and the local models read 8,192 (num_ctx in models/*/Modelfile); Ollama refuses a
%   longer prompt or, in some versions, cuts it without an error. So each dimension is scored
%   in its own call, with the shared scale, the skill's rules, that dimension's rubric and the
%   paragraphs of the minutes about it: code ranks the paragraphs by the dimension's words,
%   Participants' Views first, and keeps the best that fit. The model quotes the sentences that
%   justify its score; code matches each quote to the closest sentence of the passages (by
%   shared words) and uses that sentence, cut to 40 words, so every quote is word for word from
%   the minutes. Asked to copy
%   quotes exactly, Qwen3 4B reworded them in 4 of 7 dimensions of the September 2026 minutes
%   and repeated the same text on each retry; asked instead to name numbered sentences, it chose
%   poorly (a labor market sentence for inflation) and once wrote "S1999..." without end. The
%   model reads, judges and picks the evidence; code picks what it reads and checks what it
%   returns (fomc.guard.validateScores). A dimension no paragraph mentions is not_discussed
%   without a model call.
%
%   The model does not write a score: it names the stance (dovish, balanced, hawkish) and the row
%   of the rubric's Anchors table that the minutes match, and code takes the score from that row
%   (requestSchema, fromAnchor). Asked for a number, Qwen3 4B tended to give the mildest score
%   of the right sign. What code reads from the minutes narrows the rows: the rate decision for
%   the rate path, new purchases or the end of runoff for the balance sheet.

arguments
    s (1,1) struct
    meetingDate (1,1) string = ""
    nvp.Dimensions (1,:) string = ["rate_path", "inflation", "labor_market", "economic_activity", ...
        "financial_conditions", "balance_sheet", "risk_balance"]
end

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
    if ~any(nvp.Dimensions == dims.key(i))
        score.dimensions.(dims.key(i)).rationale = "Not scored in this run.";
    end
end
dims = dims(ismember(dims.key, nvp.Dimensions), :);
passages = struct();
unscored = strings(0, 1);
maxAttempts = 3;
attemptsUsed = 0;
calls = 0;
for i = 1:height(dims)
    key = dims.key(i);
    rubric = fomc.skills.read("fomc-score", "rubric/" + dims.rubric(i));
    anchors = anchorsOf(rubric);
    if key == "rate_path"
        % A cut can only match a dovish row, an increase a hawkish one
        move = decisionSign(ctx.D, row);
        if move ~= 0
            anchors = anchors(anchors.score * move > 0, :);
        end
    end
    note = "";
    if key == "rate_path"
        note = decisionNote(ctx.D, row);
    elseif key == "balance_sheet"
        % New purchases, or runoff slowed or ended, can only match a dovish row
        note = balanceSheetNote(ctx.D, row);
        if strlength(note) > 0
            anchors = anchors(anchors.score < 0, :);
        end
    end
    dimSchema = requestSchema(anchors.label);
    task = "Score one dimension of the FOMC minutes of the meeting that ended " + meetingDate + ...
        " (released " + releaseDate + "): " + dims.title(i) + ". Use only the passages below, which " + ...
        "code selected from these minutes as the ones about this topic, and no later knowledge. Return " + ...
        "only a JSON object for this one dimension that matches the supplied schema: evidence: 1 to 3 " + ...
        "quotes of sentences from the passages that show what was decided or argued; a rationale of " + ...
        "one or two short sentences (under 60 words) about the minutes; the stance these minutes " + ...
        "support on this topic: dovish (toward easier policy, below 0), balanced (0) or hawkish " + ...
        "(toward tighter policy, above 0); the row of the rubric's Anchors table whose description " + ...
        "matches these minutes, copied with its score and on the side of the stance " + ...
        "(stance_anchor); and stance_confidence. Pick the anchor by what the minutes say was done or urged, not by the mildest " + ...
        "row with the right sign: the score is the anchor's, in brackets. Only if the passages do not discuss this " + ...
        "topic, return no evidence and null stance, stance_anchor and stance_confidence (not_discussed).";
    if strlength(note) > 0
        task = task + " " + note;
    end
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
            [candidate, offRubric] = fromAnchor(jsondecode(content), anchors);
            [candidate, unknown] = withQuotes(candidate, sentences);
            unknown = [offRubric; unknown];
            trial = score;
            trial.dimensions.(key) = candidate;
            failures = [fomc.guard.validateScores(trial, minutesText, meetingDate, ctx.D); ...
                fomc.guard.checkRationaleSign(trial)];
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
            "score", candidateScore(candidate), "reply", extractBefore(content, min(strlength(content), 800) + 1), ...
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
    "calls", calls, "passages", passages, "dimensionsScored", dims.key.');
end

function T = dimensionList()
% Each dimension: its key, rubric file, title, the words that mark a paragraph about it, and
% the sections that state the Committee's view of it (read first). The balance sheet's words are
% phrases: "balance sheet", "purchases" and "mortgage-backed" alone matched the paragraphs of
% 2020-03-15 on households' balance sheets, consumers' purchases and mortgage payments.
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
    "the balance sheet|federal reserve's balance sheet|balance sheet measures|securities holdings|holdings of treasury|holdings of agency|asset purchases|securities purchases|purchases of treasury|purchases of agency|treasury securities|agency mortgage-backed|agency mbs|runoff|redemption|reinvest|reserves|soma"
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

function v = decisionSign(D, row)
% +1 for an increase, -1 for a cut, 0 for a hold or a decision code could not read
v = 0;
switch string(D.cards.action(row))
    case "raise"
        v = 1;
    case "cut"
        v = -1;
end
end

function note = decisionNote(D, row)
% The meeting's decision as read by code (fomc.data.decisionCards), and the rubric's scores for
% that kind of move. The rubric tells the model to look up the decision, which it cannot do
% from the passages alone; told only that a cut "must be below 0", Qwen3 4B scored the 50 basis
% point cut of 2024-09-18 and the cut to near zero of 2008-12-16 at -0.25, "under the rule".
card = D.cards(row, :);
action = string(card.action);
range = string(card.targetRange);
switch action
    case "raise"
        note = "Code read the decision of this meeting from the minutes: the Committee raised the " + ...
            "target range to " + range + ". Under the rubric's anchors an increase scores +0.5 to +1: " + ...
            "+0.5 for a small increase with hedging on what comes next, +0.75 for an increase, +1 when " + ...
            "many argue for more or faster; +0.25 only if the minutes describe it as the final increase.";
    case "cut"
        note = "Code read the decision of this meeting from the minutes: the Committee lowered the " + ...
            "target range to " + range + ". Under the rubric's anchors a cut scores -0.5 to -1: " + ...
            "-0.5 for a small cut with hedging on what comes next, -0.75 for a cut, -1 for a large cut " + ...
            "or emergency language; -0.25 only if the minutes describe it as the final cut.";
    case "hold"
        note = "Code read the decision of this meeting from the minutes: the Committee kept the target " + ...
            "range at " + range + ". Score a hold from the forward-looking language: it may be " + ...
            "positive, negative or zero.";
    otherwise
        note = "";
end
end

function T = anchorsOf(rubric)
% The rows of a rubric's Anchors table: score and label ("New purchases or large expansion
% announced or strongly urged (-1.00)"), the label as the model must copy it. The description
% comes first: with labels that began with the score ("0.00: ..."), Qwen3 4B chose the 0.00 row
% for nearly every dimension of June 2022 and March 2020, its rationale saying "hawkish" or
% "dovish" all the same.
tok = regexp(char(rubric), "(?m)^\|\s*([+-]?\d\.\d\d)\s*\|\s*(.*?)\s*\|\s*$", "tokens");
score = cellfun(@(t) str2double(t{1}), tok(:));
label = cellfun(@(t) string(t{2}) + " (" + string(t{1}) + ")", tok(:));
T = table(score, label);
end

function out = requestSchema(labels)
% The schema the model fills for one dimension: the skill's dimension (schema.json) with the
% score replaced by an anchor, one of the rubric's rows, and no status (a null anchor is
% not_discussed). The model writes the fields in alphabetical order, whatever the schema's order,
% so they are named to be written in the order it should think: what the minutes say (evidence),
% why (rationale), which side (stance), which row (stance_anchor), how sure (stance_confidence).
% Named "anchor", the row came first, before any quote, and Qwen3 4B chose "0.00" for nearly every
% dimension of June 2022. Without the stance it chose rows of the wrong side with the right size:
% +0.75 for the labor market of 2008-12-16, its rationale "weakness that supports easier policy".
% fromAnchor turns the answer back into the skill's dimension object.
anchor = strjoin("""" + replace(labels, """", "\""") + """", ", ");
out = "{""type"": ""object"", ""required"": [""evidence"", ""rationale"", ""stance"", ""stance_anchor"", ""stance_confidence""], " + ...
    """additionalProperties"": false, ""properties"": {" + ...
    """evidence"": {""type"": ""array"", ""maxItems"": 3, ""items"": {""type"": ""object"", ""required"": [""quote""], " + ...
        """additionalProperties"": false, ""properties"": {""quote"": {""type"": ""string""}}}}, " + ...
    """rationale"": {""type"": ""string"", ""maxLength"": 500}, " + ...
    """stance"": {""type"": [""string"", ""null""], ""enum"": [""dovish"", ""balanced"", ""hawkish"", null]}, " + ...
    """stance_anchor"": {""type"": [""string"", ""null""], ""enum"": [" + anchor + ", null]}, " + ...
    """stance_confidence"": {""type"": [""string"", ""null""], ""enum"": [""high"", ""medium"", ""low"", null]}}}";
end

function [d, issues] = fromAnchor(reply, anchors)
% The skill's dimension object from the model's answer: the score is the chosen anchor's, and a
% null anchor is not_discussed (no score, confidence or evidence). An answer with a status and
% score instead of an anchor keeps them (the stand-in models of the tests).
issues = strings(0, 1);
field = @(name, default) pickField(reply, name, default);
score = field("score", []);
status = field("status", "");
anchor = field("stance_anchor", []);
confidence = field("stance_confidence", field("confidence", []));
hasAnchor = (ischar(anchor) || isstring(anchor)) && strlength(string(anchor)) > 0;
if isfield(reply, "stance_anchor") && ~hasAnchor
    d = struct("status", "not_discussed", "score", [], "confidence", [], ...
        "rationale", field("rationale", ""), "evidence", {{}});
    return
end
if hasAnchor
    status = "scored";
    k = find(anchors.label == strtrim(string(anchor)), 1);
    if isempty(k)
        % Copied with small changes: match it by its score
        v = str2double(regexp(string(anchor), "[+-]?\d\.\d+(?=\)\s*$)", "match", "once"));
        k = find(anchors.score == v, 1);
    end
    if isempty(k)
        issues(end+1, 1) = "the anchor """ + string(anchor) + """ is not a row of the rubric's Anchors table: " + ...
            "copy one of them: " + strjoin(anchors.label, "; ") + ".";
    else
        score = anchors.score(k);
        stance = string(field("stance", ""));
        side = (stance == "hawkish") - (stance == "dovish");
        if any(stance == ["dovish", "balanced", "hawkish"]) && sign(score) ~= side
            issues(end+1, 1) = "the stance is " + stance + " but the row """ + anchors.label(k) + ...
                """ is " + sideOf(score) + ": choose the row on the " + sideOf(side) + ...
                " side that matches the minutes, or correct the stance.";
        end
    end
end
d = struct("status", status, "score", score, "confidence", confidence, ...
    "rationale", field("rationale", ""), "evidence", {field("evidence", {})});
end

function t = sideOf(v)
names = ["dovish (below 0)", "balanced (0)", "hawkish (above 0)"];
t = names(sign(v) + 2);
end

function v = candidateScore(d)
% The score of an answer, for the trace: NaN when there is none
v = NaN;
if isstruct(d) && isfield(d, "score") && isnumeric(d.score) && isscalar(d.score)
    v = d.score;
end
end

function v = pickField(s, name, default)
v = default;
if isstruct(s) && isfield(s, name)
    v = s.(name);
end
end

function note = balanceSheetNote(D, row)
% What code reads from the policy actions about the size of the balance sheet, for the balance
% sheet call: new purchases (holdings increased where the previous meeting's were not), or runoff
% slowed or ended. Told the rubric only, Qwen3 4B scored the purchases of at least $700 billion of
% 2020-03-15 at -0.25 and, with the anchor rows written before its quotes, at 0 ("no mention of
% runoff ... balanced"); it scored the end of runoff of 2019-07-31 +1 ("a faster balance sheet
% runoff"). "" when neither: continuing purchases and runoff are scored from the discussion.
note = "";
now = policyActionText(D, row);
if row > 1 && increasesHoldings(now) && ~increasesHoldings(policyActionText(D, row - 1))
    note = "Code read from the Committee's policy actions in these minutes that it directed the " + ...
        "Desk to increase the System's securities holdings (asset purchases), which the minutes of " + ...
        "the previous meeting (" + fomc.util.fmtDate(D.meetings.MeetingDate(row - 1)) + ") did " + ...
        "not: new purchases. Under the rubric's anchors new purchases or a large expansion " + ...
        "announced score -1, whatever their stated purpose; -0.75 or -0.5 only if the minutes " + ...
        "describe them as small or temporary.";
elseif easesRunoff(now)
    note = "Code read from the Committee's policy actions in these minutes that it decided to " + ...
        "slow or end the decline of its securities holdings (runoff), which keeps the balance " + ...
        "sheet larger than planned: dovish. Under the rubric's anchors runoff slowed or ended " + ...
        "scores -0.75, -1 if purchases are also urged, -0.5 if the minutes stress that it is " + ...
        "technical.";
end
end

function t = policyActionText(D, row)
P = D.paras(D.paras.meetingIdx == row & string(D.paras.section) == "policyAction", :);
t = lower(strjoin(string(P.text), newline));
end

function tf = increasesHoldings(t)
% "increase or reduce the pace of its purchases" (2013) is a statement of options, not a purchase
t = erase(t, "increase or reduce");
tf = ~isempty(regexp(t, "(increase|expand)[a-z ,]{0,80}(holdings|purchases)|" + ...
    "additional purchases|(begin|initiate)[a-z ,]{0,30}purchas", "once"));
end

function tf = easesRunoff(t)
% Runoff slowed or ended, in a meeting that does not begin it (May 2022's plan to "slow and
% then stop the decline" is the start of runoff)
tf = ~isempty(regexp(t, "(conclude|end|ending|stop|slow)[a-z ,]{0,40}(reduction|runoff|decline)" + ...
    "[a-z ,]{0,40}(holdings|securities|balance sheet)|(reduce|lower)[a-z ,]{0,40}redemption cap", "once")) && ...
    isempty(regexp(t, "begin[a-z ,]{0,40}(reduc|runoff)", "once"));
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
    quote = strjoin(words(1:min(40, numel(words))), " ");
    % Two quotes that match the same sentence count once
    if any(cellfun(@(e) e.quote == quote, evidence))
        continue
    end
    evidence{end+1} = struct("quote", quote, "paragraph_ref", sentences.paragraph(row)); %#ok<AGROW>
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
