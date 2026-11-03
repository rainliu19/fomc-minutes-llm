function ids = dataTopics(question, knownIds)
%DATATOPICS The data series a question is about, found from its wording.
%   ids = fomc.focus.dataTopics(question, knownIds)
%   Plain keyword rules ("unemployment", "mortgage", "yield curve"...) pick the series, most
%   specific topics first, at most 6. A series code written in the question counts too.
%   Only ids in knownIds are returned. No model.

q = lower(string(question));
rules = {
    "vix|volatil|financial stress|credit spread|financial conditions|high-yield|junk bond", ["VIXCLS", "BAA10Y", "NFCI"]
    "mortgage|housing", "MORTGAGE30US"
    "oil|crude|energy price", "DCOILWTICO"
    "dollar|currency|exchange rate", "DTWEXBGS"
    "debt|deficit", ["GFDEGDQ188S", "GFDEBTN", "TREASURY_AVG_RATE"]
    "balance sheet|quantitative|runoff|asset purchase", "WALCL"
    "stock|equit|s&p", ["GSPC", "SHILLER_CAPE"]
    "wage|pay growth|hourly earnings|compensation", ["CES0500000003", "ECIWAG"]
    "unemploy|jobless|labor market|payroll|job opening|hiring|employment|jobs", ["UNRATE", "PAYEMS", "JTSJOL", "ICSA"]
    "inflation|(?<![a-z])cpi(?![a-z])|(?<![a-z])pce(?![a-z])|consumer price|price index|price level", ["CPIAUCSL", "CPILFESL", "PCEPILFE", "T5YIFR"]
    "yield|treasur|curve|bond", ["DGS2", "DGS10", "T10Y2Y"]
    "sentiment|confidence|consumer", ["UMCSENT", "MICH"]
    "gdp|growth|economy|economic activity|spending|retail|recession|expansion|growing", ["A191RL1Q225SBEA", "GDPC1", "PCEC96", "RSAFS"]
    "fed funds|federal funds|policy rate|interest rate|target range|rate hike|rate cut|rates", ["FEDFUNDS", "DFEDTARU", "DFEDTARL"]
    };
ids = strings(0, 1);
for i = 1:size(rules, 1)
    if ~isempty(regexp(q, rules{i, 1}, "once"))
        ids = [ids; rules{i, 2}(:)]; %#ok<AGROW>
    end
end
% A series code typed in the question (UNRATE) is honored too
codes = regexp(string(question), "(?<![A-Za-z0-9_])[A-Z][A-Z0-9_]{3,}(?![A-Za-z0-9_])", "match");
ids = [ids; string(codes(:))];
ids = unique(ids, "stable");
ids = ids(ismember(ids, string(knownIds)));
ids = ids(1:min(6, numel(ids)));
end
