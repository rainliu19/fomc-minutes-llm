%% FOMC project: export all macro and market data to CSV
% Reads what macroeconomic_data.m (sections 1 to 4) and market_data_extra.m saved in data/ and
% writes four CSVs back to data/:
%   raw_series_long.csv      every series stacked: date, series_id, value, source, frequency
%   macro_market_wide.csv    one row per date, one column per series (blank where no value)
%   fred_vintages_long.csv   revision history of the revised series: date, series_id, value, rtStart, rtEnd
%   series_dictionary.csv    one row per series: label, source, frequency, first/last date, units, notes
% Nothing is filled forward. Missing values are dropped from the long file and NaN in the wide
% file. Run one section at a time. FRED_API_KEY (from startup.m) only looks up units and titles.

clear; clc;
% Paths are relative to the repository root: step up if the current folder is pipeline/.
if endsWith(pwd, "pipeline"), cd(".."); end
% Check that the files the earlier scripts save are all there
outDir = "data";
apiKey = getenv("FRED_API_KEY");
need = ["fred_current.mat","fred_vintages.mat","debt_to_the_penny.csv","gspc_daily.csv","shiller_monthly.csv"];
for f = need
    assert(isfile(fullfile(outDir,f)), "Missing %s. Run macroeconomic_data.m sections 1 to 4 and market_data_extra.m first.", f);
end

%% 1. Load every source into one list of series
% FRED series first
load(fullfile(outDir,"fred_current.mat"),"S","catalog");
ids = string(catalog(:,1));  labels = string(catalog(:,2));  revised = cell2mat(catalog(:,3));
pullFred = fileDate(fullfile(outDir,"fred_current.mat"));

% Every source becomes one entry in the list L
L = {};     % each entry: id, label, source, revised, pull, T (date, value)
for k = 1:numel(ids)
    if isfield(S, ids(k))
        L{end+1} = mk(ids(k), labels(k), "FRED", revised(k), pullFred, S.(ids(k))); %#ok<SAGROW>
    else
        warning("No data for %s in fred_current.mat", ids(k));
    end
end

% Then the S&P 500, Shiller's series and Treasury debt
g = readDateCsv(fullfile(outDir,"gspc_daily.csv"));
L{end+1} = mk("GSPC", "S&P 500 index (Yahoo ^GSPC)", "Yahoo Finance", false, ...
              fileDate(fullfile(outDir,"gspc_daily.csv")), g(:,["date","value"]));

sh = readDateCsv(fullfile(outDir,"shiller_monthly.csv"));
shPull = fileDate(fullfile(outDir,"shiller_monthly.csv"));
% Shiller's CPI and GS10 columns are left out: FRED has both, and Shiller carries them forward past the latest release
shCols  = ["price","dividend","earnings","cape"];
shNames = ["S&P composite price (Shiller)","S&P dividend (Shiller)","S&P earnings (Shiller)","CAPE, P/E10 (Shiller)"];
for j = 1:numel(shCols)
    T = table(sh.date, sh.(shCols(j)), 'VariableNames', {'date','value'});
    L{end+1} = mk("SHILLER_" + upper(shCols(j)), shNames(j), "Shiller (shillerdata.com)", false, shPull, T); %#ok<SAGROW>
end

d = readDateCsv(fullfile(outDir,"debt_to_the_penny.csv"));
L{end+1} = mk("TREASURY_DEBT_TOTAL", "Total public debt outstanding", "US Treasury FiscalData", false, ...
              fileDate(fullfile(outDir,"debt_to_the_penny.csv")), ...
              table(d.date, d.totalPublicDebt, 'VariableNames', {'date','value'}));

% Pull each entry's facts into parallel columns (id, label, source, frequency, ...)
n = numel(L);
sid = strings(n,1); lab = strings(n,1); src = strings(n,1); rev = false(n,1);
pull = strings(n,1); freq = strings(n,1);
for i = 1:n
    sid(i) = L{i}.id;  lab(i) = L{i}.label;  src(i) = L{i}.source;
    rev(i) = L{i}.revised;  pull(i) = L{i}.pull;  freq(i) = inferFreq(L{i}.T.date);
end
fprintf("Loaded %d series (%d FRED, %d other)\n", n, sum(src=="FRED"), sum(src~="FRED"));

