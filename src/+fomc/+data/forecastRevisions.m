function F = forecastRevisions(D, k)
%FORECASTREVISIONS How the Fed staff's forecast changed from the previous meeting, read from the minutes.
%   F = fomc.data.forecastRevisions(D, k)
%   k: rows of D.meetings. F: one row per meeting with meetingDate and, for inflation and
%   for economic activity (growth and spending), the revision ("higher", "lower", "mixed",
%   "about the same", or "" when the minutes make no comparison) with the paragraph it was
%   read from, and the risks the staff saw ("upside", "downside", "balanced" or "") with
%   their paragraph. Read from the Staff Economic Outlook by code, no model.
%
%   A clause counts as a revision only if it compares with the previous forecast ("than the
%   one prepared for the July meeting", "revised up", "relative to January"). The reasons
%   after "reflecting", "because" and the like are dropped, so "revised down ... reflecting
%   higher energy prices" reads as lower. Clauses about potential output, the natural rate or
%   the output gap are estimates of the economy's capacity, not forecasts, and are skipped.
%   The unemployment rate is left out: its direction means the opposite of growth's, and the
%   wording ("a smaller decline") is too varied to read reliably.

arguments
    D (1,1) struct
    k (:,1) double
end

topics = ["inflation", "activity"];
names = ["meetingDate", topics, topics + "Id", topics + "Risk", topics + "RiskId"];
F = array2table(repmat("", numel(k), numel(names)), VariableNames=names);
for i = 1:numel(k)
    F.meetingDate(i) = fomc.util.fmtDate(D.meetings.MeetingDate(k(i)));
    P = D.paras(D.paras.meetingIdx == k(i) & D.paras.section == "staffOutlook", :);
    found = struct("inflation", strings(0, 1), "activity", strings(0, 1));
    ids = struct("inflation", "", "activity", "");
    for j = 1:height(P)
        for s = sentences(P.text(j))
            [found, ids] = readRevision(s, P.id(j), found, ids);
            for t = topics
                if F.(t + "Risk")(i) == ""
                    side = readRisk(s, t);
                    if side ~= ""
                        F.(t + "Risk")(i) = side;
                        F.(t + "RiskId")(i) = P.id(j);
                    end
                end
            end
        end
    end
    for t = topics
        F.(t)(i) = combine(found.(t));
        F.(t + "Id")(i) = ids.(t);
    end
end
end

function [found, ids] = readRevision(s, id, found, ids)
% Add the revisions one sentence states: per clause, its topics and the first direction word
for c = clauses(s)
    if isempty(regexp(c, comparisonPattern(), "once", "ignorecase"))
        continue
    end
    main = regexprep(c, reasonPattern(), "", "ignorecase");
    if ~isempty(regexp(main, "potential|natural rate|output gap", "once"))
        continue
    end
    w = direction(main);
    if w == ""
        continue
    end
    for t = topicsIn(main)
        found.(t)(end+1, 1) = w;
        if ids.(t) == ""
            ids.(t) = id;
        end
    end
end
end

function side = readRisk(s, topic)
% "upside", "downside" or "balanced" when a clause of the sentence gives the risks around this
% topic's forecast; "" otherwise
side = "";
if isempty(regexp(s, "risk", "once", "ignorecase"))
    return
end
for c = regexp(s, ",? and that |; | while |, as ", "split")
    if ~any(topicsIn(c, true) == topic)
        continue
    end
    tok = regexp(c, "(?:skew|tilt|weight)\w*\s+(?:\w+\s+){0,2}to the (upside|downside)", "tokens", "once");
    skew = regexp(c, "(upward|downward) skew", "tokens", "once");
    if ~isempty(tok)
        side = string(tok{1});
        return
    elseif ~isempty(skew)
        side = replace(string(skew{1}), "ward", "side");
        return
    elseif ~isempty(regexp(c, "(?<![a-z])balanced", "once"))
        side = "balanced";
        return
    end
end
end

function p = comparisonPattern()
% Wording that compares a forecast with the previous one. "Prepared for the July meeting" counts
% only after "than the one", "relative to the forecast" and the like: on its own it introduces
% the current forecast ("In the projection prepared by the staff for the November meeting").
months = "january|february|march|april|may|june|july|august|september|october|november|december";
p = "previous(ly)?\s+(staff\s+)?(forecast|projection|outlook|meeting|projected|expected|assumed|anticipated|thought)|" + ...
    "prior\s+(forecast|projection|meeting)|than (in )?the (previous|prior|last)|" + ...
    "(than|as|relative to|compared with|similar to|in line with|from) (in )?(that |the (one|(staff )?(forecast|projection|outlook)) )" + ...
    "(prepared )?(by the staff )?for the|(that|those) at the time of the|" + ...
    "(than|relative to|compared with|similar to|in line with) (in )?(the )?(" + months + ")|revised|revision|marked (up|down)|" + ...
    "(raised|lowered|reduced|reduce|boosted) (its|their)|little changed|not much changed";
end

function p = reasonPattern()
% The reasons given for a revision, from the reason word to the end of the clause
p = ",?\s+((primarily|mostly|largely|partly|in part|chiefly|mainly)\s+)?(reflect\w*|because|in response to|" + ...
    "due to|owing to|driven by|as a result of|given|amid|on account of|stemming from|as incoming)(?![a-z]).*$";
end

function w = direction(c)
% The first direction word in a clause: "higher", "lower" or "about the same"; "" if none
words = [
    "not as strong",                  "lower"
    "not as weak",                    "higher"
    "revised (up|upward)",            "higher"
    "marked up",                      "higher"
    "upward revision",                "higher"
    "(?<![a-z])raised",               "higher"
    "higher|stronger|faster|firmer",  "higher"
    "revised (down|downward)",        "lower"
    "marked down",                    "lower"
    "downward revision",              "lower"
    "lowered|reduced?(?![a-z])",      "lower"
    "(?<![a-z])lower(?![a-z])|weaker|slower|softer", "lower"
    "similar|little changed|unchanged|(little|slightly|only a bit|only a little) revised|unrevised|" + ...
        "in line with|about the same|not much changed|essentially the same|broadly the same", "about the same"];
w = "";
first = Inf;
for i = 1:height(words)
    at = regexp(lower(c), words(i, 1), "once");
    if ~isempty(at) && at < first
        first = at;
        w = words(i, 2);
    end
end
end

function t = topicsIn(c, forRisk)
% "inflation" and/or "activity", the topics a clause is about. The risks to "employment", the
% "labor market" or "the economic outlook" go with activity: the staff state them together.
if nargin < 2
    forRisk = false;
end
c = lower(c);
t = strings(1, 0);
if ~isempty(regexp(c, "inflation|(pce|consumer) price", "once"))
    t(end+1) = "inflation";
end
activity = "real gdp|gdp growth|economic activity|real activity|economic growth|output growth|growth in real|" + ...
    "outlook for (u\.s\. )?econom|(household|consumer|aggregate) spending";
if forRisk
    activity = activity + "|employment|labor market|economic outlook";
end
if ~isempty(regexp(c, activity, "once"))
    t(end+1) = "activity";
end
end

function w = combine(found)
% One word per meeting: the direction stated, "mixed" if both directions were, and "about the
% same" only if nothing moved
w = "";
if any(found == "higher") && any(found == "lower")
    w = "mixed";
elseif any(found == "higher")
    w = "higher";
elseif any(found == "lower")
    w = "lower";
elseif any(found == "about the same")
    w = "about the same";
end
end

function s = sentences(p)
% A paragraph's sentences
s = string(regexp(p, "(?<=\.)\s+(?=[A-Z])", "split"));
end

function c = clauses(s)
% A sentence's clauses: split at ", but", semicolons, dashes, ", while" and ", although"
c = string(regexp(s, ",\s+but\s+|;\s+|\s*—\s*|,\s+while\s+|,\s+(although|though)\s+", "split"));
end
