function ids = idsIn(texts)
%IDSIN Paragraph ids (like 2020-03-15/policyAction/12) in some text, as unique strings.

% Ids look like 2020-03-15/policyAction/12
found = regexp(join(string(texts(:)), " "), "\d{4}-\d{2}-\d{2}/[A-Za-z]+/\d+", "match");
ids = unique(string(found(:)));
end
