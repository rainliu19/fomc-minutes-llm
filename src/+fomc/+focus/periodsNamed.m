function p = periodsNamed(question, asOf)
%PERIODSNAMED The periods a question asks about, as the first day of the month each starts, earliest first.
%   p = fomc.focus.periodsNamed(question, asOf)
%   The months named in words (fomc.focus.monthsNamed), a quarter ("Q2 2021", "the third quarter of 2021",
%   "2022 Q1"), a part of a year ("early", "mid", "late 2022", "the end of 2021": the earliest month it can mean),
%   and a distance after the anchor date ("3 months from now", "in two years", "next month, quarter or year").
%   A distance back ("3 months ago") is not asked about later, so it is not returned. No model.

q = lower(string(question));
p = fomc.focus.monthsNamed(q);

% A quarter, written three ways: Q2 2021, 2021 Q2, "second quarter of 2021"
for t = regexp(q, "(?<![a-z0-9])q([1-4])\s*(?:of\s*)?(20\d\d)", "tokens")
    p(end+1) = datetime(str2double(t{1}(2)), 3 * str2double(t{1}(1)) - 2, 1); %#ok<AGROW>
end
for t = regexp(q, "(20\d\d)\s*q([1-4])(?![0-9])", "tokens")
    p(end+1) = datetime(str2double(t{1}(1)), 3 * str2double(t{1}(2)) - 2, 1); %#ok<AGROW>
end
ordinals = ["first" "second" "third" "fourth"; "1st" "2nd" "3rd" "4th"];
for t = regexp(q, "(first|second|third|fourth|1st|2nd|3rd|4th)\s+quarter\s+(?:of\s+)?(20\d\d)", "tokens")
    [~, n] = find(ordinals == string(t{1}(1)), 1);
    p(end+1) = datetime(str2double(t{1}(2)), 3 * n - 2, 1); %#ok<AGROW>
end

% Part of a year: the earliest month it can mean, so a month the data shows is never called later
partWords = ["early" "beginning" "start" "mid" "late" "end"];
partMonth = [1 1 1 4 10 10];
for t = regexp(q, "(?<![a-z])(early|beginning of|start of|mid|late|end of)[\s-]*(?:the )?(?:year )?(20\d\d)", "tokens")
    p(end+1) = datetime(str2double(t{1}(2)), partMonth(partWords == strtok(t{1}(1))), 1); %#ok<AGROW>
end

% A distance after the anchor date, in months, quarters or years
units = struct("month", 1, "quarter", 3, "year", 12);
words = ["an" "a" "one" "two" "three" "four" "five" "six" "seven" "eight" "nine" "ten" "twelve" "eighteen"];
nums = [1 1 1 2 3 4 5 6 7 8 9 10 12 18];
here = dateshift(datetime(asOf), "start", "month");
number = "(\d+|" + strjoin(words, "|") + ")";
for pat = [number + "\s+(month|quarter|year)s?\s+(?:from now|from today|ahead|out|hence|later)", ...
           "(?<![a-z])in\s+" + number + "\s+(month|quarter|year)s?(?!\s+(?:ago|of|time))"]
    for t = regexp(q, pat, "tokens")
        n = str2double(t{1}(1));
        if isnan(n)
            n = nums(words == t{1}(1));
        end
        p(end+1) = here + calmonths(n * units.(t{1}(2))); %#ok<AGROW>
    end
end
if contains(q, "next month")
    p(end+1) = here + calmonths(1);
end
if contains(q, "next quarter")
    p(end+1) = dateshift(here, "start", "quarter") + calmonths(3);
end
if contains(q, "next year")
    p(end+1) = datetime(year(here) + 1, 1, 1);
end
p = sort(p);
end
