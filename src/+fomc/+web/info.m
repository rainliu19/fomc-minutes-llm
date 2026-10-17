function json = info()
%INFO Facts for the web page: default anchor date, model, meeting count.
%   json = fomc.web.info()

% Read a few facts from the data and settings and return them as JSON
D = fomc.data.load();
cfg = fomc.config();
names = fomc.data.plainNames();
series = struct("id", cellstr(names.series_id), "label", cellstr(names.name));
json = jsonencode(struct("series", series, "latestAnchor", fomc.util.fmtDate(fomc.latestAnchor(D)), ...
    "firstMeeting", fomc.util.fmtDate(min(D.meetings.MeetingDate)), ...
    "meetings", height(D.meetings), "model", cfg.model));
end