%% 2. Long file: every series stacked
% Stack the series one under another
parts = cell(n,1);
for i = 1:n
    T = L{i}.T;  m = height(T);
    parts{i} = table(T.date, repmat(sid(i),m,1), T.value, repmat(src(i),m,1), repmat(freq(i),m,1), ...
                     'VariableNames', {'date','series_id','value','source','frequency'});
end
raw = vertcat(parts{:});
raw.date.Format = "yyyy-MM-dd";
writetable(raw, fullfile(outDir,"raw_series_long.csv"));
fprintf("raw_series_long.csv      %8d rows\n", height(raw));

%% 3. Wide file: one row per date, one column per series
% Place each series into a column of a date-by-series grid (blank where there is no value)
allDates = unique(raw.date);
W = nan(numel(allDates), n);
for i = 1:n
    [~,loc] = ismember(L{i}.T.date, allDates);
    W(loc,i) = L{i}.T.value;
end
wide = [table(allDates, 'VariableNames', {'date'}), ...
        array2table(W, 'VariableNames', cellstr(matlab.lang.makeValidName(sid)))];
wide.date.Format = "yyyy-MM-dd";
writetable(wide, fullfile(outDir,"macro_market_wide.csv"));
fprintf("macro_market_wide.csv    %8d rows x %d columns\n", height(wide), width(wide));

%% 4. Vintage file: revision history of the revised FRED series
load(fullfile(outDir,"fred_vintages.mat"),"V");
% Stack the revision history of the revised series
vids = string(fieldnames(V));
vparts = cell(numel(vids),1);
for i = 1:numel(vids)
    T = V.(vids(i));  T = T(~isnan(T.value),:);
    vparts{i} = [table(repmat(vids(i),height(T),1), 'VariableNames', {'series_id'}), T];
end
vint = vertcat(vparts{:});
vint = vint(:,["date","series_id","value","rtStart","rtEnd"]);
vint.date.Format = "yyyy-MM-dd";  vint.rtStart.Format = "yyyy-MM-dd";  vint.rtEnd.Format = "yyyy-MM-dd";
writetable(vint, fullfile(outDir,"fred_vintages_long.csv"));
fprintf("fred_vintages_long.csv   %8d rows (%d series)\n", height(vint), numel(vids));

%% 5. Series dictionary
% Look up units and titles on FRED (needs the key); other sources have fixed units
units = strings(n,1);  ftitle = strings(n,1);  sa = strings(n,1);
for i = 1:n
    if src(i) == "FRED"
        if ~isempty(apiKey)
            try
                mt = getFredMeta(sid(i), apiKey);
                units(i) = mt.units;  ftitle(i) = mt.title;  sa(i) = mt.sa;
            catch ME
                warning("No metadata for %s: %s", sid(i), strrep(ME.message, apiKey, "<key hidden>"));
            end
            pause(0.6);
        end
    else
        units(i) = otherUnits(sid(i));
    end
end
% First date, last date, count and a plain-language note for each series
firstD = strings(n,1);  lastD = strings(n,1);  nobs = zeros(n,1);  notes = strings(n,1);
for i = 1:n
    dd = L{i}.T.date;  nobs(i) = numel(dd);
    if nobs(i) > 0
        firstD(i) = string(dd(1),"yyyy-MM-dd");  lastD(i) = string(dd(end),"yyyy-MM-dd");
    end
    notes(i) = noteFor(sid(i));
end
% Write the dictionary
dict = table(sid, lab, src, freq, firstD, lastD, nobs, rev, units, ftitle, sa, pull, notes, ...
    'VariableNames', {'series_id','label','source','frequency','first_date','last_date','n_obs', ...
                      'revised','units','fred_title','seasonal_adjustment','pull_date','notes'});
writetable(dict, fullfile(outDir,"series_dictionary.csv"));
fprintf("series_dictionary.csv    %8d rows\n", height(dict));

%% 6. Quick validation
% Sanity checks: no duplicates, no empty series, files small enough for GitHub
dup = height(raw) - height(unique(raw(:,["date","series_id"])));
fprintf("\nDuplicate (date, series_id) rows: %d (should be 0)\n", dup);
fprintf("Series with no data: %d (should be 0)\n", sum(nobs == 0));
fprintf("\n%-22s %-10s %7s  %-10s  %-10s\n", "series", "frequency", "n_obs", "first", "last");
for i = 1:n
    fprintf("%-22s %-10s %7d  %-10s  %-10s\n", sid(i), freq(i), nobs(i), firstD(i), lastD(i));
