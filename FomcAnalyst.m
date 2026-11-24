classdef FomcAnalyst < matlab.apps.AppBase
%FOMCANALYST Desktop chat window for the FOMC minutes agent.
%   app = FomcAnalyst   opens the window (the same agent as fomc.chat and the web page).
%   Pick an anchor date, type a question, press Enter or Ask. New chat (or a new date)
%   starts a fresh session. Needs Ollama running locally; the app checks at startup and
%   offers to build the project model (models/<id>/Modelfile) if it is missing.
%
%   This file must stay in the repo root next to setup.m: fomc.config and fomc.skills.root
%   find data/, skills/ and agents/ relative to src/, and the packaged app keeps that layout.

    properties (Access = public)
        UIFigure       matlab.ui.Figure
        Grid           matlab.ui.container.GridLayout
        AnchorLabel    matlab.ui.control.Label
        AnchorPicker   matlab.ui.control.DatePicker
        ClearButton    matlab.ui.control.Button
        ChatLog        matlab.ui.control.TextArea
        QuestionField  matlab.ui.control.EditField
        SendButton     matlab.ui.control.Button
        StatusLabel    matlab.ui.control.Label
    end

    properties (Access = private)
        S              % the agent session (fomc.newSession); replaced on every turn
        D              % the data struct (fomc.data.load), loaded once
        Cfg            % fomc.config()
        Root string    % folder this file is in (the repo root, or the installed app's folder)
        Busy logical = false
    end

    methods (Access = private)

        function startupFcn(app)
            % Put the agent on the path (same as setup.m), load the data, start a session
            app.Root = string(fileparts(mfilename("fullpath")));
            addpath(fullfile(app.Root, "src"));
            d = uiprogressdlg(app.UIFigure, Title="Starting", Message="Loading data...", Indeterminate="on");
            cleanup = onCleanup(@() close(d));
            try
                app.Cfg = fomc.config(verbose=false);
                app.D = fomc.data.load(app.Cfg.dataDir);
                latest = fomc.latestAnchor(app.D);
                app.AnchorPicker.Limits = [min(app.D.meetings.ReleaseDate), latest];
                app.AnchorPicker.Value = latest;
                d.Message = "Starting a session...";
                newChat(app);
                d.Message = "Checking Ollama...";
                checkOllama(app);
            catch ME
                setStatus(app, "Startup failed: " + ME.message);
                uialert(app.UIFigure, ME.message, "Startup failed");
            end
        end

        function SendButtonPushed(app, ~)
            % Run one turn through the agent team and append it to the log
            q = strtrim(string(app.QuestionField.Value));
            if q == "" || app.Busy || isempty(app.S)
                return
            end
            app.Busy = true;
            app.SendButton.Enable = "off";
            appendLog(app, ["YOU: " + q; ""]);
            app.QuestionField.Value = "";
            d = uiprogressdlg(app.UIFigure, Title="Thinking", ...
                Message="The agents are reading the minutes (usually 10 to 35 s)...", Indeterminate="on");
            t = tic;
            try
                [app.S, answer] = fomc.agents.run(app.S, q);
                setStatus(app, sprintf("Answered in %.0f s.", toc(t)));
            catch ME
                answer = "(Error: " + ME.message + ")";
                setStatus(app, "The last question failed.");
            end
            close(d);
            appendLog(app, ["ASSISTANT: " + string(answer); ""]);
            app.SendButton.Enable = "on";
            app.Busy = false;
        end

        function QuestionFieldValueChanged(app, ~)
            % Enter in the question box sends it (ValueChanged also fires on losing focus,
            % so only send when the field still has text and no turn is running)
            SendButtonPushed(app, []);
        end

        function newChat(app, ~)
            % New chat button and AnchorPicker ValueChanged: fresh session at the picked date
            if app.Busy || isempty(app.D)
                return
            end
            app.S = fomc.newSession(app.AnchorPicker.Value, app.Cfg, Data=app.D);
            app.ChatLog.Value = "";
            setStatus(app, "New chat anchored at " + fomc.util.fmtDate(app.AnchorPicker.Value) + ...
                " | model " + app.Cfg.model + " | only minutes released by then are visible.");
        end

        function appendLog(app, lines)
            v = string(app.ChatLog.Value);
            if isscalar(v) && v == ""
                v = strings(0, 1);
            end
            app.ChatLog.Value = [v(:); lines(:)];
            try
                scroll(app.ChatLog, "bottom");
            catch
            end
            drawnow;
        end

        function setStatus(app, msg)
            app.StatusLabel.Text = msg;
        end

        function checkOllama(app)
            % Warn if Ollama is not reachable; offer to build the project model if it is missing
            url = "http://" + app.Cfg.endpoint + "/api/tags";
            try
                tags = webread(url, weboptions(Timeout=3));
            catch
                uialert(app.UIFigure, "Ollama is not running at " + app.Cfg.endpoint + ...
                    ". Start the Ollama app (or run 'ollama serve' in a terminal), then click New chat.", ...
                    "Ollama not found", Icon="warning");
                return
            end
            names = strings(0, 1);
            if isfield(tags, "models") && ~isempty(tags.models)
                names = erase(string({tags.models.name})', ":latest");
            end
            if any(names == app.Cfg.model)
                return
            end
            choice = uiconfirm(app.UIFigure, "Ollama does not have the model '" + app.Cfg.model + ...
                "'. Build it now from models/? This downloads its base model the first time " + ...
                "(about 1.5 GB for the default).", "Model missing", ...
                Options=["Build it", "Not now"], DefaultOption=1, CancelOption=2);
            if choice == "Build it"
                buildModel(app, app.Cfg.model);
            end
        end

        function buildModel(app, name)
            % ollama pull <base> then ollama create <name> -f models/<id>/Modelfile (models.json maps them)
            list = jsondecode(fileread(fullfile(app.Root, "models", "models.json")));
            if ~iscell(list)       % entries with different fields decode as a cell array
                list = num2cell(list);
            end
            hit = find(cellfun(@(m) string(m.name) == name, list), 1);
            if isempty(hit)
                uialert(app.UIFigure, "No entry for " + name + " in models/models.json.", "Model missing");
                return
            end
            modelfile = fullfile(app.Root, "models", list{hit}.id, "Modelfile");
            base = regexp(fileread(modelfile), "(?m)^FROM\s+(\S+)", "tokens", "once");
            exe = ollamaExe();
            d = uiprogressdlg(app.UIFigure, Title="Building " + name, Indeterminate="on", ...
                Message="Downloading " + string(base) + " and building " + name + "...");
            cmd = sprintf('"%s" pull %s && "%s" create %s -f "%s"', exe, base{1}, exe, name, modelfile);
            [status, out] = system(cmd);
            close(d);
            if status ~= 0
                uialert(app.UIFigure, "Build failed:" + newline + string(out), "Model build failed");
            end
        end

        function createComponents(app)
            app.UIFigure = uifigure(Visible="off", Name="FOMC Minutes Analyst", Position=[100 100 760 600]);
            app.Grid = uigridlayout(app.UIFigure, [4 4], ...
                RowHeight={30, "1x", 30, 20}, ColumnWidth={90, 140, "1x", 100});

            app.AnchorLabel = uilabel(app.Grid, Text="Anchor date", HorizontalAlignment="right");
            app.AnchorLabel.Layout.Row = 1; app.AnchorLabel.Layout.Column = 1;
            app.AnchorPicker = uidatepicker(app.Grid, DisplayFormat="yyyy-MM-dd", ...
                ValueChangedFcn=@(~, e) newChat(app, e), ...
                Tooltip="The agent sees only minutes and data public on this date");
            app.AnchorPicker.Layout.Row = 1; app.AnchorPicker.Layout.Column = 2;
            app.ClearButton = uibutton(app.Grid, Text="New chat", ButtonPushedFcn=@(~, e) newChat(app, e));
            app.ClearButton.Layout.Row = 1; app.ClearButton.Layout.Column = 4;

            app.ChatLog = uitextarea(app.Grid, Editable="off", WordWrap="on", FontSize=13);
            app.ChatLog.Layout.Row = 2; app.ChatLog.Layout.Column = [1 4];

            app.QuestionField = uieditfield(app.Grid, "text", ...
                Placeholder="Ask about the minutes, e.g. What did the Committee decide at the last meeting?", ...
                ValueChangedFcn=@(~, e) QuestionFieldValueChanged(app, e));
            app.QuestionField.Layout.Row = 3; app.QuestionField.Layout.Column = [1 3];
            app.SendButton = uibutton(app.Grid, Text="Ask", ButtonPushedFcn=@(~, e) SendButtonPushed(app, e));
            app.SendButton.Layout.Row = 3; app.SendButton.Layout.Column = 4;

            app.StatusLabel = uilabel(app.Grid, Text="", FontColor=[0.4 0.4 0.4], FontSize=11);
            app.StatusLabel.Layout.Row = 4; app.StatusLabel.Layout.Column = [1 4];

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = FomcAnalyst
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end

function exe = ollamaExe()
% MATLAB's PATH often lacks Homebrew's bin folder, so look in the usual places
exe = "ollama";
for p = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", ...
        "/Applications/Ollama.app/Contents/Resources/ollama"]
    if isfile(p)
        exe = p;
        return
    end
end
end
