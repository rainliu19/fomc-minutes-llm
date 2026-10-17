%% FOMC project: market data not on FRED (S&P 500 from Yahoo, Shiller CAPE)
% Companion to macroeconomic_data.m; run one section at a time. Requires MATLAB R2019b+
% (no toolboxes; uses webread and readcell). Setup:
%   1. S&P 500: nothing to set up (Yahoo Finance chart API, no key). If it fails, download the
%      ^GSPC history as CSV from finance.yahoo.com and save it as data/raw/GSPC_yahoo_manual.csv
%      (columns Date and Close).
%   2. Shiller CAPE: the script finds the current ie_data.xls link on https://shillerdata.com/
%      (no API). If that fails, download it by hand to data/raw/ie_data.xls. If MATLAB cannot
%      read .xls, save it as .xlsx in Excel or Numbers as data/raw/ie_data.xlsx.
%   3. Output CSVs are frozen: once they exist the script reuses them. Set refresh = true to pull again.

clear; clc;
% Paths are relative to the repository root: step up if the current folder is pipeline/.
if endsWith(pwd, "pipeline"), cd(".."); end
% Settings: how far back to pull, where files go, and whether to re-download
startDate = datetime(1990,1,1);
outDir    = "data";
rawDir    = fullfile(outDir,"raw");
refresh   = false;                         % false: reuse existing CSVs. true: pull again
if ~isfolder(outDir), mkdir(outDir); end
if ~isfolder(rawDir), mkdir(rawDir); end
% Output files
gspcFile    = fullfile(outDir,"gspc_daily.csv");
shillerFile = fullfile(outDir,"shiller_monthly.csv");

%% 1. S&P 500 daily close (Yahoo Finance, ^GSPC)
% Columns: date, value (closing level of the index, no dividends)
% Pull the index from Yahoo; if that fails, fall back to a CSV downloaded by hand. Otherwise reuse the saved file
if refresh || ~isfile(gspcFile)
    try
        gspc = getYahooDaily("^GSPC", startDate);
        fprintf("Pulled ^GSPC from the Yahoo Finance API\n");
    catch ME
        warning("Yahoo API failed: %s", ME.message);
        manualFile = fullfile(rawDir,"GSPC_yahoo_manual.csv");
        assert(isfile(manualFile), "No Yahoo data. Download the ^GSPC history as CSV from " + ...
            "finance.yahoo.com and save it as " + manualFile);
        gspc = readManualYahoo(manualFile, startDate);
        fprintf("Read ^GSPC from the manual file %s\n", manualFile);
    end
    writetable(gspc, gspcFile);
else
    gspc = readtable(gspcFile);
    if ~isdatetime(gspc.date)
        gspc.date = datetime(string(gspc.date),"InputFormat","yyyy-MM-dd");
    end
    fprintf("Reusing the frozen file %s\n", gspcFile);
end
fprintf("OK   %-12s %6d obs  %s to %s  last close %g\n", "GSPC", height(gspc), ...
    string(gspc.date(1),"yyyy-MM-dd"), string(gspc.date(end),"yyyy-MM-dd"), gspc.value(end));

%% 2. Shiller monthly S&P price, dividends, earnings, CPI, GS10 and CAPE (shillerdata.com)
% Columns: date (first day of the month), price, dividend, earnings, cpi, gs10, cape
% The price is the month's average close, so a row is not known until the month ends.
% Find or download the Shiller spreadsheet, read it, and save a clean CSV. Otherwise reuse the saved file
if refresh || ~isfile(shillerFile)
    xlsFile = firstExisting([fullfile(rawDir,"ie_data.xlsx"), fullfile(rawDir,"ie_data.xls")]);
    if refresh || strlength(xlsFile) == 0
        try
            xlsFile = downloadShiller(rawDir);       % finds the current link on shillerdata.com
            fprintf("Downloaded the current Shiller file to %s\n", xlsFile);
        catch ME
            warning("Automatic Shiller download failed: %s", ME.message);
        end
    end
    assert(strlength(xlsFile) > 0, "Download ie_data.xls by hand from https://shillerdata.com/ " + ...
        "and save it in " + rawDir);
    shiller = readShiller(xlsFile, startDate);
    writetable(shiller, shillerFile);
else
    shiller = readtable(shillerFile);
    if ~isdatetime(shiller.date)
        shiller.date = datetime(string(shiller.date),"InputFormat","yyyy-MM-dd");
    end
    fprintf("Reusing the frozen file %s\n", shillerFile);
end
% Print a one-line summary of what was loaded
ok = ~isnan(shiller.cape);
fprintf("OK   %-12s %6d obs  %s to %s  last CAPE %.1f (%s)\n", "SHILLER", height(shiller), ...
    string(shiller.date(1),"yyyy-MM-dd"), string(shiller.date(end),"yyyy-MM-dd"), ...
    shiller.cape(find(ok,1,"last")), string(shiller.date(find(ok,1,"last")),"yyyy-MM"));

%% 3. Quick look
disp(head(gspc,3));
disp(tail(gspc,3));
disp(tail(shiller,3));

