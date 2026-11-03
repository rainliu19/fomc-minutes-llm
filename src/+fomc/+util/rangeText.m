function t = rangeText(lower, upper)
%RANGETEXT A rate target written the way the minutes write it: "3-3/4 to 4 percent".
%   t = fomc.util.rangeText(lower, upper); one target (lower == upper) is "3 percent".
%   Values in percent, to the nearest eighth of a point.

arguments
    lower (1,1) double
    upper (1,1) double
end

if lower == upper
    t = fraction(upper) + " percent";
else
    t = fraction(lower) + " to " + fraction(upper) + " percent";
end
end

function t = fraction(x)
% 3.75 -> "3-3/4", 0.25 -> "1/4", 4 -> "4"
whole = floor(x + 1e-9);
eighths = round((x - whole) * 8);
names = ["", "1/8", "1/4", "3/8", "1/2", "5/8", "3/4", "7/8"];
if eighths == 0
    t = string(whole);
elseif whole == 0
    t = names(eighths + 1);
else
    t = string(whole) + "-" + names(eighths + 1);
end
end
