function s = scrub(s)
%SCRUB Remove API key values from text before it is logged or shown.

% Replace the value of any API key found in the environment
for name = ["OPENAI_API_KEY", "FRED_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"]
    key = string(getenv(name));
    if strlength(key) >= 8
        s = replace(s, key, "[REDACTED]");
    end
end
end