end
fprintf("\nFile sizes (GitHub rejects files over 100 MB):\n");
for f = ["raw_series_long.csv","macro_market_wide.csv","fred_vintages_long.csv","series_dictionary.csv"]
    info = dir(fullfile(outDir,f));
    fprintf("  %-26s %6.1f MB\n", f, info.bytes/1e6);
end

%% ---------- Local functions ----------
function e = mk(id, label, source, revised, pull, T)
    % Package one series: keep date and value, drop missing and future-dated rows
    T = T(:,["date","value"]);
    T = T(~isnan(T.value) & T.date <= datetime("today"),:);   % drop future-dated rows (CBO projections run to 2036)
    T = sortrows(T,"date");
    e = struct("id",string(id), "label",string(label), "source",string(source), ...
               "revised",logical(revised), "pull",string(pull), "T",T);
end

function T = readDateCsv(file)
    T = readtable(file);
    if ~isdatetime(T.date)
        T.date = datetime(string(T.date),"InputFormat","yyyy-MM-dd");
    end
end

function s = fileDate(f)
    % The file's last-modified date, used as the pull date
    d = dir(f);
    s = string(datetime(d(1).datenum,"ConvertFrom","datenum"),"yyyy-MM-dd");
end

function f = inferFreq(d)
    % Guess the frequency from the typical gap between dates
    if numel(d) < 2, f = "unknown"; return; end
    m = median(days(diff(d)));
    if m <= 4,        f = "daily";
    elseif m <= 8,    f = "weekly";
    elseif m <= 35,   f = "monthly";
    elseif m <= 100,  f = "quarterly";
    else,             f = "annual";
    end
end

function mt = getFredMeta(id, apiKey)
    % Ask FRED for a series' title, units and seasonal adjustment
    r = webread("https://api.stlouisfed.org/fred/series", "series_id",id, "api_key",apiKey, ...
                "file_type","json", weboptions("Timeout",60));
    s = r.seriess;
    if iscell(s), s = s{1}; end
    mt = struct("title",string(s(1).title), "units",string(s(1).units), ...
                "sa",string(s(1).seasonal_adjustment_short));
end

function u = otherUnits(id)
    % Units for the non-FRED series
    if id == "GSPC",                         u = "Index level";
    elseif id == "SHILLER_GS10",             u = "Percent";
    elseif id == "SHILLER_CAPE",             u = "Ratio";
    elseif id == "SHILLER_CPI",              u = "Index level";
    elseif startsWith(id,"SHILLER_"),        u = "Index points";
    elseif id == "TREASURY_DEBT_TOTAL",      u = "US dollars";
    else,                                    u = "";
    end
end

function n = noteFor(id)
    % Caveats worth knowing when using each series
    n = "";
    if id == "SHILLER_PRICE"
        n = "Monthly average of daily closes, so not known until month end. Latest row is a partial month";
    elseif id == "SHILLER_CAPE"
        n = "Uses the monthly average price, so not known until month end. After the last month with earnings, Shiller estimates earnings and CPI";
    elseif ismember(id, ["SHILLER_DIVIDEND","SHILLER_EARNINGS"])
        n = "Published with a lag of several months, so the latest rows are missing";
    elseif id == "GSPC"
        n = "Price index, no dividends. Last bar excludes the current day";
    elseif id == "THREEFYTP10"
        n = "Model estimate (Kim-Wright), can be revised, about a week behind";
    elseif ismember(id, ["FEDFUNDS","UMCSENT","MICH","GACDFSA066MSFRBPHI","GACDISA066MSFRBNY","ICSA"])
        n = "Dated at start of period but published later. Lag it before aligning to meetings";
    elseif ismember(id, ["GDPPOT","NROU"])
        n = "CBO estimates. Rows after the pull date are cut here, and the full projection history is in the vintage file";
    elseif id == "SP500"
        n = "FRED copy covers about 10 years only. Use GSPC for the long history";
    elseif id == "BAMLH0A0HYM2"
        n = "FRED history truncated to about 3 years. Use BAA10Y as the credit spread";
    elseif id == "DFEDTAR"
        n = "Single fed funds target, ends Dec 2008";
    end
end