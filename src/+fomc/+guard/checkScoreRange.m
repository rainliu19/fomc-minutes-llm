function issues = checkScoreRange(result)
%CHECKSCORERANGE Check statuses, score increments, confidence and evidence presence.

issues = strings(0, 1);
dimensions = ["rate_path", "inflation", "labor_market", "economic_activity", ...
    "financial_conditions", "balance_sheet", "risk_balance"];
if ~isstruct(result) || ~isscalar(result) || ~isfield(result, "dimensions") || ...
        ~isstruct(result.dimensions) || ~isscalar(result.dimensions)
    return
end

for name = dimensions
    if ~isfield(result.dimensions, name)
        continue
    end
    dim = result.dimensions.(name);
    if ~isstruct(dim) || ~isscalar(dim)
        continue
    end
    if ~all(isfield(dim, cellstr(["status", "score", "confidence", "evidence"])))
        continue
    end
    if ~isText(dim.status)
        issues(end+1, 1) = name + ".status must be 'scored' or 'not_discussed'."; %#ok<AGROW>
        continue
    end
    status = string(dim.status);
    evidence = fomc.util.asCell(dim.evidence);
    if status == "scored"
        score = dim.score;
        if ~isnumeric(score) || ~isscalar(score) || ~isfinite(score) || ...
                score < -1 || score > 1 || abs(score * 4 - round(score * 4)) > 1e-9
            issues(end+1, 1) = name + ".score must be numeric, within [-1, 1], in steps of 0.25."; %#ok<AGROW>
        end
        if ~isText(dim.confidence) || ~any(string(dim.confidence) == ["high", "medium", "low"])
            issues(end+1, 1) = name + ".confidence must be 'high', 'medium' or 'low'."; %#ok<AGROW>
        end
        if isempty(evidence)
            issues(end+1, 1) = name + " is scored but has no evidence."; %#ok<AGROW>
        end
    elseif status == "not_discussed"
        if ~isempty(dim.score)
            issues(end+1, 1) = name + ".score must be null when status is not_discussed."; %#ok<AGROW>
        end
        if ~isempty(dim.confidence)
            issues(end+1, 1) = name + ".confidence must be null when status is not_discussed."; %#ok<AGROW>
        end
        if ~isempty(evidence)
            issues(end+1, 1) = name + ".evidence must be empty when status is not_discussed."; %#ok<AGROW>
        end
    end
end
end

function tf = isText(value)
tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value));
end
