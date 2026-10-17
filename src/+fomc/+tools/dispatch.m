function [json, rec] = dispatch(ctx, name, args)
%DISPATCH Run one tool call the model asked for; return its result as JSON text.
%   [json, rec] = fomc.tools.dispatch(ctx, name, args)
%
%   args is a JSON string or decoded struct. Every failure comes back as {"error": "..."}
%   so the model can retry; nothing throws. Order: find the tool, parse args, input
%   guardrail, run, output guardrail, trace. rec (name, args, result, ok, ms) is the record.

arguments
    ctx (1,1) struct
    name (1,1) string
    args
end

% Find the tool the model named
t0 = tic;
reg = fomc.tools.registry();
i = find([reg.name] == name, 1);
ok = false;
parsed = struct();

if isempty(i)
    json = errorJson("Unknown tool '" + name + "'. Available tools: " + strjoin([reg.name], ", ") + ".");
else
    % Read the arguments the model sent
    [parsed, perr] = parseArgs(args);
    if perr ~= ""
        json = errorJson("Arguments for " + name + " were not valid JSON (" + perr + "). Resend the call with a JSON object.");
    else
        % Input guardrail: refuse calls that name dates after the anchor
        g = fomc.guard.checkToolInput(ctx, name, parsed);
        if ~g.ok
            json = errorJson(g.message);
            fomc.trace.logEvent(ctx, "guardrail_block", struct("stage", "tool_input", ...
                "tool", name, "args", parsed, "message", g.message));
        else
            % Run the tool, then check its output for anything dated after the anchor
            try
                result = reg(i).fn(ctx, parsed);
                json = string(jsonencode(result));
                o = fomc.guard.checkToolOutput(ctx, result, json);
                if o.ok
                    ok = ~isfield(result, "error");
                else
                    json = errorJson(o.message);
                    fomc.trace.logEvent(ctx, "guardrail_block", struct("stage", "tool_output", ...
                        "tool", name, "args", parsed, "message", o.message));
                end
            catch ME
                msg = fomc.trace.scrub(string(ME.message));
                json = errorJson(name + " failed: " + msg);
            end
        end
    end
end

% Record the call in the trace (and print it when verbose)
ms = round(toc(t0) * 1000);
rec = struct("name", name, "args", parsed, "result", json, "ok", ok, "ms", ms);
fomc.trace.logEvent(ctx, "tool_call", rec);
if ctx.verbose
    shown = char(json);
    shown = shown(1:min(numel(shown), 300));
    fprintf("  TOOL %s(%s) -> %s\n", name, compactArgs(parsed), shown);
end
end

function [s, err] = parseArgs(args)
s = struct();
err = "";
% Accept either an already-decoded struct or JSON text
if isstruct(args)
    s = args;
elseif (ischar(args) || isstring(args)) && isscalar(string(args))
    txt = strtrim(string(args));
    if txt == ""
        return
    end
    try
        s = jsondecode(txt);
    catch ME
        err = string(ME.message);
        return
    end
    if ~isstruct(s)
        err = "expected a JSON object";
        s = struct();
    end
else
    err = "expected a JSON object";
end
end

function j = errorJson(msg)
% Errors go back to the model as JSON so it can read them and retry
j = string(jsonencode(struct("error", string(msg))));
end

function s = compactArgs(a)
s = char(jsonencode(a));
if numel(s) > 120
    s = [s(1:117) '...'];
end
end
