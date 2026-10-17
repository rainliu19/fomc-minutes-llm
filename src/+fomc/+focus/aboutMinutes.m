function tf = aboutMinutes(question)
%ABOUTMINUTES True if a question is about the Committee or its minutes.
%   Such answers must rest on text read from the minutes (see prefetch, the nudge, the warning).

q = lower(string(question));
tf = contains(q, ["committee", "fomc", "minutes", "participants", "meeting", ...
    "decid", "vote", "dissent", "members", "stance"]);
% "What did the Fed say...", "the Fed's view of inflation" ask about the Committee too
tf = tf || ~isempty(regexp(q, "(?<![a-z])(fed|federal reserve|policymakers?|officials)(?:'s|s')?\s+(?:view|views|viewed|outlook|thinking|assessment|said|say|says|saying|discuss\w*|concern\w*|expect\w*|judg\w*)", "once")) ...
    || ~isempty(regexp(q, "(?:view|views|assessment|outlook) of (?:the )?(?:fed|federal reserve|committee)(?![a-z])", "once"));
end
