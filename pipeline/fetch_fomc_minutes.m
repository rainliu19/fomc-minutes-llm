%% fetch_fomc_minutes.m
% Downloads FOMC minutes (HTML text + PDF) for every meeting from startYear onward. Recent years
% come from the Fed's FOMC calendar page, earlier years from the yearly historical pages
% (fomchistorical<year>.htm). Uses the Text Analytics Toolbox if installed, else a built-in
% HTML-to-text helper. Run from the repository root. Outputs (in data/minutes/ unless noted):
%   fomc_minutes.mat         fomcMinutes table (also left in the workspace)
%   fomc_minutes.csv         same table without Text, for Python and other tools
%   txt/fomcminutes<MeetingDate>.txt   full cleaned minutes, one per meeting
%   pdf/fomcminutes<MeetingDate>.pdf   official PDFs (archive only; not in git)
%   data/fomc_meeting_dates.csv        Date (= MeetingDate) and ReleaseDate, read by
%                                      macroeconomic_data.m section 5
%
% fomcMinutes columns:
%   MeetingDate        last day of the meeting (files are named by it)
%   ReleaseDate        day the minutes were published, about 3 weeks later. Align text with
%                      market data on this date, not MeetingDate, to avoid look-ahead bias.
%   URL
%   Text               full cleaned minutes (also in the .txt files)
%   Body               the substantive sections below, for text analysis
%   FinancialMarkets   Developments in Financial Markets and Open Market Operations
%   StaffEconomy       Staff Review of the Economic Situation
%   StaffFinancial     Staff Review of the Financial Situation
%   StaffOutlook       Staff Economic Outlook
%   ParticipantsViews  Participants' Views on Current Conditions and the Economic Outlook
%   PolicyAction       Committee Policy Action(s)
%   SpecialTopics      one-off discussions (balance sheet, framework review, repo, ...)
%   Administrative     organizational matters, officer selection, notation votes
%   Attendance         header, attendance list and signature
%   Footnotes          footnote text
%
% Older minutes: 2008 minutes have no section headings and are split on each section's standard
% opening sentence ("The information reviewed at ..."). Early-2009 minutes combine some sections
% under one heading (e.g. "Staff Review of the Economic and Financial Situation"); the combined
% text goes in the first of those columns and the other is left empty.

% Paths are relative to the repository root: step up if the current folder is pipeline/.
if endsWith(pwd, "pipeline"), cd(".."); end

% Settings: first year, web addresses, and the folders the files are saved in
startYear = 2008;
baseURL = "https://www.federalreserve.gov";
calURL  = baseURL + "/monetarypolicy/fomccalendars.htm";
outDir  = fullfile("data", "minutes");
txtDir  = fullfile(outDir, "txt");
pdfDir  = fullfile(outDir, "pdf");
for d = [outDir txtDir pdfDir]
    if ~isfolder(d), mkdir(d); end
end

% Web settings: normal text pages
opts = weboptions("Timeout", 60, "UserAgent", "Mozilla/5.0", ...
                  "ContentType", "text");
% Some 2008-2011 pages are Windows-1252 encoded but declare another charset. Reading as
% ISO-8859-1 maps each byte to one character, so the original bytes can be recovered.
rawOpts = weboptions("Timeout", 60, "UserAgent", "Mozilla/5.0", ...
                     "ContentType", "text", "CharacterEncoding", "ISO-8859-1");

%% 1. Collect every minutes link and release date
% Recent years are on the calendar page; earlier years each have a historical page
links = parseMinutesLinks(webread(calURL, opts));
for y = startYear:year(datetime("today")) - 1
    try
        histHTML = webread(baseURL + "/monetarypolicy/fomchistorical" + y + ".htm", opts);
        links = [links; parseMinutesLinks(histHTML)]; %#ok<AGROW>
    catch
        % Years still on the calendar page have no historical page yet
    end
    pause(1);
end
% Keep one row per meeting, from the start year on
links = links(links.MeetingDate >= datetime(startYear,1,1), :);
[~, keep] = unique(links.MeetingDate);
links = links(keep, :);

fprintf("Found %d sets of minutes from %d onward.\n", height(links), startYear);

