function bad = checkReport(reply, sources)
%CHECKREPORT What a specialist agent's report says that its sources do not.
%   bad = fomc.guard.checkReport(reply, sources)
%   Paragraph ids and numbers in the reply must appear in the sources (what the agent's code
%   found and its tool results), so a small model cannot add a figure or an id. Commas inside
%   numbers are ignored. Returns the offending tokens (a 1-by-n string, empty when none).

src = replace(join(string(sources(:)), " "), ",", "");
reply = replace(string(reply), ",", "");
% contains(src, tokens) is one answer for "any token", so each token is asked on its own
missing = @(tokens) tokens(~arrayfun(@(t) contains(src, t), tokens));
ids = fomc.guard.idsIn(reply);
nums = unique(string(regexp(reply, "\d+(?:\.\d+)?", "match")));
nums = nums(~arrayfun(@(t) contains(join(ids, " "), t), nums));   % digits inside an id were checked with the id
bad = [missing(ids(:)); missing(nums(:))].';
end
