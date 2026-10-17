function a = availableDate(rule, param, obs)
%AVAILABLEDATE When a non-vintaged observation became public.
%   a = fomc.data.availableDate(rule, param, obs)
%   rule "lagdays": obs + param days. rule "monthend": end of the obs month + param days.
%   Vintaged series use rtStart instead.

arguments
    rule (1,1) string
    param (1,1) double
    obs datetime
end

% Two rules: a fixed number of days after the observation, or after the end of its month
switch rule
    case "lagdays"
        a = obs + days(param);
    case "monthend"
        lastDay = dateshift(obs, "start", "month") + calmonths(1) - days(1);
        a = lastDay + days(param);
    otherwise
        error("fomc:data:badRule", "availableDate has no rule '%s'.", rule);
end
end
