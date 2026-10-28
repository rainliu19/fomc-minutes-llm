function m = minutesDirection(D, k, rangeNow, nvp)
%MINUTESDIRECTION Which way a meeting's minutes point for the rate: the AI's score, else the word rules.
%   m = fomc.data.minutesDirection(D, k, rangeNow)
%   k: a row of D.meetings. rangeNow: the target range then (a row of fomc.data.ratePath levels).
%   When the AI has scored the meeting's minutes (fomc.skills.scoreCache, filled by
%   pipeline/score_minutes.m) and the score passed its checks, the direction is its rate_path
%   score: "up" at or above the cutoff, "down" at or below minus the cutoff, else "hold".
%   Otherwise it is the lean read by the word rules (fomc.data.policyViews). At a range of 0 to
%   1/4 percent, a lean to cuts means support by other means, so the rate itself holds.
%   m: way, source ("ai" or "rules"), score (NaN without one), evidence (the AI's quotes, each
%   with quote and paragraph_ref), and the word rules' lean and way, kept as the baseline.
%   Model=... picks whose scores (default the configured model); UseAI=false gives the rules;
%   Folder=... reads scores from another folder (tests).

arguments
    D (1,1) struct
    k (1,1) double
    rangeNow (1,:) table
    nvp.Model (1,1) string = fomc.config(verbose=false).model
    nvp.UseAI (1,1) logical = true
    nvp.Cutoff (1,1) double = 0.5
    nvp.Folder (1,1) string = ""
end

V = fomc.data.policyViews(D, k);
ruleWay = wayOfLean(V.lean, rangeNow);
m = struct("way", ruleWay, "source", "rules", "score", NaN, "evidence", {{}}, ...
    "ruleLean", V.lean, "ruleWay", ruleWay);
if ~nvp.UseAI
    return
end
saved = fomc.skills.scoreCache("read", nvp.Model, fomc.util.fmtDate(D.meetings.MeetingDate(k)), Folder=nvp.Folder);
if isempty(saved) || ~any(string(saved.dimensionsScored) == "rate_path") || ~saved.ok
    return
end
d = saved.score.dimensions.rate_path;
if string(d.status) ~= "scored" || isempty(d.score)
    return
end
way = "hold";
if d.score >= nvp.Cutoff
    way = "up";
elseif d.score <= -nvp.Cutoff
    way = "down";
    if rangeNow.upper <= 0.25
        way = "hold";
    end
end
m.way = way;
m.source = "ai";
m.score = d.score;
m.evidence = fomc.util.asCell(d.evidence);
end

function w = wayOfLean(lean, rangeNow)
% The direction a word-rule lean points: "up", "down", "hold" or "unclear"
switch lean
    case {"increases", "slower increases"}
        w = "up";
    case {"cuts", "slower cuts"}
        w = "down";
        if rangeNow.upper <= 0.25
            w = "hold";
        end
    case "hold"
        w = "hold";
    otherwise
        w = "unclear";
end
end
