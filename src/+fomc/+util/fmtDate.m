function s = fmtDate(d)
%FMTDATE Format datetimes as yyyy-MM-dd strings. NaT becomes "".

s = string(d, "yyyy-MM-dd");
s(ismissing(s)) = "";
end
