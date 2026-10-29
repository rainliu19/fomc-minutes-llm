%% FOMC project: macro data acquisition and meeting alignment
% Requires MATLAB R2019b+ (no toolboxes; uses webread). Setup:
%   1. Get a free FRED API key: https://fred.stlouisfed.org/docs/api/api_key.html
%   2. In MATLAB: setenv("FRED_API_KEY","your_key_here")
%   3. Create data/fomc_meeting_dates.csv with a "Date" column (yyyy-mm-dd, last day of each meeting).
% Run one section at a time (Ctrl+Enter). Save As .mlx for a Live Script.

clear; clc;
% Paths are relative to the repository root: step up if the current folder is pipeline/.
if endsWith(pwd, "pipeline"), cd(".."); end
% Read the API key from the environment (never stored in a file) and set the output folder
apiKey    = getenv("FRED_API_KEY");
assert(~isempty(apiKey), "Set FRED_API_KEY first (see header).");
startDate = "1990-01-01";
outDir    = "data";
if ~isfolder(outDir), mkdir(outDir); end

%% 1. Series catalog  {FRED id, label, revised?}
% revised = true: also pull the vintage history (ALFRED) to reconstruct what was known on each date.
catalog = {
    % Inflation
    "PCEPILFE","Core PCE price index",true
    "PCEPI","Headline PCE price index",true
    "CPILFESL","Core CPI",true
    "CPIAUCSL","Headline CPI",true
    "MICH","UMich 1-yr inflation expectations",false
    "T5YIE","5-yr breakeven",false
    "T10YIE","10-yr breakeven",false
    "T5YIFR","5y5y forward inflation expectation",false
    % Output and spending
    "GDPC1","Real GDP",true
    "A191RL1Q225SBEA","Real GDP growth, annualized",true
    "PCEC96","Real personal consumption",true
    "RSAFS","Retail sales",true
    % Labor and wages
    "UNRATE","Unemployment rate",true
    "PAYEMS","Nonfarm payrolls",true
    "JTSJOL","JOLTS job openings",true
    "ICSA","Initial jobless claims",false
    "CES0500000003","Avg hourly earnings, private",true
    "ECIWAG","Employment Cost Index, wages",true
    % Sentiment
    "UMCSENT","UMich consumer sentiment",false
    "GACDFSA066MSFRBPHI","Philly Fed manufacturing index",false
    "GACDISA066MSFRBNY","Empire State manufacturing index",false
    % Policy and yields
    "FEDFUNDS","Effective fed funds rate",false
    "DFEDTAR","Fed funds target (single, until Dec 2008)",false
    "DFEDTARU","Target range upper",false
    "DFEDTARL","Target range lower",false
    "WALCL","Fed balance sheet",false
    "DFF","Effective fed funds rate, daily",false
    "DGS1MO","1-mo Treasury yield",false
    "DGS3MO","3-mo Treasury yield",false
    "DGS6MO","6-mo Treasury yield",false
    "DGS2","2-yr Treasury yield",false
    "DGS10","10-yr Treasury yield",false
    "T10Y2Y","10y-2y spread",false
    "T10Y3M","10y-3m spread",false
    "DFII10","10-yr real yield",false
    "THREEFYTP10","10-yr term premium (Kim-Wright)",false
    % Credit / financial conditions
    "BAMLH0A0HYM2","High-yield OAS",false
    "BAA10Y","Baa-10yr spread",false
    "NFCI","Chicago Fed NFCI",false
    "VIXCLS","VIX",false
    % Borrowing costs
    "MORTGAGE30US","30-yr fixed mortgage rate",false
    % Taylor-rule inputs
    "GDPPOT","CBO potential GDP",true
    "NROU","CBO natural rate of unemployment",true
    % Debt
    "GFDEBTN","Federal debt, total",true
    "GFDEGDQ188S","Federal debt / GDP",true
    % Market / other
    "SP500","S&P 500 (FRED, ~10 yrs only)",false
    "DTWEXBGS","Broad dollar index",false
    "DCOILWTICO","WTI crude",false
    "USREC","NBER recession indicator",false
    };
% Split the catalog into parallel lists of ids, labels and revised flags
ids = string(catalog(:,1));  labels = string(catalog(:,2));
revised = cell2mat(catalog(:,3));

%% 2. Pull current-vintage series (latest revised values)
% One request per series; a failure for one series does not stop the rest
S = struct();
for k = 1:numel(ids)
    try
        S.(ids(k)) = getFredSeries(ids(k), apiKey, startDate);
        fprintf("OK   %-20s %6d obs\n", ids(k), height(S.(ids(k))));
    catch ME
        warning("FAIL %s: %s", ids(k), strrep(ME.message, apiKey, "<key hidden>"));
    end
    pause(0.6);   % stay under FRED's rate limit (~120 requests/min)
end
save(fullfile(outDir,"fred_current.mat"), "S", "catalog");

%% 3. Pull full vintage history (ALFRED) for revised series
% Only the revised series: every vintage, so we can rebuild what was known on any date
V = struct();
for k = find(revised)'
    try
        V.(ids(k)) = getFredVintages(ids(k), apiKey, startDate);
        fprintf("VINT %-20s %8d rows\n", ids(k), height(V.(ids(k))));
    catch ME
        warning("FAIL vintages %s: %s", ids(k), strrep(ME.message, apiKey, "<key hidden>"));
    end
    pause(0.6);
end
save(fullfile(outDir,"fred_vintages.mat"), "V");

%% 4. Treasury debt (Fiscal Data API; no key needed)
% Verify field names at https://fiscaldata.treasury.gov/api-documentation/
try
    debtDaily = getTreasuryDebt();
    writetable(debtDaily, fullfile(outDir,"debt_to_the_penny.csv"));
