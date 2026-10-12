# FOMC Minutes LLM

Data pipeline for studying FOMC meetings alongside the macroeconomic and market conditions around them. [One sentence on the LLM component: e.g. "LLM-based analysis of FOMC minutes (stance, sentiment, topics) is then compared against this data."]

This repo currently contains a MATLAB pipeline that:

1. Pulls 52 macro and market series from FRED, Yahoo Finance, Shiller, and US Treasury FiscalData (from 1990 onward).
2. Pulls the full revision history (vintages) for the revised FRED series, so you can reconstruct what was known at any point in time.
3. Exports everything as analysis-ready CSVs in `data/`.
4. Optionally builds a meeting-aligned dataset: for each FOMC meeting, the latest values that were publicly available the day before.

## Repository structure

```
fomc-minutes-llm/
├── macroeconomic_data.m      # FRED series, FRED vintages, Treasury debt, meeting alignment
├── market_data_extra.m       # S&P 500 (Yahoo Finance) and Shiller data
├── export_csvs.m             # Combines everything into CSVs
└── data/
    ├── macro_market_wide.csv
    ├── fred_vintages_long.csv
    ├── series_dictionary.csv
    ├── fomc_meeting_dates.csv    # you create this (see Setup)
    └── raw/                      # downloaded or manually saved source files
```

## Requirements

