function json = schema()
%SCHEMA JSON Schema of the structured meeting analysis.
%   json = fomc.analysis.schema() returns it as text for the model's structured output.
%   The model cites paragraph ids, never quotes; fomc.analysis.structure fills in the
%   exact text. Output is kept short because writing is the slow part.

% Small helpers for building JSON Schema pieces
str = struct("type", "string");
desc = @(s, text) setfield(s, "description", text);
list = @(text) desc(struct("type", "array", "items", str), text);

% A cited figure, and a cited paragraph with the claim it supports
dataItem = obj(struct("series", str, "value", struct("type", "number"), "date", str));
evidenceItem = obj(struct("claim", desc(str, "One sentence."), ...
    "id", desc(str, "Paragraph id from a tool result, like 2020-03-15/policyAction/12.")));

% The fields of the analysis, each with a short instruction for the model
props = struct( ...
    "meetingDate", str, ...
    "summary", desc(str, "At most 80 words. State the decision, the vote and facts from the cited paragraphs. Give a reason only if a cited paragraph gives it."), ...
    "policyStance", desc(struct("type", "string", "enum", {["easing", "neutral", "tightening", "mixed"]}), ...
    "easing: rates cut or support added. tightening: rates raised or support removed. neutral: no change in stance. mixed: signals point both ways."), ...
    "keyDrivers", list("At most 3 short phrases."), ...
    "evidence", desc(struct("type", "array", "items", evidenceItem), "1 to 4 items."), ...
    "dataCited", desc(struct("type", "array", "items", dataItem), "At most 4 figures the summary relies on."), ...
    "caveats", list("At most 2 short items."));
% Turn it into JSON text
json = string(jsonencode(obj(props)));
end

function o = obj(props)
% Wrap fields as an object where all fields are required and no others are allowed
o = struct("type", "object", "properties", props, ...
    "required", {fieldnames(props).'}, "additionalProperties", false);
end
