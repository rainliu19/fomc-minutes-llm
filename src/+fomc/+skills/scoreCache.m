function out = scoreCache(action, model, meetingDate, output, nvp)
%SCORECACHE The AI scores of each meeting's minutes, saved once and read at question time.
%   out = fomc.skills.scoreCache("read", model, meetingDate) returns the saved result of
%   fomc.skills.scoreByDimension for that meeting and model, or [] if there is none.
%   fomc.skills.scoreCache("write", model, meetingDate, output) saves one, keeping dimensions
%   scored earlier that this run did not score.
%   fomc.skills.scoreCache("list", model) returns the meeting dates with a saved score.
%   Scoring one meeting takes the local model minutes, too slow while answering a question, so
%   pipeline/score_minutes.m scores the released minutes ahead of time. Files are
%   data/scores/<model>/<YYYY-MM-DD>.json (Folder=... for tests). Only the minutes' text goes
%   into a score, so a saved score is the same whenever it is read; it is used only once the
%   minutes are public on the anchor date.

arguments
    action (1,1) string {mustBeMember(action, ["read", "write", "list"])}
    model (1,1) string
    meetingDate (1,1) string = ""
    output = []
    nvp.Folder (1,1) string = ""
end

folder = nvp.Folder;
if folder == ""
    folder = fullfile(fomc.config(verbose=false).dataDir, "scores");
end
folder = fullfile(folder, model);
file = fullfile(folder, meetingDate + ".json");

switch action
    case "list"
        entries = dir(fullfile(folder, "*.json"));
        out = sort(erase(string({entries.name}), ".json")).';
    case "read"
        out = [];
        if isfile(file)
            out = jsondecode(fileread(file));
        end
    case "write"
        old = [];
        if isfile(file)
            old = jsondecode(fileread(file));
        end
        record = struct("meetingDate", meetingDate, "model", model, ...
            "scoredOn", string(datetime("now"), "yyyy-MM-dd"), "ok", output.ok, ...
            "issues", output.issues, "dimensionsScored", output.dimensionsScored, ...
            "score", output.score, "passages", output.passages);
        % Keep the dimensions an earlier run scored that this one did not
        if ~isempty(old)
            kept = setdiff(string(old.dimensionsScored), string(output.dimensionsScored), "stable");
            for d = kept(:).'
                record.score.dimensions.(d) = old.score.dimensions.(d);
                if isfield(old.passages, d)
                    record.passages.(d) = old.passages.(d);
                end
            end
            record.dimensionsScored = union(string(output.dimensionsScored), kept, "stable");
            record.ok = output.ok && old.ok;
            record.issues = [string(output.issues(:)); string(old.issues(:))];
        end
        if ~isfolder(folder)
            mkdir(folder);
        end
        fid = fopen(file, "w");
        fwrite(fid, jsonencode(record, PrettyPrint=true), "char");
        fclose(fid);
        out = record;
end
end