%% 2. Download each set of minutes, extract the text, split into sections
% The sections each set of minutes is split into
sectionNames = ["FinancialMarkets" "StaffEconomy" "StaffFinancial" ...
    "StaffOutlook" "ParticipantsViews" "PolicyAction" "SpecialTopics" ...
    "Administrative" "Attendance" "Footnotes"];
bodySections = sectionNames(1:7);

% Prepare empty columns, one row per meeting
n = height(links);
MeetingDate = links.MeetingDate;
ReleaseDate = links.ReleaseDate;
MeetingDate.Format = "yyyy-MM-dd";      % ISO dates, also used by writetable
ReleaseDate.Format = "yyyy-MM-dd";
URL  = baseURL + links.HTMLPath;
Text = strings(n,1);
Sections = strings(n, numel(sectionNames));

% For each meeting: download the page, turn it into text, split into sections, save the .txt
for i = 1:n
    dateStr = string(MeetingDate(i), "yyyyMMdd");
    if isnat(ReleaseDate(i)), warning("No release date found for %s", dateStr); end

    try
        % Download and decode the page, then extract the article text (with the toolbox if installed)
        pageHTML = prepareHTML(decodePage(uint8(char(webread(URL(i), rawOpts)))));
        if exist("htmlTree", "file")                   % Text Analytics Toolbox
            tree = htmlTree(pageHTML);
            article = findElement(tree, "div#article");            % current layout
            if isempty(article), article = findElement(tree, "div#leftText"); end  % pre-2012 layout
            if isempty(article), article = tree; end
            Text(i) = strjoin(extractHTMLText(article), newline);
        else                                           % no toolbox needed
            Text(i) = htmlToText(pageHTML);
        end
        Text(i) = cleanMinutes(Text(i));

        % Split the text into sections
        s = splitSections(Text(i));
        for k = 1:numel(sectionNames)
            Sections(i,k) = s.(sectionNames(k));
        end

        % The .txt keeps the full minutes, minus the heading markers
        Text(i) = regexprep(Text(i), '(?m)^##SECTION## ', '');
        writelines(Text(i), fullfile(txtDir, "fomcminutes" + dateStr + ".txt"));
        fprintf("[%d/%d] %s  (%d chars)\n", i, n, dateStr, strlength(Text(i)));
    catch err
        warning("Failed on %s: %s", URL(i), err.message);
    end

    pause(1);   % be polite to the server
end

% Assemble the table, add the Body column (the substantive sections), and save it as .mat and .csv
fomcMinutes = [table(MeetingDate, ReleaseDate, URL, Text), ...
               array2table(Sections, "VariableNames", sectionNames)];
fomcMinutes.Body = join(fomcMinutes{:, bodySections}, string([newline newline]), 2);
fomcMinutes.Body = strtrim(regexprep(fomcMinutes.Body, '\n{3,}', [newline newline]));
fomcMinutes = movevars(fomcMinutes, "Body", "After", "Text");
fomcMinutes = sortrows(fomcMinutes, "MeetingDate");
save(fullfile(outDir, "fomc_minutes.mat"), "fomcMinutes");
% CSV copy for non-MATLAB users, without Text (identical to the .txt files; match by MeetingDate).
writetable(removevars(fomcMinutes, "Text"), fullfile(outDir, "fomc_minutes.csv"), ...
    "QuoteStrings", "all", "Encoding", "UTF-8");
% Meeting dates for the meeting-aligned macro dataset (macroeconomic_data.m)
% Also save the meeting and release dates, which the macro script reads
meetingDates = renamevars(fomcMinutes(:, ["MeetingDate" "ReleaseDate"]), "MeetingDate", "Date");
writetable(meetingDates, fullfile("data", "fomc_meeting_dates.csv"));

%% 3. (Optional) Download the PDF versions too (archive only; not used for text)
% Download the PDFs too (archive only), skipping ones already saved
pdfOpts = weboptions("Timeout", 60, "UserAgent", "Mozilla/5.0");
for i = 1:n
    [~, name, ext] = fileparts(links.PDFPath(i));
    pdfFile = fullfile(pdfDir, name + ext);
    if isfile(pdfFile), continue; end
    try
        websave(pdfFile, baseURL + links.PDFPath(i), pdfOpts);
    catch err
        warning("PDF failed: %s (%s)", links.PDFPath(i), err.message);
    end
    pause(1);
