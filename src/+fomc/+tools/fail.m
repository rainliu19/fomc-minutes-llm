function r = fail(msg)
%FAIL A tool result reporting an error the model can act on.
%   Errors are returned as data, not thrown, so the model can read them and retry.

r = struct("error", string(msg));
end
