function issues = checkSchema(result)
%CHECKSCHEMA Check the required top-level, dimension and dimension-result keys.

dimensions = ["rate_path", "inflation", "labor_market", "economic_activity", ...
    "financial_conditions", "balance_sheet", "risk_balance"];
rootKeys = ["meeting_date", "scale", "dimensions"];
dimensionKeys = ["status", "score", "confidence", "rationale", "evidence"];
evidenceKeys = ["quote", "paragraph_ref"];
issues = strings(0, 1);

if ~isstruct(result) || ~isscalar(result)
    issues(end+1, 1) = "Score output must be one JSON object."; %#ok<AGROW>
    return
end
issues = checkKeys(result, rootKeys, rootKeys, "top-level", issues);
if isfield(result, "meeting_date") && ...
        (~isText(result.meeting_date) || isempty(regexp(char(string(result.meeting_date)), ...
        '^\d{4}-\d{2}-\d{2}$', 'once')))
    issues(end+1, 1) = "meeting_date must be a date in YYYY-MM-DD format."; %#ok<AGROW>
end
if isfield(result, "scale") && ...
        (~isText(result.scale) || string(result.scale) ~= "hawkish_positive")
    issues(end+1, 1) = "scale must be 'hawkish_positive'."; %#ok<AGROW>
end
if ~isfield(result, "dimensions") || ~isstruct(result.dimensions) || ~isscalar(result.dimensions)
    issues(end+1, 1) = "dimensions must be one object containing all seven dimensions."; %#ok<AGROW>
    return
end

actual = string(fieldnames(result.dimensions));
for name = dimensions
    if ~isfield(result.dimensions, name)
        issues(end+1, 1) = "dimensions is missing '" + name + "'."; %#ok<AGROW>
    end
end
for name = actual(:).'
    if ~any(name == dimensions)
        issues(end+1, 1) = "dimensions contains unexpected key '" + name + "'."; %#ok<AGROW>
    elseif isstruct(result.dimensions.(name)) && isscalar(result.dimensions.(name))
        dim = result.dimensions.(name);
        issues = checkKeys(dim, dimensionKeys, dimensionKeys, name, issues);
        if isfield(dim, "status") && isText(dim.status) && ...
                ~any(string(dim.status) == ["scored", "not_discussed"])
            issues(end+1, 1) = name + ".status must be 'scored' or 'not_discussed'."; %#ok<AGROW>
        end
        if isfield(dim, "rationale") && ~isText(dim.rationale)
            issues(end+1, 1) = name + ".rationale must be a string."; %#ok<AGROW>
        end
        if isfield(dim, "evidence")
            evidence = fomc.util.asCell(dim.evidence);
            if numel(evidence) > 3
                issues(end+1, 1) = name + ".evidence may contain at most 3 items."; %#ok<AGROW>
            end
            for k = 1:numel(evidence)
                item = evidence{k};
                if ~isstruct(item) || ~isscalar(item)
                    issues(end+1, 1) = name + ".evidence item " + k + " must be an object."; %#ok<AGROW>
                else
                    issues = checkKeys(item, "quote", evidenceKeys, name + ".evidence item " + k, issues);
                    if isfield(item, "quote") && ~isText(item.quote)
                        issues(end+1, 1) = name + ".evidence item " + k + " quote must be a string."; %#ok<AGROW>
                    end
                    if isfield(item, "paragraph_ref") && ~isText(item.paragraph_ref)
                        issues(end+1, 1) = name + ".evidence item " + k + " paragraph_ref must be a string."; %#ok<AGROW>
                    end
                end
            end
        end
    else
        issues(end+1, 1) = name + " must be one object."; %#ok<AGROW>
    end
end
end

function issues = checkKeys(value, required, allowed, label, issues)
actual = string(fieldnames(value));
for key = required
    if ~any(actual == key)
        issues(end+1, 1) = label + " is missing required key '" + key + "'."; %#ok<AGROW>
    end
end
for key = actual(:).'
    if ~any(key == allowed)
        issues(end+1, 1) = label + " has unexpected key '" + key + "'."; %#ok<AGROW>
    end
end
end

function tf = isText(value)
tf = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value));
end
