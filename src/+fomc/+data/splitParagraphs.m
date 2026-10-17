function P = splitParagraphs(minutes)
%SPLITPARAGRAPHS One row per paragraph of each searchable section:
%   meetingIdx, section, paraIdx (1-based within the section), text.

S = fomc.data.sections();
S = S(S.name ~= "body", :);

% Collect pieces per meeting and section, then join them once at the end (faster than growing a table)
idx = cell(height(S) * height(minutes), 1);
sec = idx; pidx = idx; txt = idx;
n = 0;
for i = 1:height(minutes)
    for j = 1:height(S)
        t = minutes.(S.column(j))(i);
        if ismissing(t) || strlength(t) == 0
            continue
        end
        % One paragraph per non-empty line
        lines = strtrim(splitlines(t));
        lines(lines == "") = [];
        if isempty(lines)
            continue
        end
        n = n + 1;
        idx{n} = repmat(i, numel(lines), 1);
        sec{n} = repmat(S.name(j), numel(lines), 1);
        pidx{n} = (1:numel(lines)).';
        txt{n} = lines;
    end
end
% Join the pieces into one table
P = table(vertcat(idx{1:n}), vertcat(sec{1:n}), vertcat(pidx{1:n}), vertcat(txt{1:n}), ...
    VariableNames=["meetingIdx","section","paraIdx","text"]);
end