catch ME
    warning("Treasury API failed: %s", ME.message);
end
% The average interest rate the Treasury pays on its marketable debt, monthly from 2001
try
    avgRate = getTreasuryAvgRate();
    writetable(avgRate, fullfile(outDir,"avg_interest_rates.csv"));
catch ME
    warning("Treasury average interest rate failed: %s", ME.message);
end
% Auction/issuance data: dataset "auctions_query" (v1/accounting/od/auctions_query)
% on the same API; same paging pattern as getTreasuryDebt below.

%% 5. Build meeting-aligned dataset (as-of join, no look-ahead)
% Dates the info set ends: the day before each meeting
meet = readtable(fullfile(outDir,"fomc_meeting_dates.csv"));
meet.Date = datetime(meet.Date);
meet = sortrows(meet,"Date");
asOf = meet.Date - days(1);          % info set = everything known the day before

% For each series and meeting, take the value known on that day (no look-ahead)
A = table(meet.Date, 'VariableNames', {'MeetingDate'});
for k = 1:numel(ids)
    id = ids(k);
    vals = nan(height(meet),1);  lag = nan(height(meet),1);
    if revised(k) && isfield(V,id)
        for i = 1:height(meet)
            [vals(i), od] = asOfValue(V.(id), asOf(i));
            lag(i) = days(asOf(i) - od);       % staleness of the latest reading
        end
        A.(id + "_lagDays") = lag;
    elseif isfield(S,id)
        T = S.(id);                             % unrevised: last obs on/before asOf
        for i = 1:height(meet)
            j = find(T.date <= asOf(i) & ~isnan(T.value), 1, "last");
            if ~isempty(j), vals(i) = T.value(j); end
        end
    end
    A.(id) = vals;
end
writetable(A, fullfile(outDir,"fomc_aligned_macro.csv"));
save(fullfile(outDir,"fomc_aligned_macro.mat"), "A");
disp(head(A(:,1:6)));

%% ---------- Local functions ----------
function tt = getFredSeries(id, apiKey, startDate)
    % Ask FRED for one series; "." in FRED means missing and becomes NaN
    url  = "https://api.stlouisfed.org/fred/series/observations";
    opts = weboptions("Timeout",60);
    r = webread(url, "series_id",id, "api_key",apiKey, "file_type","json", ...
                "observation_start",startDate, opts);
    o = r.observations;
    tt = table(datetime(string({o.date})',"InputFormat","yyyy-MM-dd"), ...
               str2double(string({o.value})'), ...        % "." -> NaN
               'VariableNames', {'date','value'});
end

function T = getFredVintages(id, apiKey, startDate)
    % All vintages: each row = (obs date, value, window in which it was the published value)
    url  = "https://api.stlouisfed.org/fred/series/observations";
    opts = weboptions("Timeout",120);
    % Page through the results until FRED returns fewer rows than the page size
    lim = 100000; offset = 0; parts = {};
    while true
        r = webread(url, "series_id",id, "api_key",apiKey, "file_type","json", ...
                    "observation_start",startDate, ...
                    "realtime_start","1990-01-01", "realtime_end","9999-12-31", ...
                    "limit",lim, "offset",offset, opts);
        o = r.observations;  n = numel(o);
        if n == 0, break; end
        parts{end+1} = table( ...
            datetime(string({o.date})',"InputFormat","yyyy-MM-dd"), ...
            str2double(string({o.value})'), ...
            datetime(string({o.realtime_start})',"InputFormat","yyyy-MM-dd"), ...
            datetime(string({o.realtime_end})',"InputFormat","yyyy-MM-dd"), ...
            'VariableNames', {'date','value','rtStart','rtEnd'}); %#ok<AGROW>
        offset = offset + n;
        if n < lim, break; end
    end
    T = vertcat(parts{:});
end

function [val, obsDate] = asOfValue(T, asOf)
    % Value of the most recent observation as it was published on date asOf
    % Rows whose publication window contains asOf; then take the latest observation
    m = T.rtStart <= asOf & T.rtEnd >= asOf & ~isnan(T.value);
    if ~any(m), val = NaN; obsDate = NaT; return; end
    sub = T(m,:);
    [obsDate, i] = max(sub.date);
    val = sub.value(i);
end

function T = getTreasuryAvgRate()
    % Average interest rate on total marketable Treasury debt, one row per month, dated the
    % first of the month (FiscalData dates it the last day)
    base = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v2/accounting/od/avg_interest_rates";
    r = webread(base, "fields","record_date,avg_interest_rate_amt", ...
                "filter","security_desc:eq:Total Marketable", "sort","record_date", ...
                "page[size]","10000", weboptions("Timeout",60));
    d = r.data;
    T = table(dateshift(datetime(string({d.record_date})',"InputFormat","yyyy-MM-dd"),"start","month"), ...
              str2double(string({d.avg_interest_rate_amt})'), 'VariableNames', {'date','avgInterestRate'});
end

function T = getTreasuryDebt()
    % Page through Treasury debt-to-the-penny, one row per day
    base = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v2/accounting/od/debt_to_penny";
    opts = weboptions("Timeout",60);
    page = 1; parts = {};
    while true
        r = webread(base, "fields","record_date,tot_pub_debt_out_amt", ...
                    "sort","record_date", "page[size]","10000", ...
                    "page[number]",string(page), opts);
        d = r.data;
        if isempty(d), break; end
        parts{end+1} = table(datetime(string({d.record_date})',"InputFormat","yyyy-MM-dd"), ...
                             str2double(string({d.tot_pub_debt_out_amt})'), ...
                             'VariableNames', {'date','totalPublicDebt'}); %#ok<AGROW>
        if page >= r.meta.total_pages, break; end
        page = page + 1;
    end
    T = vertcat(parts{:});
end