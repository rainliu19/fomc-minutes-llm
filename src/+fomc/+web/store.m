function out = store(action, key, value)
%STORE In-memory web sessions, kept between calls.
%   tf = fomc.web.store("has", key);    s = fomc.web.store("get", key);
%   fomc.web.store("set", key, s);      fomc.web.store("remove", key)
%   A persistent map, because MATLAB functions keep no state. Lost when MATLAB exits.

arguments
    action (1,1) string {mustBeMember(action, ["has", "get", "set", "remove"])}
    key (1,1) string
    value = []
end

% A map from session id to session, kept alive between calls
persistent sessions
if isempty(sessions)
    sessions = containers.Map(KeyType="char", ValueType="any");
end

k = char(key);
out = [];
% has / get / set / remove one session
switch action
    case "has"
        out = isKey(sessions, k);
    case "get"
        out = sessions(k);
    case "set"
        sessions(k) = value;
    case "remove"
        if isKey(sessions, k)
            remove(sessions, k);
        end
end
end
