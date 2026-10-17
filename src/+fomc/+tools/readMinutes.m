function r = readMinutes(ctx, args)
%READMINUTES Paragraphs of one section of one meeting's minutes, a page at a time.
%   Each paragraph has an id. A page holds whole paragraphs up to cfg.maxToolChars;
%   nextParagraph says where to continue.

% Check the arguments
d = fomc.util.parseDate(fomc.tools.getArg(args, "meetingDate", ""));
if isnat(d)
    r = fomc.tools.fail("'meetingDate' is required and must be written YYYY-MM-DD. Call listMeetings for valid dates.");
    return
end
S = fomc.data.sections();
S = S(S.name ~= "body", :);
section = string(fomc.tools.getArg(args, "section", ""));
if ~any(S.name == section)
    r = fomc.tools.fail("'section' must be one of: " + strjoin(S.name, ", ") + ".");
    return
end
first = fomc.tools.getArg(args, "startParagraph", 1);
if ~isnumeric(first) || ~isscalar(first) || first < 1 || first ~= round(first)
    r = fomc.tools.fail("'startParagraph' must be a whole number, 1 or more.");
    return
end

% Find the meeting, only if released by the anchor date; if not, suggest the nearest ones
M = ctx.D.meetings;
R = M(M.ReleaseDate <= ctx.asOf, :);
k = find(M.MeetingDate == d & M.ReleaseDate <= ctx.asOf, 1);
if isempty(k)
    [~, order] = sort(abs(days(R.MeetingDate - d)));
    near = fomc.util.fmtDate(sort(R.MeetingDate(order(1:min(3, numel(order))))));
    r = fomc.tools.fail("No FOMC meeting ended on " + fomc.util.fmtDate(d) + ...
        ". The nearest available meetings ended on: " + strjoin(near, ", ") + ".");
    return
end

% The paragraphs of the requested section
P = ctx.D.paras(ctx.D.paras.meetingIdx == k & ctx.D.paras.section == section, :);
if isempty(P)
    r = fomc.tools.fail("The " + section + " section is empty for the " + fomc.util.fmtDate(d) + ...
        " meeting (older minutes do not split every section). Try another section.");
    return
end
if first > height(P)
    r = fomc.tools.fail("'startParagraph' " + first + " is past the end: this section has " + height(P) + " paragraphs.");
    return
end

% Fill one page with whole paragraphs until the character cap is reached
cap = ctx.cfg.maxToolChars;
rows = {};
used = 0;
last = first - 1;
for i = first:height(P)
    text = P.text(i);
    if used > 0 && used + strlength(text) > cap
        break
    end
    if strlength(text) > cap                      % one very long paragraph: clip it
        text = extractBefore(text, cap + 1) + "...";
    end
    rows{end+1, 1} = struct("id", P.id(i), "text", text); %#ok<AGROW>
    used = used + strlength(text);
    last = i;
end

% Build the result; nextParagraph tells the model where to continue
r = struct("meetingDate", fomc.util.fmtDate(M.MeetingDate(k)), ...
    "releaseDate", fomc.util.fmtDate(M.ReleaseDate(k)), "section", section, ...
    "totalParagraphs", height(P), "firstParagraph", first, "lastParagraph", last);
if last < height(P)
    r.nextParagraph = last + 1;
end
r.paragraphs = rows;
end
