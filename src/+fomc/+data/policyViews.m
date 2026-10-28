function V = policyViews(D, k)
%POLICYVIEWS What participants said about the rate at future meetings, read from the minutes.
%   V = fomc.data.policyViews(D, k)
%   k: one row of D.meetings. V: meetingDate, lean ("increases", "cuts", "hold", "slower
%   increases", "slower cuts", "divided", "depends on the data", or "" when the minutes say
%   nothing the code can read), leanShare (who held the view that gave the lean), and views: one struct per sentence
%   about future rate moves, most widely held first, with who held it ("most participants"),
%   what it leans to, whether it was conditional ("if inflation ..."), the sentence and its
%   paragraph id. Read from Participants' Views and the Committee Policy Action by code, no model.
%
%   A sentence counts only if it names the rate (target range, federal funds rate, policy
%   rate, firming, accommodation), a move in it, and something ahead (future or upcoming
%   meetings, "further", "another", "soon", "for some time", "patient"). Sentences about the
%   decision at this meeting, the balance sheet or the economic projections are skipped. A
%   move that is doubted ("uncertain whether ... would soon warrant an increase", "premature")
%   reads as a hold. Slowing the pace of increases or cuts reads as the same direction, more
%   slowly ("slower cuts"). The lean is the most widely held view that is not conditional;
%   an opposite view held by many or more and nearly as widely makes it "divided", and views that are all
%   conditional make it "depends on the data". Named individuals (often dissenters) are skipped.

arguments
    D (1,1) struct
    k (1,1) double
end

V = struct("meetingDate", fomc.util.fmtDate(D.meetings.MeetingDate(k)), "lean", "", "leanShare", "", "views", {{}});
P = D.paras(D.paras.meetingIdx == k & any(D.paras.section == ["participantsViews", "policyAction"], 2), :);
views = {};
for j = 1:height(P)
    % A dissent paragraph gives one member's view, not the Committee's; a quoted one is the
    % statement or directive
    if ~isempty(regexp(lower(P.text(j)), "dissent|voted against|voting against|^\s*[""“]", "once"))
        continue
    end
    s = sentences(P.text(j));
    % A paragraph that opens on the outlook for policy is read more loosely and ranked first
    onOutlook = ~isempty(regexp(lower(s(1)), outlookPattern(), "once"));
    for x = s
        v = readView(x, onOutlook);
        if ~isempty(v)
            v.id = P.id(j);
            views{end+1, 1} = v; %#ok<AGROW>
        end
    end
end
if isempty(views)
    return
end
% Most widely held first; on a tie, a view on the outlook, then one that names a time
rank = cellfun(@(v) v.weight + v.onOutlook + 0.25 * v.timed, views);
[~, order] = sort(rank, "descend");
views = views(order);
V.views = views;
[V.lean, V.leanShare] = leanOf(views);
end

function v = readView(s, onOutlook)
% The view a sentence states about future rate moves; empty if it states none
v = [];
c = lower(s);
if isempty(regexp(c, ratePattern(), "once"))
    return
end
% Something ahead; on the outlook for policy, a judgment of what would be appropriate is enough
if isempty(regexp(c, aheadPattern(), "once")) && ~(onOutlook && ~isempty(regexp(c, judgmentPattern(), "once")))
    return
end
% Not the decision at this meeting, one member's view, the statement's wording, the directive, the
% balance sheet or the projections
if ~isempty(regexp(c, "(at|for) (this|the current) meeting|this meeting", "once")) && ...
        isempty(regexp(c, "beyond (this|the current) meeting|(future|upcoming|coming|subsequent) meetings?", "once"))
    return
end
if ~isempty(regexp(c, "dissent|decided to|voted to|agreed to (maintain|raise|lower|keep|reduce|leave)|^[""“]|" + ...
        "seeks conditions in reserve markets|projections|summary of economic|within (its|the) target range|" + ...
        "(that|one) member|(?<![a-z])(he|she)(?![a-z])|statement|phrasing|wording|in determining the extent of|" + ...
        "[""”]\s*$|at its previous meeting", "once")) || ...
        ~isempty(regexp(s, "(Governor|President) [A-Z]", "once"))
    return
end
if ~isempty(regexp(c, "asset purchases|balance sheet|securities holdings|holdings of|purchases of|reinvest|runoff", "once")) && ...
        isempty(regexp(c, "target range|federal funds rate|policy rate", "once"))
    return
end
w = moveIn(c);
if w == "" || (w == "hold" && ~isempty(regexp(c, "at the (" + months() + ") meeting", "once")))
    return
