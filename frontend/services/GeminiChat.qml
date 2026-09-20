pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // `caelestia shell prism open|toggle|close`: the dashboard straight on the
    // Prism tab, for a keybind. Prism is always the last dashboard tab.
    IpcHandler {
        target: "prism"

        function open(): void {
            const s = ShellState.forActive();
            s.dashboardTab = root.dashboardTabIndex;
            s.dashboard = true;
        }

        function close(): void {
            ShellState.forActive().dashboard = false;
        }

        function toggle(): void {
            const s = ShellState.forActive();
            if (s.dashboard && s.dashboardTab === root.dashboardTabIndex) {
                s.dashboard = false;
                return;
            }
            open();
        }

        // Re-fetch providers, models, settings and the active chat from the daemon
        function reload(): void {
            root._loadAll();
        }
    }

    // Index of the Prism tab in the dashboard (dash, media, performance, weather, prism)
    readonly property int dashboardTabIndex: 4

    // PRISM_DAEMON_URL points the tab at a daemon on another port (PRISM_PORT)
    readonly property string daemonUrl: Quickshell.env("PRISM_DAEMON_URL") || "http://127.0.0.1:5000"
    readonly property string tokenPath: Quickshell.env("HOME") + "/.local/share/prism/daemon.token"

    property string authToken: ""

    FileView {
        id: tokenFile
        preload: true
        blockLoading: true
        blockAllReads: true
        printErrors: false
        path: root.tokenPath
        Component.onCompleted: root.authToken = tokenFile.text().trim()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            tokenFile.path = root.tokenPath;
            root.authToken = tokenFile.text().trim();
        }
    }

    property bool isSending: false
    property string statusText: "Ready"
    property string currentModel: "gemini-3.6-flash"
    property var modelsList: []
    property var quotaData: null
    property string draft: ""
    property var attachments: []
    property var sessionsList: []
    property string activeSessionId: ""
    property bool watchActive: false

    property string currentProvider: "gemini"
    property var providersList: []
    readonly property var providerInfo: {
        for (let i = 0; i < providersList.length; i++) {
            if (providersList[i].id === currentProvider)
                return providersList[i];
        }
        if (providersList.length > 0)
            return providersList[0];
        return null;
    }
    readonly property string providerName: providerInfo?.name ?? "Gemini"
    readonly property string providerBubble: providerInfo?.bubble ?? "#4285F4"
    readonly property string providerPrimary: providerInfo?.primary ?? "#4285F4"
    readonly property string providerSecondary: providerInfo?.secondary ?? "#9B72CB"
    readonly property string providerTertiary: providerInfo?.tertiary ?? "#D96570"
    readonly property var providerGradient: providerInfo?.gradient ?? ["#4285F4", "#9B72CB", "#D96570", "#4285F4"]

    readonly property bool glowEnabled: settingsData?.glow?.enabled ?? true

    Timer {
        id: quotaRefreshTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            root.loadQuota();
            root._checkDaemon();
        }
    }

    // Start timestamp reported by /health. Everything below is fetched once
    // at startup, so when the daemon restarts (new providers, new config) the
    // lists would otherwise stay stale until the shell itself reloads.
    property real daemonStarted: 0

    function _checkDaemon() {
        const xhr = _xhr();
        xhr.open("GET", `${daemonUrl}/health`);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
            let started = 0;
            try {
                started = JSON.parse(xhr.responseText).started ?? 0;
            } catch (e) {}
            if (started !== root.daemonStarted) {
                root.daemonStarted = started;
                root._loadAll();
            }
        };
        xhr.send();
    }

    function _loadAll() {
        loadHistory();
        loadSessions();
        loadCurrentModel();
        loadModels();
        loadQuota();
        loadProviders();
        loadSettings();
    }

    Timer {
        id: titleRefresh
        interval: 2500
        repeat: false
        running: false
        onTriggered: root.loadSessions()
    }


    // GET/POST wrapper for the common shape below: token header, JSON body
    // and Content-Type when there is one, JSON.parse the reply, ignore
    // anything that isn't a plain 200 (the odd handler that needs more
    // than that keeps its own xhr, e.g. sendMessage, confirmTool).
    function _request(method, path, body, onOk) {
        const xhr = _xhr();
        xhr.open(method, `${daemonUrl}${path}`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        if (body !== undefined) xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    onOk(JSON.parse(xhr.responseText));
                } catch (e) {}
            }
        };
        xhr.send(body !== undefined ? JSON.stringify(body) : undefined);
    }

    function loadHistory() {
        _request("GET", "/history", undefined, res => {
            // An empty history must clear too: the session may have been
            // switched or wiped behind our back (daemon restart, IPC reload)
            if (res.history) {
                chatModel.clear();
                for (let i = 0; i < res.history.length; i++) {
                    const item = res.history[i];
                    const role = item.role === "user" ? "user" : "assistant";
                    let text = "";
                    let imgs = [];
                    if (item.parts && item.parts.length > 0) {
                        for (let p = 0; p < item.parts.length; p++) {
                            if (item.parts[p].text)
                                text += item.parts[p].text + "\n";
                            else if (item.parts[p].functionCall)
                                text += "";
                            else if (item.parts[p].inline_data) {
                                imgs.push({
                                    mime: item.parts[p].inline_data.mime_type || "image/png",
                                    data: item.parts[p].inline_data.data || ""
                                });
                            } else if (item.parts[p].type === "image") {
                                imgs.push({
                                    mime: item.parts[p].mime || "image/png",
                                    data: item.parts[p].data || ""
                                });
                            }
                        }
                    }
                    text = text.trim();
                    if (text || imgs.length > 0)
                        chatModel.append({ sender: role, text, images: imgs });
                }
            }
        });
    }

    function clearHistory() {
        _request("POST", "/clear", undefined, () => chatModel.clear());
    }

    function addAttachment(a) {
        if (a && a.data)
            attachments = [...attachments, a].slice(0, 8);
    }

    function removeAttachment(index) {
        attachments = attachments.filter((_, i) => i !== index);
    }

    function readFile(path) {
        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/read_file`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText);
                    if (res.data) {
                        addAttachment(res);
                        statusText = "Ready";
                    } else if (res.error === "too_large") {
                        statusText = qsTr("File > 11MB");
                    } else {
                        statusText = qsTr("Could not read file");
                    }
                } catch (e) {}
            }
        };
        xhr.send(JSON.stringify({ path }));
    }

    function stopWatch() {
        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/watch/stop`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText);
                    if (res.response) {
                        chatModel.append({ sender: "assistant", text: res.response });
                    }
                } catch (e) {}
            }
        };
        xhr.send();
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: root._request("GET", "/watch/status", undefined, res => watchActive = res.active)
    }

    function loadSessions() {
        _request("GET", "/sessions", undefined, res => {
            sessionsList = res.sessions ?? [];
            activeSessionId = res.active_id ?? "";
        });
    }

    function newChat() {
        _request("POST", "/session/new", undefined, () => {
            chatModel.clear();
            draft = "";
            statusText = "Ready";
            loadSessions();
            chatReset();
        });
    }

    function selectSession(id) {
        _request("POST", "/session/select", { id }, () => {
            chatModel.clear();
            loadHistory();
            loadSessions();
        });
    }

    function renameSession(id, title) {
        _request("POST", "/session/rename", { id, title }, () => loadSessions());
    }

    function deleteSession(id) {
        const wasActive = id === activeSessionId;
        _request("POST", "/session/delete", { id }, () => {
            loadSessions();
            if (wasActive) {
                chatModel.clear();
                loadHistory();
            }
        });
    }

    function pickFile() {
        _request("POST", "/pick_file", undefined, res => {
            if (res.data)
                addAttachment(res);
            else if (res.path)
                readFile(res.path);
        });
    }

    function pasteFromClipboard(onFail) {
        _request("POST", "/clipboard_image", undefined, res => {
            if (res.data) {
                addAttachment(res);
                statusText = "Ready";
            } else if (onFail) {
                onFail(res.error);
            }
        });
    }

    function sendMessage(msg) {
        msg = (msg || "").trim();
        const atts = attachments;
        console.log("[SENDDBG] sendMessage msg='" + msg + "' atts=" + atts.length + " isSending=" + isSending);
        if ((msg === "" && atts.length === 0) || isSending)
            return;

        chatModel.append({ sender: "user", text: msg, images: atts });
        draft = "";
        isSending = true;
        statusText = providerName + " думает...";

        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/chat`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            if (xhr.status === 200) {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.pending) {
                        // run_bash needs user confirmation — keep isSending until resolved
                        isSending = true;
                        statusText = qsTr("Ожидание подтверждения команды…");
                        root.toolConfirmRequested({
                            tool_call_id: response.tool_call_id || "",
                            command: response.command || "",
                            dangerous: !!response.dangerous,
                            persistable: response.persistable !== false,
                            patterns: response.patterns || []
                        });
                        return;
                    }
                    if (response.response) {
                        chatModel.append({ sender: "assistant", text: response.response });
                        statusText = "Ready";
                    } else if (response.error) {
                        chatModel.append({ sender: "assistant", text: qsTr("Error: %1").arg(response.error) });
                        statusText = "Error";
                    }
                } catch (e) {
                    chatModel.append({ sender: "assistant", text: qsTr("Error parsing response: %1").arg(e.toString()) });
                    statusText = "Parse Error";
                }
            } else {
                chatModel.append({ sender: "assistant", text: qsTr("Could not reach daemon (HTTP %1).").arg(xhr.status) });
                statusText = "Offline";
            }
            isSending = false;
            if (xhr.status === 200)
                attachments = [];
            if (xhr.status === 200)
                loadSessions();
            titleRefresh.restart();
        };
        xhr.send(JSON.stringify({ message: msg, attachments: atts }));
    }

    function loadModels() {
        _request("GET", "/models", undefined, res => modelsList = res.models);
    }

    function loadCurrentModel() {
        _request("GET", "/model", undefined, res => currentModel = res.model);
    }

    function selectModel(name) {
        _request("POST", "/model", { model: name }, res => currentModel = res.model);
    }

    function loadQuota() {
        _request("GET", "/quota", undefined, res => quotaData = res);
    }

    function loadProviders() {
        _request("GET", "/providers", undefined, res => {
            const prev = currentProvider;
            providersList = res.providers ?? [];
            currentProvider = res.current ?? prev;
        });
    }

    function selectProvider(id) {
        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/provider`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    const res = JSON.parse(xhr.responseText);
                    if (res.ok) {
                        currentProvider = res.provider;
                        currentModel = res.model;
                        chatModel.clear();
                        draft = "";
                        loadModels();
                        loadCurrentModel();
                        loadProviders();
                        loadSettings();
                        loadQuota();
                        chatReset();
                    }
                } catch (e) {}
            }
        };
        xhr.send(JSON.stringify({ provider: id }));
    }

    property var settingsData: null

    function loadSettings() {
        _request("GET", "/settings", undefined, res => settingsData = res);
    }

    function saveSettings(data) {
        const xhr = _xhr();
        xhr.open("PUT", `${daemonUrl}/settings`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                loadSettings();
                settingsSaved(true, "");
                return;
            }
            let err = xhr.status === 0 ? qsTr("Daemon unreachable") : qsTr("Save failed (%1)").arg(xhr.status);
            try {
                err = JSON.parse(xhr.responseText).error || err;
            } catch (e) {}
            settingsSaved(false, err);
        };
        xhr.send(JSON.stringify(data));
    }

    // Permission rules stored by the daemon (~/.config/prism/permissions.json):
    // [{pattern, action: "allow"|"deny", added}]
    property var permissions: []
    signal permissionError(string error)

    function loadPermissions() {
        _request("GET", "/permissions", undefined, res => permissions = res.rules || []);
    }

    function _permissionRequest(method, body) {
        const xhr = _xhr();
        xhr.open(method, `${daemonUrl}/permissions`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                try {
                    permissions = JSON.parse(xhr.responseText).rules || [];
                } catch (e) {
                    loadPermissions();
                }
                return;
            }
            let err = qsTr("Request failed (%1)").arg(xhr.status);
            try {
                err = JSON.parse(xhr.responseText).error || err;
            } catch (e) {}
            permissionError(err);
        };
        xhr.send(JSON.stringify(body));
    }

    // Add or update a rule; the daemon validates allow-rules against its allowlist
    function setPermission(pattern, action) {
        _permissionRequest("POST", { pattern: pattern, action: action });
    }

    function revokePermission(pattern) {
        _permissionRequest("DELETE", { pattern: pattern });
    }

    signal settingsSaved(bool ok, string error)
    signal settingsValidated(var result)
    signal chatReset()
    signal toolConfirmRequested(var info)

    function confirmTool(toolCallId, decision, pattern) {
        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/tool/confirm`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            if (xhr.status === 200) {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.pending) {
                        isSending = true;
                        statusText = qsTr("Ожидание подтверждения команды…");
                        root.toolConfirmRequested({
                            tool_call_id: response.tool_call_id || "",
                            command: response.command || "",
                            dangerous: !!response.dangerous,
                            persistable: response.persistable !== false,
                            patterns: response.patterns || []
                        });
                        return;
                    }
                    if (response.response) {
                        chatModel.append({ sender: "assistant", text: response.response });
                        statusText = "Ready";
                    } else if (response.error) {
                        chatModel.append({ sender: "assistant", text: qsTr("Error: %1").arg(response.error) });
                        statusText = "Error";
                    }
                } catch (e) {
                    chatModel.append({ sender: "assistant", text: qsTr("Error: %1").arg(e.toString()) });
                    statusText = "Parse Error";
                }
            } else if (xhr.status === 410 || xhr.status === 404 || xhr.status === 409) {
                // Timed out (the daemon recorded a denial) or settled elsewhere;
                // the history already tells the story.
                statusText = xhr.status === 410 ? qsTr("Confirmation expired") : "Ready";
                loadHistory();
            } else {
                chatModel.append({ sender: "assistant", text: qsTr("Could not reach daemon (HTTP %1).").arg(xhr.status) });
                statusText = "Offline";
            }
            isSending = false;
            if (xhr.status === 200)
                loadSessions();
            titleRefresh.restart();
        };
        const body = { tool_call_id: toolCallId, decision };
        if (pattern)
            body.pattern = pattern;
        xhr.send(JSON.stringify(body));
    }

    function validateSettings(apiKey, workerUrl) {
        const xhr = _xhr();
        xhr.open("POST", `${daemonUrl}/settings/validate`);
        if (root.authToken) xhr.setRequestHeader("X-Prism-Token", root.authToken);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    settingsValidated(JSON.parse(xhr.responseText));
                } catch (e) {}
            }
        };
        const payload = {};
        if (apiKey) payload.api_key = apiKey;
        if (workerUrl) payload.worker_url = workerUrl;
        xhr.send(JSON.stringify(payload));
    }

    function _xhr() {
        return new XMLHttpRequest();
    }

    Timer {
        id: startupRetryTimer
        interval: 1000
        repeat: false
        property int attempt: 0
        onTriggered: root._waitForDaemon()
    }

    function _waitForDaemon() {
        const xhr = _xhr();
        xhr.open("GET", `${daemonUrl}/health`);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    root.daemonStarted = JSON.parse(xhr.responseText).started ?? 0;
                } catch (e) {}
                _loadAll();
            } else if (startupRetryTimer.attempt < 30) {
                startupRetryTimer.attempt++;
                startupRetryTimer.start();
            }
        };
        xhr.send();
    }

    Component.onCompleted: root._waitForDaemon()

    ListModel {
        id: chatModel
    }

    // Expose model to views
    readonly property alias messages: chatModel
}
