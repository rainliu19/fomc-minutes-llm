function T = coreGroups()
%COREGROUPS Core series by group, for the snapshot.
%   yoy: show the year over year change (index or count series). brief: shown in the first
%   message; the rest are available through getSeries.

% Helper: a small table of series ids for one group
g = @(group, ids, yoy) table(repmat(group, numel(ids), 1), ids(:), repmat(yoy, numel(ids), 1), ...
    VariableNames=["group", "series_id", "yoy"]);
% The core series, grouped; yoy marks those shown as year-over-year change
T = [
    g("inflation", ["PCEPILFE";"PCEPI";"CPILFESL";"CPIAUCSL"], true)
    g("inflation", ["T5YIE";"T10YIE";"T5YIFR"], false)
    g("labor", ["UNRATE";"JTSJOL";"ICSA"], false)
    g("labor", ["PAYEMS";"CES0500000003";"ECIWAG"], true)
    g("rates", ["DFEDTARU";"DFEDTARL";"DFEDTAR";"FEDFUNDS";"DGS3MO";"DGS2";"DGS10"; ...
        "T10Y2Y";"T10Y3M";"DFII10";"THREEFYTP10";"MORTGAGE30US"], false)
    g("rates", "WALCL", true)
    g("credit", ["BAA10Y";"BAMLH0A0HYM2";"NFCI";"VIXCLS";"DTWEXBGS";"SHILLER_CAPE"], false)
    g("credit", ["GSPC";"DCOILWTICO"], true)
    g("activity", ["A191RL1Q225SBEA";"GDPPOT";"NROU";"GFDEGDQ188S"], false)
    g("activity", ["GDPC1";"PCEC96";"RSAFS"], true)
    g("sentiment", ["UMCSENT";"MICH";"GACDFSA066MSFRBPHI";"GACDISA066MSFRBNY"], false)
    ];
% The few series that go in the first message of every session
briefIds = ["UNRATE";"PAYEMS";"CPIAUCSL";"PCEPILFE";"T5YIFR";"DFEDTARU";"DFEDTARL";"DFEDTAR"; ...
    "DGS2";"DGS10";"T10Y2Y";"BAA10Y";"VIXCLS";"UMCSENT";"A191RL1Q225SBEA"];
T.brief = ismember(T.series_id, briefIds);
end