end
[share, weight] = shareOf(c);
% "If the economy evolves as expected" is their baseline, not a condition
conditional = ~isempty(regexp(regexprep(c, baselinePattern(), ""), conditionPattern(), "once"));
timed = ~isempty(regexp(c, "next meeting|(coming|upcoming|next couple of) meetings|year[- ]end|end of (this|the) year|" + ...
    "this year|later this year|in (" + months() + ")", "once"));
v = struct("share", share, "lean", w, "conditional", conditional, "text", trimSentence(s), ...
    "weight", weight, "onOutlook", onOutlook, "timed", timed);
end

function w = moveIn(c)
% "increases", "cuts", "hold", "slower increases" or "slower cuts"; "" if the sentence names
% no move. The first move named counts; one that is doubted reads as a hold.
increase = "(increas|rais|hik)\w*( in)? (in |of )?(the )?(target range|federal funds rate|policy rate|rates?)|" + ...
    "rate (increases|hikes)|policy (firming|tightening)|(firming|tightening) (of |in )?(the stance of )?(monetary )?policy|" + ...
    "(ongoing|further|additional|some|gradual|more) (policy )?firming|tightening moves|tighten\w* (monetary )?policy|" + ...
    "remov\w* (of )?(some )?(monetary )?(policy )?accommodation|less accommodative|more restrictive|higher (path|level|policy rate|target range)|" + ...
    "above the current (target )?range";
cut = "(reduc|cut|lower|decreas)\w*( in)? (in |of )?(the )?(target range|federal funds rate|policy rate|rates?)|" + ...
    "rate (cuts|reductions)|policy easing|eas(e|ing) (monetary )?policy|easing (of |in )?(the stance of )?(monetary )?policy|" + ...
    "additional (monetary )?(policy )?accommodation|more accommodative|less restrictive|lower (path|level|policy rate|target range)|" + ...
    "below the current (target )?range|more neutral (stance|setting)|reduc\w* (policy )?restraint";
hold = "(maintain|keep|hold|leav|remain)\w* .{0,40}(target range|federal funds rate|policy rate)|on hold|" + ...
    "pause|patient|exceptionally low levels|within the current (target )?range|unchanged|wait for (more|greater) clarity|" + ...
    "(policy|stance) could be maintained|at or near (its|the) peak|maintain\w* (a |the )?(current )?restrictive";
slower = "(slow|moderat|reduc)\w* (in )?the pace of (policy )?|(slower|smaller|more gradual) (pace of )?";
found = ["increases", "cuts", "hold"];
at = [firstAt(c, increase), firstAt(c, cut), firstAt(c, hold)];
[first, i] = min(at);
w = "";
if isinf(first)
    return
end
w = found(i);
if w ~= "hold" && ~isempty(regexp(c, "(" + slower + ")(\w+ ){0,3}(" + increase + "|" + cut + ")", "once"))
    w = "slower " + w;
elseif w ~= "hold" && ~isempty(regexp(withoutConditions(c), doubtPattern(), "once"))
    w = "hold";
end
end

function c = withoutConditions(c)
% A sentence without its "if" and "unless" clauses, so "if inflation did not decline" is not a doubt
c = regexprep(c, "(?<![a-z])(if|unless)(?![a-z])[^,]*,", "");
c = regexprep(c, "(?<![a-z])(if|unless)(?![a-z]).*$", "");
end

function at = firstAt(c, pattern)
% Where a pattern first matches, Inf if it does not
at = regexp(c, pattern, "once");
if isempty(at)
    at = Inf;
end
end

function [share, weight] = shareOf(c)
% Who held the view, from the first quantifier in the sentence, and how widely: all = 5,
% most or participants as a whole = 4, many = 3, several or some = 2, a few = 1, one = 0.5
shares = [
    "all participants|all members|participants agreed|members agreed",     "all",              5
    "almost all|nearly all|(the )?vast majority",                          "almost all",       4.5
    "most(?! likely)|(a )?majority|(participants|members) generally|generally (agreed|anticipated|expected|judged|noted|saw)", "most", 4
    "many",                                                                "many",             3
    "(a )?number of|several|some(?! time| point| further| additional)|various",                                "several",          2
    "(a )?few|(a )?couple",                                                "a few",            1
    "(?<![a-z])one (participant|member)|(?<![a-z])one noted",              "one",              0.5];
