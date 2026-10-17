function D = load(dataDir)
%LOAD Read the project's CSVs into the agent's data struct (cached).
%   D = fomc.data.load() or fomc.data.load(dataDir)

arguments
    dataDir (1,1) string = fomc.config().dataDir
end

% Reuse the data already loaded for this folder: reading the CSVs is slow
persistent cachedDir cachedD
if ~isempty(cachedD) && cachedDir == dataDir
    D = cachedD;
    return
end

% Check that every expected file exists before reading any
files = ["macro_market_wide.csv", "fred_vintages_long.csv", "series_dictionary.csv", ...
    "series_availability.csv", fullfile("minutes", "fomc_minutes.csv")];
for f = files
    if ~isfile(fullfile(dataDir, f))
        error("fomc:data:missingFile", ...
            "Expected %s in %s. Run the data scripts (see README) or pull the latest main.", f, dataDir);
    end
end

% Read each file, then assemble the data struct
wide  = readtable(fullfile(dataDir, files(1)), TextType="string");
vint  = readtable(fullfile(dataDir, files(2)), TextType="string");
dict  = readtable(fullfile(dataDir, files(3)), TextType="string");
avail = readtable(fullfile(dataDir, files(4)), TextType="string");
mins  = readtable(fullfile(dataDir, files(5)), TextType="string");

D = fomc.data.build(wide, vint, dict, avail, mins);
% Remember it for next time
cachedDir = dataDir;
cachedD = D;
end
