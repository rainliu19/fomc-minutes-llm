function n = nextMeetingReading(D, asOf)
%NEXTMEETINGREADING What the latest minutes and markets together suggest for the next meeting.
%   n = fomc.data.nextMeetingReading(D, asOf)
%   The minutes give the direction of future moves (fomc.data.minutesDirection: the AI's
%   rate-path score where the minutes have been scored, else the word rules of
%   fomc.data.policyViews); the 6-month bill against the effective fed funds rate gives the
%   timing (fomc.data.billSignal). On the 62 meetings from 2019 on, the AI's direction was right
%   about the next decision 81% of the time, the word rules 76% and the bill 84%: participants
%   often expect further moves and hold first (docs/agent_interface.md). So the reading says what each
%   points to and how they combine, and how often the next meeting raised, held or cut after
%   earlier minutes with the same pattern, counting only meetings held by asOf.
%   n: minutesWay and marketWay ("up", "down", "hold", or "unclear"), reading (a sentence),
%   history (raised, held, cut, n) and text (both sentences). Empty struct when no minutes are
%   public or no bill yield is known. No model.

arguments
    D (1,1) struct
    asOf (1,1) datetime
end

n = struct();
M = D.meetings;
k = find(M.ReleaseDate <= asOf, 1, "last");
if isempty(k)
    return
end
[~, levels] = fomc.data.ratePath(D, asOf);
rangeNow = levels(end, :);
b = fomc.data.billSignal(D, asOf, rangeNow);
if isempty(fieldnames(b))
    return
end
dir = fomc.data.minutesDirection(D, k, rangeNow);
minutesWay = dir.way;
marketWay = string(b.way);

% Earlier pairs with the same pattern: the minutes' way, and the bill on the day they came out
H = history(D);
same = H(H.nextMeetingDate <= asOf & H.minutesWay == minutesWay & H.marketWay == marketWay, :);
hist = struct("raised", sum(same.nextAction == "raise"), "held", sum(same.nextAction == "hold"), ...
    "cut", sum(same.nextAction == "cut"), "n", height(same));

n = struct("minutesWay", minutesWay, "marketWay", marketWay, "reading", readingOf(minutesWay, marketWay), ...
    "history", hist, "minutesSource", dir.source, "ratePathScore", dir.score, "ruleWay", dir.ruleWay);
n.text = "Next meeting: " + n.reading + " " + sourceText(dir) + " " + historyText(hist);
end

function t = readingOf(minutesWay, marketWay)
% The two signals in one sentence: the minutes for direction, the bill for timing
move = struct("up", "an increase", "down", "a cut");
further = struct("up", "further increases", "down", "further cuts");
if minutesWay == "unclear"
    if marketWay == "hold"
        t = "the minutes give no clear direction, and the 6-month bill suggests markets expect no change over the next few meetings.";
    else
        t = "the minutes give no clear direction, and the 6-month bill suggests markets expect " + move.(marketWay) + ...
            " over the next few meetings.";
    end
elseif minutesWay == marketWay && marketWay == "hold"
    t = "the minutes and the 6-month bill both point to no change over the next few meetings.";
elseif minutesWay == marketWay
    t = "the minutes and the 6-month bill both point to " + move.(marketWay) + " over the next few meetings.";
elseif marketWay == "hold"
    t = "participants expected " + further.(minutesWay) + " over coming meetings, but the 6-month bill suggests " + ...
        "markets do not expect one over the next few meetings.";
elseif minutesWay == "hold"
    t = "participants expected to hold for now, but the 6-month bill suggests markets expect " + move.(marketWay) + ...
        " over the next few meetings, perhaps after data released since the minutes.";
else
    t = "the minutes point to " + further.(minutesWay) + " but the 6-month bill suggests markets expect " + ...
        move.(marketWay) + ": the two signals disagree.";
end
end

function t = sourceText(dir)
% Where the minutes' direction came from: the AI's score of their rate path, or the word rules
if dir.source == "ai"
    t = "The minutes' direction is the AI's reading: it scored their rate path " + ...
        string(sprintf("%+.2f", dir.score)) + ", from -1 (dovish) to +1 (hawkish).";
else
    t = "The minutes' direction is read from their wording by fixed rules.";
end
end

function t = historyText(h)
% "After earlier minutes with this pattern, the next meeting held 25 times, raised 4 times (of 29)."
if h.n < 3
    t = "Too few earlier meetings in this data had this pattern to compare.";
    return
end
counts = [h.raised, h.held, h.cut];
verbs = ["raised", "held", "cut"];
[~, order] = sort(counts, "descend");
parts = strings(1, 0);
for i = order
    if counts(i) > 0
        parts(end+1) = verbs(i) + " " + times(counts(i)); %#ok<AGROW>
    end
end
t = "After earlier minutes in this data with this pattern, the next meeting " + strjoin(parts, ", ") + ...
    " (of " + h.n + "). This is history, not a forecast.";
end

function t = times(c)
% 1 -> "once", 3 -> "3 times"
if c == 1
    t = "once";
else
    t = c + " times";
end
end

function H = history(D)
% For every meeting but the last: the way its minutes point, the bill's way on the day they came
% out, and the next meeting's date and decision. Worked out once per data set, since it reads
% every meeting.
persistent cachedKey cachedH
M = D.meetings;
% The AI's saved scores change the minutes' direction, so a new score means a new history
key = height(M) + "|" + fomc.util.fmtDate(M.MeetingDate(end)) + "|" + ...
    numel(fomc.skills.scoreCache("list", fomc.config(verbose=false).model));
if ~isempty(cachedH) && cachedKey == key
    H = cachedH;
    return
end
n = height(M) - 1;
minutesWay = strings(n, 1);
marketWay = strings(n, 1);
for k = 1:n
    rel = M.ReleaseDate(k);
    [~, levels] = fomc.data.ratePath(D, rel);
    b = fomc.data.billSignal(D, rel, levels(end, :));
    minutesWay(k) = fomc.data.minutesDirection(D, k, levels(end, :)).way;
    marketWay(k) = "none";
    if ~isempty(fieldnames(b))
        marketWay(k) = b.way;
    end
end
H = table(minutesWay, marketWay, M.MeetingDate(2:end), D.cards.action(2:end), ...
    VariableNames=["minutesWay", "marketWay", "nextMeetingDate", "nextAction"]);
cachedKey = key;
cachedH = H;
end
