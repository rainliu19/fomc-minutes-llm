%% FOMC project: market data not on FRED (S&P 500 from Yahoo, Shiller CAPE)
% Companion to macroeconomic_data.m. Same conventions: run one section at a time.
% Requires: MATLAB R2019b+ (no extra toolboxes; uses webread and readcell).
% Setup:
%   1. S&P 500: nothing to set up. It pulls from Yahoo Finance's chart API (no key).
%      If that fails, download the ^GSPC history as CSV from finance.yahoo.com and
%      save it as data/raw/GSPC_yahoo_manual.csv (needs columns Date and Close).
%   2. Shiller CAPE: the script downloads ie_data.xls itself by finding the current link
%      on https://shillerdata.com/ (there is no API). If that fails, download the file
%      by hand and save it as data/raw/ie_data.xls. If MATLAB cannot read .xls on your
%      computer, open it in Excel or Numbers, save as .xlsx, and save that as
%      data/raw/ie_data.xlsx instead.
%   3. The output CSVs are frozen: once they exist the script reuses them.
%      Set refresh = true below to pull again.

clear; clc;
startDate = datetime(1990,1,1);
outDir    = "data";
rawDir    = fullfile(outDir,"raw");
refresh   = false;                         % false: reuse existing CSVs. true: pull again
if ~isfolder(outDir), mkdir(outDir); end
if ~isfolder(rawDir), mkdir(rawDir); end
gspcFile    = fullfile(outDir,"gspc_daily.csv");
shillerFile = fullfile(outDir,"shiller_monthly.csv");

%% 1. S&P 500 daily close (Yahoo Finance, ^GSPC)
% Columns: date, value (closing level of the index, no dividends)
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
% Note: the price is the average of the month's daily closes, so a month's row is
% not known until the month has ended. Handle that lag when aligning to meetings.
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
    t0 = startDate;  t0.TimeZone = "UTC";
    t1 = datetime("now","TimeZone","UTC");
    url  = "https://query1.finance.yahoo.com/v8/finance/chart/" + string(urlencode(char(symbol)));
    opts = weboptions("Timeout",60, "UserAgent","Mozilla/5.0");
    r = webread(url, "period1",sprintf("%d",round(posixtime(t0))), ...
                "period2",sprintf("%d",round(posixtime(t1))), ...
                "interval","1d", "events","history", opts);
    res = r.chart.result;
    if iscell(res), res = res{1}; end
    q = res.indicators.quote;
    if iscell(q), q = q{1}; end
    d = datetime(res.timestamp(:),"ConvertFrom","posixtime","TimeZone","UTC");
    d.TimeZone = "America/New_York";       % each daily bar is stamped at the New York open
    d.TimeZone = "";                       % keep the New York clock time, drop the zone
    d = dateshift(d,"start","day");
    tt = cleanSeries(table(d, q.close(:), 'VariableNames', {'date','value'}), startDate);
end

function tt = readManualYahoo(file, startDate)
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
    f = "";
    for i = 1:numel(files)
        if isfile(files(i)), f = files(i); return; end
    end
end

function f = downloadShiller(rawDir)
    % shillerdata.com has no API and its file link changes with each update, so read the
    % page and pick out the current ie_data.xls link. Breaks only if the site layout changes.
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
    C = readcell(file, "Sheet","Data");
    isTxt = @(x) ischar(x) || isstring(x);

    % Header row = the row whose first cell is the word "Date"
    hdr = 0;
    for i = 1:min(30,size(C,1))
        if isTxt(C{i,1}) && strcmpi(strtrim(string(C{i,1})),"Date"), hdr = i; break; end
    end
    assert(hdr > 0, "Could not find the header row (first cell 'Date') in the Data sheet of " + file);

    % Header text per column: join the last few header rows
    nc = size(C,2);
    h = strings(1,nc);
    for j = 1:nc
        for i = max(1,hdr-3):hdr
            if isTxt(C{i,j}), h(j) = h(j) + " " + string(C{i,j}); end
        end
    end
    h = lower(strtrim(h));

    % CAPE column: header mentions CAPE or P/E10, but is not the total return or excess versions
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

    body = C(hdr+1:end,:);
    col  = @(j) cellfun(@toNum, body(:,j));
    dn   = col(1);                         % dates look like 1871.01, and October is 1871.1
    year  = floor(dn + 1e-6);
    month = round((dn - year)*100);
    valid = ~isnan(dn) & dn > 1800 & month >= 1 & month <= 12;
    X = nan(numel(dn), numel(cols));
    for k = 1:numel(cols), X(:,k) = col(cols(k)); end
    X = X(valid,:);
    tt = table(datetime(year(valid), month(valid), 1), ...
               X(:,1), X(:,2), X(:,3), X(:,4), X(:,5), X(:,6), ...
               'VariableNames', ["date" names]);
    tt = tt(~isnan(tt.price) & tt.date >= startDate,:);
    tt = sortrows(tt,"date");
    tt.date.Format = "yyyy-MM-dd";
end