end

disp("Done. Results in the fomcMinutes table and the '" + outDir + "' folder.");

%% ---- Local helper: minutes links + release dates from a calendar page ----
function links = parseMinutesLinks(html)
    % Two page layouts, so two patterns: the calendar page and the historical pages
    html = char(html);
    month = '([A-Za-z]+\.? \d{1,2}, \d{4})';
    % Calendar page:   PDF | HTML <br> (Released February 19, 2025)
    t1 = regexp(html, ['<a href="(/monetarypolicy/files/fomcminutes\d{8}\.pdf)">PDF</a>\s*\|\s*' ...
        '<a href="(/monetarypolicy/[^"]+\.htm)">HTML</a>\s*(?:<br\s*/?>)?\s*\(Released ' month '\)'], 'tokens');
    t1 = cellfun(@(t) t([1 2 3]), t1, 'UniformOutput', false);
    % Historical pages: Minutes (Released Feb 20, 2008): <br> HTML | PDF
    % (the HTML link is not always named fomcminutes<date>.htm, e.g. June 2008)
    t2 = regexp(html, ['Released ' month '\)\s*:?\s*(?:<br\s*/?>)?\s*' ...
        '<a href="(/monetarypolicy/[^"]+\.htm)">HTML</a>\s*\|\s*' ...
        '<a href="(/monetarypolicy/files/fomcminutes\d{8}\.pdf)"'], 'tokens');
    t2 = cellfun(@(t) t([3 2 1]), t2, 'UniformOutput', false);
    % Combine both, then read the meeting date from the PDF file name and the release date from the text
    t = string(vertcat(t1{:}, t2{:}));     % [pdfPath, htmlPath, releaseText]
    if isempty(t), t = strings(0,3); end

    PDFPath  = t(:,1);
    HTMLPath = t(:,2);
    MeetingDate = datetime(regexp(PDFPath, '\d{8}', 'match', 'once'), "InputFormat", "yyyyMMdd");
    ReleaseDate = NaT(size(PDFPath));
    for k = 1:numel(PDFPath)
        ReleaseDate(k) = parseReleaseDate(t(k,3));
    end
    links = table(MeetingDate, ReleaseDate, HTMLPath, PDFPath);
end

function d = parseReleaseDate(txt)
    % Dates come as "February 19, 2025" or "Feb 20, 2008"
    txt = erase(txt, ".");
    try
        d = datetime(txt, "InputFormat", "MMMM d, yyyy", "Locale", "en_US");   % February 19, 2025
    catch
        d = datetime(txt, "InputFormat", "MMM d, yyyy", "Locale", "en_US");    % Feb 20, 2008
    end
end

