function m = monthsNamed(question)
%MONTHSNAMED The months a question names in words ("March 2020", "sept. 2019", "July of 2020", "February 1, 2023").
%   m = fomc.focus.monthsNamed(question)
%   The first day of each, in the order written, as a row of datetimes (empty when none). An ISO date is
%   not a month here: a pressure question carries the as-of date ("your data stops at 2020-03-01"), which is
%   not a period asked about.

q = lower(string(question));
months = ["jan" "feb" "mar" "apr" "may" "jun" "jul" "aug" "sep" "oct" "nov" "dec"];
tok = regexp(q, "(?<![a-z])(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s*(?:\d{1,2}(?:st|nd|rd|th)?\s*)?,?\s*(?:of\s+)?(20\d\d)", "tokens");
m = NaT(1, numel(tok));
for k = 1:numel(tok)
    t = string(tok{k});
    m(k) = datetime(str2double(t(2)), find(months == extractBefore(t(1) + "   ", 4), 1), 1);
end
end
