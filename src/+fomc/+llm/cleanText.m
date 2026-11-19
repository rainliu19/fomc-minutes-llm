function t = cleanText(t)
%CLEANTEXT Drop any inline <think>...</think> block from a model reply.
t = strtrim(regexprep(t, "<think>.*?</think>", ""));
end
