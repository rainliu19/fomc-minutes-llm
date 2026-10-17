function text = expandIds(text, known)
%EXPANDIDS Repair shortened paragraph ids such as "staffOutlook/2" in an answer.
%   text = fomc.guard.expandIds(text, known)
%   A small model sometimes drops the meeting date from an id. If exactly one id in known
%   (ids tools returned this session) ends with that section and number, the short form is
%   replaced by the full id. Ambiguous or unknown short forms are left as written.

text = string(text);
names = fomc.data.sections().name;
names = names(names ~= "body");
pat = "(?<![\w/\-])(" + strjoin(names, "|") + ")/(\d+)(?![\w/])";
[tok, st, en] = regexp(char(text), pat, "tokens", "start", "end");
chars = char(text);
for k = numel(tok):-1:1
    suffix = "/" + string(tok{k}{1}) + "/" + string(tok{k}{2});
    match = known(endsWith(known, suffix));
    if numel(match) == 1
        chars = [chars(1:st(k)-1) char(match) chars(en(k)+1:end)];
    end
end
text = string(chars);
end