- MATLAB R2019b or later. No extra toolboxes are needed (the scripts use `webread` and `readcell`).
- A free [FRED API key](https://fred.stlouisfed.org/docs/api/api_key.html).
- An internet connection.

## Setup

1. **FRED API key.** In the MATLAB command window:
   ```matlab
   setenv("FRED_API_KEY", "your_key_here")
   ```
   This lasts for the current MATLAB session. To set it automatically at every launch, put the same line in a `startup.m` file (not included in this repo; keep your key out of version control).

2. **FOMC meeting dates** (only needed for the meeting-aligned dataset in step 5 of `macroeconomic_data.m`). Create `data/fomc_meeting_dates.csv` with one column named `Date`, formatted `yyyy-mm-dd`, one row per FOMC meeting. Use the last day of each meeting.

3. **Yahoo and Shiller fallbacks** (only if the automatic downloads fail, see below).

## Running the pipeline

Each script is split into sections. Run one section at a time (Ctrl+Enter), in this order:

| Step | Script / section | What it does | Writes (in `data/`) |
|------|------------------|--------------|---------------------|
| 1 | `macroeconomic_data.m`, section 1 | Defines the series catalog (46 FRED series, flagged as revised or not) | none |
| 2 | section 2 | Pulls current-vintage values for every FRED series | `fred_current.mat` |
| 3 | section 3 | Pulls full vintage history (ALFRED) for the 17 revised series | `fred_vintages.mat` |
| 4 | section 4 | Pulls total public debt from the Treasury FiscalData API (no key needed) | `debt_to_the_penny.csv` |
| 5 | `market_data_extra.m` | Pulls S&P 500 daily closes and Shiller monthly data | `gspc_daily.csv`, `shiller_monthly.csv` |
| 6 | `export_csvs.m` | Combines everything into the output CSVs | see Output files |
| 7 (optional) | `macroeconomic_data.m`, section 5 | Builds the meeting-aligned dataset | `fomc_aligned_macro.csv`, `fomc_aligned_macro.mat` |

`export_csvs.m` needs the outputs of steps 2 to 5 and stops with an error if any are missing. Section 5 of `macroeconomic_data.m` is not required for the export.

### Notes on the data pulls

- **FRED** requests are paced (0.6 s between calls) to stay under the rate limit. Failed series are reported as warnings with the API key masked.
- **S&P 500 (Yahoo Finance)** uses Yahoo's unofficial chart API. If it fails, download the `^GSPC` history as CSV from finance.yahoo.com and save it as `data/raw/GSPC_yahoo_manual.csv` (needs columns `Date` and `Close`).
- **Shiller** has no API. The script finds the current `ie_data.xls` link on [shillerdata.com](https://shillerdata.com/) and downloads it to `data/raw/`. If that fails, download the file by hand and save it as `data/raw/ie_data.xls`. If MATLAB cannot read `.xls` on your machine, convert it to `.xlsx` in Excel or Numbers and save it as `data/raw/ie_data.xlsx`.
- **Frozen files.** `market_data_extra.m` reuses `gspc_daily.csv` and `shiller_monthly.csv` if they already exist. Set `refresh = true` at the top of the script to pull again.
- **Treasury.** If the API fails, check the field names against the [FiscalData API documentation](https://fiscaldata.treasury.gov/api-documentation/). The same API also has Treasury auction and issuance data (`auctions_query`), which could be added with the same paging pattern.

## Output files

| File | Description | Shape |
|------|-------------|-------|
| `macro_market_wide.csv` | One row per date, one column per series. Blank where a series has no value on that date. | 13,431 rows x 53 columns |
| `fred_vintages_long.csv` | Revision history for the revised FRED series: `date, series_id, value, rtStart, rtEnd`. | 47,424 rows x 5 columns |
| `series_dictionary.csv` | One row per series: label, source, frequency, first and last date, number of observations, units, notes. | 52 rows x 13 columns |
| `raw_series_long.csv` | Every series stacked: `date, series_id, value, source, frequency`. | [rows] |
| `fomc_aligned_macro.csv` | One row per FOMC meeting with the latest known value of each series (optional, see below). | [rows] |

> `export_csvs.m` also writes `raw_series_long.csv`. [Note here whether it is committed or only generated locally. GitHub rejects files over 100 MB, and the script prints each file's size so you can check.]

Series dictionary columns: `series_id`, `label`, `source`, `frequency`, `first_date`, `last_date`, `n_obs`, `revised`, `units`, `fred_title`, `seasonal_adjustment`, `pull_date`, `notes`. Units, FRED title, and seasonal adjustment are filled in only when `FRED_API_KEY` is set.

### Meeting-aligned dataset

For each meeting date in `fomc_meeting_dates.csv`, the information set is everything known the day before the meeting. This avoids look-ahead bias:

- **Revised series** (17 of them): the value is taken from the vintage that was current on that day, using the real-time window (`rtStart`, `rtEnd`). A `<series>_lagDays` column records how stale the latest reading was, in days.
- **Unrevised series**: the last observation on or before that day.

## Series included

52 series: 46 from FRED and 6 from other sources. See `series_dictionary.csv` for labels, units, and coverage.

| Category | Series IDs |
|----------|------------|
| Inflation | `PCEPILFE`, `PCEPI`, `CPILFESL`, `CPIAUCSL` |
| Inflation expectations | `MICH`, `T5YIE`, `T10YIE`, `T5YIFR` |
| Output and spending | `GDPC1`, `A191RL1Q225SBEA`, `PCEC96`, `RSAFS` |
| Labor market | `UNRATE`, `PAYEMS`, `JTSJOL`, `ICSA`, `CES0500000003`, `ECIWAG` |
| Sentiment and regional surveys | `UMCSENT`, `GACDFSA066MSFRBPHI`, `GACDISA066MSFRBNY` |
| Policy rate and balance sheet | `FEDFUNDS`, `DFEDTAR`, `DFEDTARU`, `DFEDTARL`, `WALCL` |
| Yields and curve | `DGS3MO`, `DGS2`, `DGS10`, `T10Y2Y`, `T10Y3M`, `DFII10`, `THREEFYTP10` |
| Credit and financial conditions | `BAMLH0A0HYM2`, `BAA10Y`, `NFCI`, `VIXCLS`, `MORTGAGE30US` |
| Taylor-rule inputs (CBO) | `GDPPOT`, `NROU` |
| Debt | `GFDEBTN`, `GFDEGDQ188S`, `TREASURY_DEBT_TOTAL` |
| Markets and other | `SP500`, `GSPC`, `DTWEXBGS`, `DCOILWTICO`, `USREC` |
| Shiller | `SHILLER_PRICE`, `SHILLER_DIVIDEND`, `SHILLER_EARNINGS`, `SHILLER_CAPE` |

Sources: **FRED** (Federal Reserve Bank of St. Louis), **Yahoo Finance** (`^GSPC`), **Shiller** (shillerdata.com), and **US Treasury FiscalData** (Debt to the Penny). The Shiller file also contains CPI and GS10, but the export leaves them out because FRED has both and Shiller carries them forward past the latest release.

## Design notes

- **No forward filling.** Missing values are dropped from the long file and appear as blanks in the wide file, so no value shows up before it was dated.
- **Future-dated rows are removed.** Anything dated after the pull date is cut (for example, CBO projections that run to 2036 for `GDPPOT` and `NROU`). The full projection history stays in the vintage file.
- **Revisions are kept.** `fred_vintages_long.csv` stores each value with the real-time window in which it was current (vintages from 1990-01-01 onward).
- **Frequency is inferred** from the median gap between observations.
- **Validation.** `export_csvs.m` checks for duplicate `(date, series_id)` rows and for series with no data, then prints a summary of every series.

## Data caveats

These are also recorded in the `notes` column of `series_dictionary.csv`.

- **Publication lags.** `FEDFUNDS`, `UMCSENT`, `MICH`, `GACDFSA066MSFRBPHI`, `GACDISA066MSFRBNY`, and `ICSA` are dated at the start of the period but published later. Lag them before aligning to meetings.
- **Shiller series.** `SHILLER_PRICE` and `SHILLER_CAPE` use monthly average prices, so a month is not known until it ends, and the latest row is a partial month. After the last month with earnings, Shiller estimates earnings and CPI. `SHILLER_DIVIDEND` and `SHILLER_EARNINGS` are published with a lag of several months, so the latest rows are missing.
- **`GSPC`** is a price index without dividends, and the last bar excludes the current day.
- **`SP500`** (FRED) covers only about 10 years. Use `GSPC` for the long history.
- **`BAMLH0A0HYM2`** (FRED) is truncated to about 3 years. Use `BAA10Y` as the credit spread.
- **`THREEFYTP10`** is a model estimate (Kim-Wright) that can be revised, and it runs about a week behind.
- **`GDPPOT`, `NROU`** are CBO estimates.
- **`DFEDTAR`** is the single fed funds target and ends in December 2008. `DFEDTARU` and `DFEDTARL` cover the range afterwards.
- **Unofficial sources.** The Yahoo Finance API is unofficial, and the Shiller download works by reading the shillerdata.com page, so either can break if the provider changes things. The manual fallbacks above cover both.

## FOMC minutes and LLM analysis

[Describe this part of the project once it is in the repo: where the minutes come from (e.g. federalreserve.gov), which LLM(s) and prompts are used, what is extracted (rate decision, forward guidance, sentiment, topics), and how results connect to the meeting-aligned macro data.]

## Usage example

```python
import pandas as pd

wide = pd.read_csv("data/macro_market_wide.csv", parse_dates=["date"])
dictionary = pd.read_csv("data/series_dictionary.csv")

# 10-year Treasury yield, daily
dgs10 = wide[["date", "DGS10"]].dropna()

# Look up what a series is
print(dictionary.loc[dictionary.series_id == "DGS10", ["label", "units", "notes"]])
```

## Data sources and licensing

Data belongs to its original providers. Please review the terms of use for [FRED](https://fred.stlouisfed.org/docs/api/terms_of_use.html), [Yahoo Finance](https://policies.yahoo.com/), [Shiller](https://shillerdata.com/), and [US Treasury FiscalData](https://fiscaldata.treasury.gov/) before redistributing.

## License

[e.g. MIT for the code]