share = "participants";
weight = 4;
first = Inf;
for i = 1:height(shares)
    at = regexp(c, "(?<![a-z])(" + shares(i, 1) + ")(?![a-z])", "once");
    if ~isempty(at) && at < first
        first = at;
        share = shares(i, 2);
        weight = double(shares(i, 3));
    end
end
% "most of these participants" is most of a group already named: at most "several"
if ~isempty(regexp(c, "of (these|those|them)(?![a-z])|these participants|(?<![a-z])others", "once"))
    share = share + " of those";
    weight = min(weight, 2);
end
end

function [lean, share] = leanOf(views)
% The most widely held view that is not conditional; "divided" when the opposite direction is
% held by many or more and by nearly as many (within one step); "depends on the data" when
% every view is conditional
share = "";
plain = views(~cellfun(@(v) v.conditional, views));
if isempty(plain)
    lean = "depends on the data";
    return
end
share = plain{1}.share;
dirs = cellfun(@(v) erase(v.lean, "slower "), plain);
weights = cellfun(@(v) v.weight, plain);
lean = plain{1}.lean;
opposite = struct("increases", "cuts", "cuts", "increases");
if isfield(opposite, dirs(1)) && any(dirs == opposite.(dirs(1)) & weights >= max(3, weights(1) - 1))
    lean = "divided";
end
end

function p = ratePattern()
% The sentence is about the policy rate
p = "target range|federal funds rate|policy rate|firming|tightening|eas(e|ing) (monetary )?policy|policy easing|" + ...
    "accommodation|accommodative|restrictive|more neutral|policy restraint|rate (increases|hikes|cuts|reductions)";
end

function p = aheadPattern()
% The sentence is about something ahead
p = "future|coming|upcoming|subsequent|beyond (this|the current) meeting|period ahead|going forward|ahead|" + ...
    "further|additional|another|ongoing|soon|later|at some point|eventually|(?<![a-z])next|by (the )?(end of the |year[- ]end)|" + ...
    "remainder of|rest of the year|end of (this|the) year|for some time|for a time|extended period|over time|patient|pause|(slow|moderat)\w* the pace|" + ...
    "time being|for now|near term|before long|until|(?<![a-z])wait|(at or near|near) (its|the) peak";
end

function p = judgmentPattern()
% A judgment of what policy would be appropriate
p = "(would|could|might|may|will|should) (\w+ ){0,2}(be )?(appropriate|warranted|necessary|needed|prudent|required)|" + ...
    "anticipat|prepared to|favou?r|call for";
end

function p = outlookPattern()
% The opening of a paragraph on the outlook for policy
p = "outlook for (monetary )?policy|policy outlook|(upcoming|future|coming) meetings|beyond (this|the current) meeting|" + ...
    "future (path of )?(monetary )?policy|appropriate path";
end

function p = baselinePattern()
% "If incoming information broadly confirmed their outlook", "if the economy evolves about as expected"
p = "(?<![a-z])if (the )?(incoming (information|data)|the economy|economic conditions|the data|data)" + ...
    "( \w+){0,4} (confirm\w*|evolv\w*|come in|came in|continued to come in|develop\w*)( \w+){0,4}? " + ...
    "(as (they )?expected|as anticipated|(their|the) (current )?(economic )?outlook|in line with (their )?expectations|" + ...
    "about as (they )?expected)";
end

function m = months()
% Month names, for "at the July meeting"
m = "january|february|march|april|may|june|july|august|september|october|november|december";
end

function p = conditionPattern()
% The view holds only if something happens
p = "(?<![a-z])(if|unless|should (inflation|the|economic|incoming|labor|growth|data))(?![a-z])|were to|in the event|" + ...
    "in the absence of|contingent|(in|under) (such|these|those|a|some|this) scenarios?|scenarios in which";
end

function p = doubtPattern()
% The move is doubted or put off
p = "(?<![a-z])no (participants?|members?)|before it would be appropriate|before assessing|prudent to wait|uncertain whether|not (yet )?(be )?(appropriate|warranted)|premature|no need|would not|did not|" + ...
    "not (soon )?warrant|less likely|too early|avoid|(could|might|would) (add to|raise|increase|heighten) the risk|misinterpreted";
end

function t = trimSentence(s)
% A sentence cut to at most 320 characters at a word boundary
t = strtrim(s);
if strlength(t) > 320
    t = regexprep(extractBefore(t, 318), "\s+\S*$", "") + " …";
end
end

function s = sentences(p)
% A paragraph's sentences
s = string(regexp(p, "(?<=\.)\s+(?=[A-Z])", "split"));
end
