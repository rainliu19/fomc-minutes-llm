function ev = traceEvents(path)
%TRACEEVENTS A trace file (JSON lines) as a cell array of event structs, for tests.
lines = readlines(path);
ev = arrayfun(@jsondecode, lines(strlength(lines) > 0), UniformOutput=false);
end
