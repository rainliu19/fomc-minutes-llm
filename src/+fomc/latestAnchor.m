function d = latestAnchor(D)
%LATESTANCHOR The latest minutes release date: the default "today" (the data is frozen at its pull date).

arguments
    D (1,1) struct = fomc.data.load()
end
d = max(D.meetings.ReleaseDate);
end