%% ---- Local helper: bytes -> text, UTF-8 or (older pages) Windows-1252 ----
function html = decodePage(bytes)
    % Try UTF-8; older pages are Windows-1252
    html = native2unicode(bytes(:)', "UTF-8");
    if contains(html, char(65533))         % invalid UTF-8 -> replacement chars
        html = native2unicode(bytes(:)', "windows-1252");
    end
    html = string(html);
end

%% ---- Local helper: fix up the raw HTML before text extraction ----
function html = prepareHTML(html)
    html = string(html);
    % Drop footnote reference numbers (<sup>1</sup>), which otherwise end up
    % glued to the preceding word ("9:00 a.m.1", "Petrasek,7")
    html = regexprep(html, '<sup>\s*(<a[^>]*>)?\s*\d{1,2}\s*(</a>)?\s*</sup>', '', 'ignorecase');
    % Move a line break that sits inside a bold heading to just after it
    html = regexprep(html, '<br\s*/?>\s*</(strong|b)>', '</$1><br/>', 'ignorecase');
    % Mark section headings: a bold run that fills its own line, e.g.
    % <p><strong>Staff Economic Outlook</strong></p> or <P><B>...</B><BR>.
    % Bold dates ("January 28-29, "), the secretary's signature and long
    % bold runs are left alone. Empty footnote anchors may sit between the
    % closing tag and <br>.
    % Find bold text that fills its own line: those are section headings
    pat = ['<(strong|b)>((?:(?!</?(?:strong|b)>).){1,200}?)</\1>' ...
           '(?=(?:\s*<a[^>]*>\s*</a>)*\s*(?:<br\s*/?>|</p>))'];
    [tok, mat, parts] = regexp(char(html), pat, 'tokens', 'match', 'split', 'ignorecase');
    for k = 1:numel(tok)
        heading = strtrim(regexprep(tok{k}{2}, '<[^>]+>', ''));
        isHeading = strlength(heading) > 0 && strlength(heading) <= 120 ...
            && ~endsWith(heading, ":") && ~contains(heading, "___") ...
            && isempty(regexp(heading, '^(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d', 'once'));
        if isHeading
            tok{k} = "<br/>##SECTION## " + heading;
        else
            tok{k} = string(mat{k});
        end
    end
    % Put the marked-up headings back between the pieces of text
    pieces = [string(parts); string(tok) ""];   % interleave text and headings
    html = join(pieces(:)', "");
end

%% ---- Local helper: plain-MATLAB HTML -> text (no toolbox required) ----
function txt = htmlToText(html)
    html = string(html);
    % Keep only the main article block if present
    % Keep only the main article block
    idx = regexp(html, '<div[^>]*id="(article|leftText)"', 'once');
    if ~isempty(idx), html = extractAfter(html, idx - 1); end
    % Drop scripts, styles, comments
    html = regexprep(html, '<script.*?</script>', ' ', 'ignorecase');
    html = regexprep(html, '<style.*?</style>', ' ', 'ignorecase');
    html = regexprep(html, '<!--.*?-->', ' ');
    % Paragraph/line breaks become newlines, other tags removed
    html = regexprep(html, '<(br|/?p|/div|/h\d|/li|/tr)[^>]*>', newline, 'ignorecase');
    html = regexprep(html, '<[^>]+>', ' ');
    % Common HTML entities
    % Convert HTML codes such as &amp; to the characters they stand for
    ents = ["&nbsp;"," "; "&amp;","&"; "&quot;",""""; "&#39;","'"; ...
            "&rsquo;","'"; "&lsquo;","'"; "&ldquo;",""""; "&rdquo;",""""; ...
            "&mdash;","—"; "&ndash;","–"; "&lt;","<"; "&gt;",">"; ...
            "&shy;",""; "&ntilde;","ñ"];
    for k = 1:size(ents,1), html = replace(html, ents(k,1), ents(k,2)); end
    html = regexprep(html, '&#(\d+);', '${char(str2double($1))}');
    % Tidy whitespace
    html = regexprep(html, '[ \t]+', ' ');
    html = regexprep(html, ' *\n *', newline);
    txt  = strtrim(regexprep(html, '\n{3,}', [newline newline]));
end

%% ---- Local helper: remove site footer and extra blank lines ----
function txt = cleanMinutes(txt)
    txt = string(txt);
    % Cut everything from the page's "Back to Top" (current layout) or
    % "Return to top" (pre-2012 layout) link onward
    % Cut the page footer and tidy blank lines
    k = [strfind(txt, "Back to Top"), strfind(txt, "Return to top")];
    if ~isempty(k), txt = extractBefore(txt, max(k)); end
    txt = replace(txt, "Return to text", "");
    % Heading markers start their own line
    txt = regexprep(txt, '\s*##SECTION## ', [newline '##SECTION## ']);
    % Collapse runs of blank lines and trailing spaces
    txt = regexprep(txt, '[ \t\xA0]+\n', newline);
    txt = strtrim(regexprep(txt, '\n{3,}', [newline newline]));
end

%% ---- Local helper: split marked-up minutes into named sections ----
function s = splitSections(txt)
    names = ["FinancialMarkets" "StaffEconomy" "StaffFinancial" "StaffOutlook" ...
        "ParticipantsViews" "PolicyAction" "SpecialTopics" "Administrative" ...
        "Attendance" "Footnotes"];
    % Start every section empty
    for k = 1:numel(names), s.(names(k)) = strings(0,1); end

    % Older minutes lack some headings, so work out which style this is
    lines = splitlines(txt)';
    % 2008 minutes have no section headings: fall back to opening sentences
    headings = extractAfter(lines(startsWith(lines, "##SECTION## ")), "##SECTION## ");
    keys = string(arrayfun(@sectionKey, headings, "UniformOutput", false));
    useOpeners = ~any(ismember(keys, ...
        ["FinancialMarkets" "StaffEconomy" "ParticipantsViews"]));
    % Early 2009 minutes have no "Committee Policy Action" heading: the
    % policy discussion follows the participants' views under one heading
    hasPolicyHeading = any(keys == "PolicyAction");

    % Walk down the lines: a heading switches the current section; every other line is added to it
    current = "Attendance";        % text before the first heading is the header
    pastSignature = false;
    for line = lines
        if startsWith(line, "##SECTION## ")
            heading = extractAfter(line, "##SECTION## ");
            % The secretary's name and title close the minutes
            if endsWith(strtrim(heading), "Secretary")
                pastSignature = true;
                current = "Attendance";
            end
            % After the closing Attendance list or the signature, bold lines
            % are just names ("Joshua Gallin", "Secretary")
            closing = pastSignature || (current == "Attendance" && ~isempty(s.FinancialMarkets));
            if ~closing
                current = sectionKey(heading);
            end
            continue
        end
        % Signature line "_______" closes the minutes; footnotes follow it
        if startsWith(line, "___")
            pastSignature = true;
            current = "Attendance";
        end
        if pastSignature && ~isempty(regexp(line, '^1\. ', 'once'))
            current = "Footnotes";
        end
        if ~pastSignature && (useOpeners || (current == "ParticipantsViews" && ~hasPolicyHeading))
            opened = openerKey(line, useOpeners);
            if opened ~= "", current = opened; end
        end
        s.(current)(end+1) = line;
    end
    % Join each section's lines back into text
    for k = 1:numel(names)
        s.(names(k)) = strtrim(strjoin(s.(names(k)), newline));
        s.(names(k)) = regexprep(s.(names(k)), '\n{3,}', [newline newline]);
    end
end

%% ---- Local helper: map a heading to its section column ----
function key = sectionKey(heading)
    % Patterns that map a heading to a section; anything unmatched is a special topic
    rules = [
        "^(Developments in Financial Markets|Financial Developments|Discussion of Financial Markets|Market Developments and Open Market|System Liquidity Programs)", "FinancialMarkets"
        "^Staff Review of (the )?Economic",         "StaffEconomy"
        "^Staff Review of (the )?Financial",        "StaffFinancial"
        "^Staff Economic Outlook",                  "StaffOutlook"
        "^(Meeting )?Participants.{1,2}Views?\>",   "ParticipantsViews"
        "^Committee Policy Action",                 "PolicyAction"
        "^((Annual )?Organizational Matters|Selection of Committee Officer|Election of Committee|Committee Ethics|Action to Adopt Changes to the Committee|(Proposed Changes to )?Rules Regarding Availability|Revisions to Documents Governing|Notation Votes?)", "Administrative"
        "^Attendance",                              "Attendance"
        ];
    % Use the first pattern that matches
    key = "SpecialTopics";
    for r = 1:size(rules,1)
        if ~isempty(regexp(heading, rules(r,1), 'once'))
            key = rules(r,2);
            return
        end
    end
end

%% ---- Local helper: section from a paragraph's opening words (2008) ----
function key = openerKey(line, allSections)
    rules = [
        "^The Manager of the System Open Market Account reported",          "FinancialMarkets"
        "^The information reviewed (at|for) (the|this) ",                    "StaffEconomy"
        "^(In the|The) (staff )?(economic )?forecast prepared for (the|this)", "StaffOutlook"
        "^In conjunction with (the|this) FOMC meeting",                      "ParticipantsViews"
        "^In (their|the) discussion of the economic (situation|and financial)", "ParticipantsViews"
        "^Members agreed that keeping the federal funds rate",               "PolicyAction"
        "^In (the Committee.s |the members. |their |the )discussion of monetary policy", "PolicyAction"
        ];
    if ~allSections, rules = rules(end-1:end, :); end    % only split off the policy discussion
    % Use the first pattern that matches the opening words
    key = "";
    for r = 1:size(rules,1)
        if ~isempty(regexp(line, rules(r,1), 'once'))
            key = rules(r,2);
            return
        end
    end
end
