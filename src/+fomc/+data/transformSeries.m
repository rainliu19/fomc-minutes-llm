function v = transformSeries(T, transform)
%TRANSFORMSERIES Level, one-step difference or year over year percent change.
%   v = fomc.data.transformSeries(T, transform), with T from fomc.data.valueAsOf.
%   NaN where undefined. yoy_pct uses the observation closest to a year earlier (within 20 days).

arguments
    T table
    transform (1,1) string {mustBeMember(transform, ["level","diff_1","yoy_pct"])}
end

n = height(T);
% Level is the raw value; diff_1 subtracts the previous value; yoy_pct compares with a year earlier
switch transform
    case "level"
        v = T.value;
    case "diff_1"
        v = [NaN; diff(T.value)];
        v = v(1:n);
    case "yoy_pct"
        v = NaN(n, 1);
        if n < 2
            return
        end
        % Find, for each date, the observation closest to one year before it (accepted if within 20 days)
        epoch = datetime(1970, 1, 1);
        x = days(T.date - epoch);
        target = days((T.date - calyears(1)) - epoch);
        j = interp1(x, (1:n).', target, "nearest", NaN);
        ok = ~isnan(j);
        ok(ok) = abs(x(j(ok)) - target(ok)) <= 20 & j(ok) < (find(ok));
        v(ok) = 100 * (T.value(ok) ./ T.value(j(ok)) - 1);
end
end
