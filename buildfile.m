function plan = buildfile
%BUILDFILE Build tasks. Run from the repository root:
%   buildtool check    Code Analyzer on src/
%   buildtool test     all MATLAB tests (no model needed; each test adds src/ to the path)
%   buildtool          check, then test

import matlab.buildtool.tasks.CodeIssuesTask
import matlab.buildtool.tasks.TestTask

% Two tasks: static code checks on src/, and the unit tests in tests/
plan = buildplan(localfunctions);
plan("check") = CodeIssuesTask("src");
plan("test") = TestTask("tests");
plan.DefaultTasks = ["check" "test"];
end
