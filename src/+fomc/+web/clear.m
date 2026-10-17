function clear(sessionId)
%CLEAR Forget a web session; the next message under that id starts a new one.
%   fomc.web.clear(sessionId)

arguments
    sessionId (1,1) string
end
fomc.web.store("remove", sessionId);
end
