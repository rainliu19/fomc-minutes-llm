function t = anchorLine(asOf)
%ANCHORLINE The date line at the top of a session's first message and of each specialist's.
%   t = fomc.anchorLine(asOf)

d = fomc.util.fmtDate(asOf);
t = "ANCHOR DATE: " + d + ". Today is " + d + "; nothing after it is known.";
end