%% ---------- Local functions ----------
function tt = getYahooDaily(symbol, startDate)
    % Yahoo Finance chart API (unofficial, no key). Needs a browser-like user agent.
    % Ask Yahoo for daily bars between the start date and now (times as Unix seconds)
    t0 = startDate;  t0.TimeZone = "UTC";
    t1 = datetime("now","TimeZone","UTC");
    url  = "https://query1.finance.yahoo.com/v8/finance/chart/" + string(urlencode(char(symbol)));
    opts = weboptions("Timeout",60, "UserAgent","Mozilla/5.0");
    r = webread(url, "period1",sprintf("%d",round(posixtime(t0))), ...
                "period2",sprintf("%d",round(posixtime(t1))), ...
                "interval","1d", "events","history", opts);
    % Unpack the reply into dates and closing prices
    res = r.chart.result;
    if iscell(res), res = res{1}; end
    q = res.indicators.quote;
    if iscell(q), q = q{1}; end
    d = datetime(res.timestamp(:),"ConvertFrom","posixtime","TimeZone","UTC");
    d.TimeZone = "America/New_York";       % each daily bar is stamped at the New York open
    d.TimeZone = "";                       % keep the New York clock time, drop the zone
    d = dateshift(d,"start","day");
    % Tidy the table
    tt = cleanSeries(table(d, q.close(:), 'VariableNames', {'date','value'}), startDate);
end

function tt = readManualYahoo(file, startDate)
    % Read a hand-downloaded Yahoo CSV (Date and Close columns)
    T = readtable(file, "VariableNamingRule","preserve");
    d = T.Date;
    if ~isdatetime(d), d = datetime(string(d),"InputFormat","yyyy-MM-dd"); end
    tt = cleanSeries(table(dateshift(d,"start","day"), double(T.Close), ...
                           'VariableNames', {'date','value'}), startDate);
end

function tt = cleanSeries(tt, startDate)
    % Drop missing values and today's unfinished bar, sort, remove duplicate dates
    tt = tt(~isnan(tt.value),:);
    tt = tt(tt.date >= startDate & tt.date < dateshift(datetime("now"),"start","day"),:);
    tt = sortrows(tt,"date");
    [~,iu] = unique(tt.date,"last");
    tt = tt(iu,:);
    tt.date.Format = "yyyy-MM-dd";
end

function f = firstExisting(files)
    % Return the first file in the list that exists, or empty text
    f = "";
    for i = 1:numel(files)
        if isfile(files(i)), f = files(i); return; end
    end
end

function f = downloadShiller(rawDir)
    % shillerdata.com has no API and its file link changes with each update, so read the
    % page and pick out the current ie_data.xls link. Breaks only if the site layout changes.
    % Read the web page and pull out the link to the spreadsheet
    html = webread("https://shillerdata.com/", ...
        weboptions("Timeout",60, "UserAgent","Mozilla/5.0", "ContentType","text"));
    link = regexp(html, '(?:https:)?//[^"''\s<>]*ie_data\.xls[^"''\s<>]*', 'match', 'once');
    assert(~isempty(link), "No ie_data.xls link found on shillerdata.com");
    link = strrep(link, "&amp;", "&");
    if startsWith(link, "//"), link = "https:" + link; end
    f = fullfile(rawDir, "ie_data.xls");
    websave(f, link, weboptions("Timeout",120, "UserAgent","Mozilla/5.0"));
end

function v = toNum(x)
    if isnumeric(x) && isscalar(x), v = double(x); else, v = NaN; end
end

function tt = readShiller(file, startDate)
    % Read the sheet as raw cells
    C = readcell(file, "Sheet","Data");
    isTxt = @(x) ischar(x) || isstring(x);

    % Header row = the row whose first cell is the word "Date"
    % Find the header row (the row whose first cell is "Date")
    hdr = 0;
    for i = 1:min(30,size(C,1))
        if isTxt(C{i,1}) && strcmpi(strtrim(string(C{i,1})),"Date"), hdr = i; break; end
    end
    assert(hdr > 0, "Could not find the header row (first cell 'Date') in the Data sheet of " + file);

    % Header text per column: join the last few header rows
    % Build a header text for each column by joining the last few header rows
    nc = size(C,2);
    h = strings(1,nc);
    for j = 1:nc
        for i = max(1,hdr-3):hdr
            if isTxt(C{i,j}), h(j) = h(j) + " " + string(C{i,j}); end
        end
    end
    h = lower(strtrim(h));

    % CAPE column: header mentions CAPE or P/E10, but is not the total return or excess versions
    % Find the columns we need by their header text
    capeCol = find(contains(h,["cape","p/e10"]) & ~contains(h,["tr cape","total return","excess","yield"]), 1);
    assert(~isempty(capeCol), "Could not find the CAPE column in " + file);
    gs10Col = find(contains(h,"gs10"), 1);
    if isempty(gs10Col), gs10Col = 7; end
    % Columns 2 to 5 are the nominal S&P price, dividend, earnings and CPI in this file
    cols = [2 3 4 5 gs10Col capeCol];
    names = ["price","dividend","earnings","cpi","gs10","cape"];
    for k = 1:numel(cols)
        fprintf("Shiller column %-9s -> sheet column %2d, header: %s\n", names(k), cols(k), strtrim(h(cols(k))));
    end

    % Convert the data rows to numbers; Shiller writes dates as year.month, such as 1871.01
    body = C(hdr+1:end,:);
    col  = @(j) cellfun(@toNum, body(:,j));
    dn   = col(1);                         % dates look like 1871.01, and October is 1871.1
    year  = floor(dn + 1e-6);
    month = round((dn - year)*100);
    valid = ~isnan(dn) & dn > 1800 & month >= 1 & month <= 12;
    X = nan(numel(dn), numel(cols));
    for k = 1:numel(cols), X(:,k) = col(cols(k)); end
    X = X(valid,:);
    % Build the clean table and keep rows from the start date on
    tt = table(datetime(year(valid), month(valid), 1), ...
               X(:,1), X(:,2), X(:,3), X(:,4), X(:,5), X(:,6), ...
               'VariableNames', ["date" names]);
    tt = tt(~isnan(tt.price) & tt.date >= startDate,:);
    tt = sortrows(tt,"date");
    tt.date.Format = "yyyy-MM-dd";
end