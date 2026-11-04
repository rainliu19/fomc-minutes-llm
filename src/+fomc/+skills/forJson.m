function score = forJson(score)
%FORJSON A score struct made ready for jsonencode, so the JSON matches skills/fomc-score/schema.json.
%   text = jsonencode(fomc.skills.forJson(score))
%
%   MATLAB's jsondecode and jsonencode do not give back the JSON they read. A one-item array of
%   objects decodes to a struct and encodes as an object, and null decodes to [] and encodes as
%   [] (an empty array). The schema wants evidence as an array and score and confidence as null
%   when a dimension is not_discussed. So evidence becomes a cell array (encoded as an array,
%   empty or not), and an empty score or confidence becomes NaN (encoded as null).
%   Only the copy for encoding changes: callers keep [] in their own struct.

if ~(isstruct(score) && isscalar(score) && isfield(score, "dimensions") && isstruct(score.dimensions))
    return
end
for name = string(fieldnames(score.dimensions)).'
    dim = score.dimensions.(name);
    if ~isstruct(dim)
        continue
    end
    if isfield(dim, "evidence")
        dim.evidence = fomc.util.asCell(dim.evidence).';
    end
    for field = ["score", "confidence"]
        if isfield(dim, field) && isempty(dim.(field))
            dim.(field) = NaN;
        end
    end
    score.dimensions.(name) = dim;
end
end
