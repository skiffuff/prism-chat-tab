import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    implicitWidth: 900
    implicitHeight: 650
    color: palette.base

    // ==========================================
    // Palette — single source of truth for all colors (Catppuccin Mocha)
    // ==========================================
    readonly property var palette: ({
        base: "#1e1e2e",          // main background
        surface: "#181825",       // sidebar / input area background
        surfaceAlt: "#313244",    // cards, borders, second-level surfaces
        surfaceHover: "#45475a",  // hover state for buttons/items
        accent: "#89b4fa",        // primary accent (user bubbles, highlights)
        accentHover: "#b4befe",   // accent on hover
        text: "#cdd6f4",          // primary text
        textMuted: "#a6adc8",     // secondary text (chat titles, timestamps)
        textDim: "#6c7086",       // tertiary text (labels, placeholders)
        green: "#a6e3a1",         // status online / exec output
        red: "#f38ba8",           // status offline / errors
        yellow: "#f9e2af",        // exec message accent
        black: "#11111b",         // dark surface (exec background)
        white: "#ffffff"
    })

    // ==========================================
    // Backend endpoints (local Gemini daemon, see gemini_daemon.py)
    // ==========================================
    readonly property string baseUrl: "http://127.0.0.1:5000"
    readonly property string backendUrl: baseUrl + "/chat"
    readonly property string healthUrl: baseUrl + "/health"
    readonly property string confirmUrl: baseUrl + "/tool/confirm"
    // Prefix that marks a message as a shell command executed by the daemon
    readonly property string execMark: "[EXEC]:"

    // Daemon auth token (read from ~/.local/share/prism/daemon.token)
    property string authToken: ""
    // Id of the run_bash tool call waiting for user confirmation
    property string pendingToolCallId: ""

    // ==========================================
    // UI state
    // ==========================================
    property bool sidebarCollapsed: false
    property bool isDaemonOnline: false
    property bool isLoading: false
    property int activeChatIndex: 0
    property var providersModel: ListModel { }
    property string currentProvider: "gemini"
    property bool providersLoaded: false

    // Per-chat message history: chatsData[i] -> array of {sender, text, isExec, timestamp}
    property var chatsData: []

    // ==========================================
    // Data Models
    // ==========================================
    ListModel {
        id: chatsModel          // sidebar chat list
    }

    ListModel {
        id: messagesModel       // messages of the active chat
    }

    function readAuthToken() {
        try {
            var home = Qt.getenv("HOME");
            var tokenPath = "file://" + home + "/.local/share/prism/daemon.token";
            var xhr = new XMLHttpRequest();
            xhr.open("GET", tokenPath, false);
            xhr.send();
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var t = xhr.responseText.trim();
                if (t !== "")
                    root.authToken = t;
            }
        } catch (e) {
            // Token file not readable — daemon will reject requests (401).
        }
        checkDaemonHealth();
        loadProviders();
    }

    function loadProviders() {
        httpRequest("GET", root.baseUrl + "/providers", undefined,
            function(xhr) {
                try {
                    var obj = JSON.parse(xhr.responseText);
                    if (obj.providers) {
                        root.providersModel.clear();
                        obj.providers.forEach(function(p) {
                            root.providersModel.append(p);
                        });
                        // Set current provider if not already set
                        if (!root.providersLoaded) {
                            root.currentProvider = obj.current || "gemini";
                            root.providersLoaded = true;
                        }
                    }
                } catch (e) {
                    console.log("Failed to parse providers:", e.message);
                }
            },
            function(xhr) {
                console.log("Failed to load providers");
            }
        );
    }

    function setProvider(providerId) {
        if (providerId === root.currentProvider) return;

        var payload = JSON.stringify({ "provider": providerId });
        httpRequest("POST", root.baseUrl + "/provider", payload,
            function(xhr) {
                var obj = JSON.parse(xhr.responseText);
                if (obj.ok) {
                    root.currentProvider = providerId;
                    // Update first message sender for new chats
                    appendMessage(providerId === "gemini" ? "gemini" : "claude",
                        providerId === "gemini"
                            ? "Привет! Я Gemini Assistant в Caelestia Dashboard. Чем могу помочь по системе Arch Linux / Hyprland?"
                            : "Привет! Я Claude Assistant в Caelestia Dashboard. Чем могу помочь по системе Arch Linux / Hyprland?",
                        false);
                }
            },
            function(xhr) {
                appendMessage("system", "[ Ошибка смены провайдера ]", true);
            }
        );
    }

    // ==========================================
    // HTTP helper — single XHR implementation for all requests
    // ==========================================
    function httpRequest(method, url, payload, onSuccess, onError) {
        var xhr = new XMLHttpRequest();
        var done = false;

        xhr.open(method, url, true);
        if (root.authToken !== "")
            xhr.setRequestHeader("X-Prism-Token", root.authToken);
        if (payload !== undefined)
            xhr.setRequestHeader("Content-Type", "application/json");

        // Route the final response to the corresponding callback (fires once)
        xhr.onreadystatechange = function() {
            if (done || xhr.readyState !== XMLHttpRequest.DONE)
                return;
            done = true;
            if (xhr.status === 200 && xhr.responseText.length > 0)
                onSuccess(xhr);
            else
                onError(xhr);
        };

        xhr.onerror = function() {
            if (done)
                return;
            done = true;
            onError(xhr);
        };

        xhr.send(payload !== undefined ? payload : null);
    }

    // ==========================================
    // Chat management
    // ==========================================
    function createNewChat(title) {
        // Save the messages of the currently open chat before switching
        if (chatsModel.count > 0 && activeChatIndex >= 0 && activeChatIndex < chatsModel.count)
            saveCurrentChatMessages();

        var chatTitle = title || ("Диалог " + (chatsModel.count + 1));
        var chatId = "chat_" + Date.now();

        chatsData.push([]);
        chatsModel.append({ "chatId": chatId, "title": chatTitle });

        activeChatIndex = chatsModel.count - 1;
        messagesModel.clear();

        // Default greeting message
        appendMessage("gemini", "Привет! Я Gemini Assistant в Caelestia Dashboard. Чем могу помочь по системе Arch Linux / Hyprland?", false);
    }

    function saveCurrentChatMessages() {
        var msgs = [];
        for (var i = 0; i < messagesModel.count; i++) {
            var item = messagesModel.get(i);
            msgs.push({
                "sender": item.sender,
                "text": item.text,
                "isExec": item.isExec,
                "timestamp": item.timestamp
            });
        }
        chatsData[activeChatIndex] = msgs;
    }

    function loadChat(index) {
        if (index === activeChatIndex || index < 0 || index >= chatsModel.count)
            return;
        saveCurrentChatMessages();
        activeChatIndex = index;
        messagesModel.clear();

        var msgs = chatsData[index] || [];
        for (var i = 0; i < msgs.length; i++)
            messagesModel.append(msgs[i]);
    }

    function appendMessage(sender, text, isExec) {
        var timeStr = Qt.formatTime(new Date(), "hh:mm");
        var execFlag = isExec || false;

        // A message starting with [EXEC]: is rendered as a shell command
        if (typeof text === "string" && text.indexOf(execMark) === 0)
            execFlag = true;

        messagesModel.append({
            "sender": sender,
            "text": text,
            "isExec": execFlag,
            "timestamp": timeStr
        });

        // Auto-name the chat from the first user prompt
        if (sender === "user" && messagesModel.count <= 3) {
            var currentTitle = chatsModel.get(activeChatIndex).title;
            if (currentTitle.startsWith("Диалог") || currentTitle === "Новый диалог") {
                var autoTitle = text.trim();
                if (autoTitle.length > 20)
                    autoTitle = autoTitle.substring(0, 20) + "...";
                chatsModel.setProperty(activeChatIndex, "title", autoTitle);
            }
        }

        messageListView.positionViewAtEnd();
    }

    // ==========================================
    // Backend communication
    // ==========================================
    function sendMessage() {
        var query = inputTextArea.text.trim();
        if (query === "" || isLoading)
            return;

        appendMessage("user", query, false);
        inputTextArea.text = "";
        isLoading = true;

        httpRequest("POST", backendUrl, JSON.stringify({ "message": query }),
            function(xhr) {
                // Success: parse the daemon reply and show it
                isLoading = false;
                isDaemonOnline = true;
                handleDaemonResponse(xhr);
            },
            function(xhr) {
                // Failure: distinguish network errors from HTTP errors
                isLoading = false;
                isDaemonOnline = false;
                if (xhr.status === 0)
                    appendMessage("system", "[ Ошибка сети: не удалось подключиться к " + backendUrl + " ]", true);
                else if (xhr.status === 401)
                    appendMessage("system", "[ Неавторизованный запрос: проверьте daemon.token ]", true);
                else
                    appendMessage("system", "[ Ошибка связи с демоном (HTTP " + xhr.status + ") ]", true);
            }
        );
    }

    // Parse a daemon /chat or /tool/confirm reply: either a final answer or a
    // pending run_bash confirmation that must be shown to the user.
    function handleDaemonResponse(xhr) {
        try {
            var obj = JSON.parse(xhr.responseText);
            if (obj.pending) {
                root.pendingToolCallId = obj.tool_call_id || "";
                confirmCommandText.text = obj.command || "";
                confirmAllways.visible = !obj.dangerous;
                confirmDangerNote.visible = !!obj.dangerous;
                root.openConfirmModal();
                return;
            }
            var reply = obj.response ||
                        (obj.error ? "[ Ошибка демона: " + obj.error + " ]" :
                         "Получен пустой ответ от демона.");
            appendMessage("gemini", reply, reply.indexOf(execMark) === 0);
        } catch (e) {
            appendMessage("system", "[ Ошибка парсинга JSON ответа: " + e.message + " ]", true);
        }
    }

    // Send the user's decision for a pending run_bash call to /tool/confirm.
    function confirmTool(decision) {
        if (root.pendingToolCallId === "")
            return;
        confirmModal.close();
        var toolCallId = root.pendingToolCallId;
        root.pendingToolCallId = "";
        isLoading = true;
        httpRequest("POST", confirmUrl, JSON.stringify({ "tool_call_id": toolCallId, "decision": decision }),
            function(xhr) {
                isLoading = false;
                isDaemonOnline = true;
                handleDaemonResponse(xhr);
            },
            function(xhr) {
                isLoading = false;
                isDaemonOnline = false;
                if (xhr.status === 401)
                    appendMessage("system", "[ Неавторизованный запрос: проверьте daemon.token ]", true);
                else
                    appendMessage("system", "[ Ошибка подтверждения команды (HTTP " + xhr.status + ") ]", true);
            }
        );
    }

    function checkDaemonHealth() {
        httpRequest("GET", healthUrl, undefined,
            function() { isDaemonOnline = true; },
            function() { isDaemonOnline = false; }
        );
    }

    Component.onCompleted: {
        createNewChat("Новый диалог");
        readAuthToken();
    }

    // Periodically refresh the daemon online status
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.checkDaemonHealth()
    }

    // ==========================================
    // Main UI Layout
    // ==========================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // --------------------------------------
        // 1. SIDEBAR (chat list)
        // --------------------------------------
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: root.sidebarCollapsed ? 64 : 260
            color: palette.surface

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
            }

            // Right border separator
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: palette.surfaceAlt
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // Header controls: collapse toggle + new chat
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Toggle collapse button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 8
                        color: sidebarToggleHover.hovered ? palette.surfaceAlt : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: root.sidebarCollapsed ? "➔" : "◀"
                            color: palette.text
                            font.pixelSize: 14
                        }

                        HoverHandler { id: sidebarToggleHover }
                        TapHandler {
                            onTapped: root.sidebarCollapsed = !root.sidebarCollapsed
                        }
                    }

                    // "+ New Chat" button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: newChatHover.hovered ? palette.surfaceHover : palette.surfaceAlt
                        visible: !root.sidebarCollapsed

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "+"
                                color: palette.accent
                                font.pixelSize: 18
                                font.bold: true
                            }
                            Text {
                                text: "Новый чат"
                                color: palette.text
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }

                        HoverHandler { id: newChatHover }
                        TapHandler {
                            onTapped: root.createNewChat("Новый диалог")
                        }
                    }
                }

                // Compact "+ New Chat" button shown in collapsed mode
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 38
                    height: 38
                    radius: 8
                    color: newChatCollapsedHover.hovered ? palette.surfaceHover : palette.surfaceAlt
                    visible: root.sidebarCollapsed

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: palette.accent
                        font.pixelSize: 20
                        font.bold: true
                    }

                    HoverHandler { id: newChatCollapsedHover }
                    TapHandler {
                        onTapped: root.createNewChat("Новый диалог")
                    }
                }

                // Chat history section title
                Text {
                    text: "ИСТОРИЯ ЧАТОВ"
                    color: palette.textDim
                    font.pixelSize: 10
                    font.bold: true
                    Layout.leftMargin: 4
                    visible: !root.sidebarCollapsed
                }

                // Chat list
                ListView {
                    id: chatListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: chatsModel

                    delegate: Rectangle {
                        id: chatItem
                        width: chatListView.width
                        height: 42
                        radius: 8

                        property bool isActive: index === root.activeChatIndex
                        color: isActive ? palette.surfaceAlt : (chatHover.hovered ? palette.base : "transparent")

                        // Active indicator bar on the left edge
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            width: 3
                            radius: 2
                            color: palette.accent
                            visible: chatItem.isActive
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: chatItem.isActive ? 14 : 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "💬"
                                font.pixelSize: 14
                                color: chatItem.isActive ? palette.accent : palette.textMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: model.title
                                color: chatItem.isActive ? palette.text : palette.textMuted
                                font.pixelSize: 13
                                font.bold: chatItem.isActive
                                elide: Text.ElideRight
                                visible: !root.sidebarCollapsed
                            }
                        }

                        HoverHandler { id: chatHover }
                        TapHandler {
                            onTapped: root.loadChat(index)
                        }
                    }
                }
            }
        }

        // --------------------------------------
        // 2. MAIN CHAT AREA
        // --------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // 2a. Header with chat title and daemon status
            Rectangle {
                Layout.fillWidth: true
                height: 56
                color: palette.base

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: palette.surfaceAlt
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20

                    // Provider selector (Opencode-style)
                    Rectangle {
                        id: providerSelector
                        implicitWidth: 120
                        implicitHeight: 32
                        color: palette.surfaceAlt
                        radius: 8
                        border.width: 1
                        border.color: palette.surfaceAlt
                        visible: root.providersLoaded

                        MouseArea {
                            anchors.fill: parent
                            onClicked: providerMenu.open()
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 50
                                color: {
                                    var provider = currentProvider
                                    if (provider === "gemini") return "#4285F4"
                                    if (provider === "anthropic") return "#D97757"
                                    return palette.surface
                                }
                            }
                            Text {
                                text: currentProvider === "gemini" ? "Gemini" : "Claude"
                                color: palette.text
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                text: "▼"
                                color: palette.textDim
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Provider menu
                    Menu {
                        id: providerMenu
                        implicitWidth: 180
                        property var currentProvider: root.currentProvider

                        MenuItem {
                            text: "Gemini"
                            checkable: true
                            checked: root.currentProvider === "gemini"
                            onTriggered: root.setProvider("gemini")
                        }
                        MenuItem {
                            text: "Claude"
                            checkable: true
                            checked: root.currentProvider === "anthropic"
                            onTriggered: root.setProvider("anthropic")
                        }
                    }

                    // Current chat title
                    Text {
                        text: chatsModel.count > 0 && root.activeChatIndex < chatsModel.count ?
                              chatsModel.get(root.activeChatIndex).title : "Gemini Chat"
                        color: palette.text
                        font.pixelSize: 16
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Status indicator (online/offline)
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: root.isDaemonOnline ? palette.green : palette.red

                            Behavior on color {
                                ColorAnimation { duration: 300 }
                            }

                            // Pulse animation while the daemon is online
                            SequentialAnimation on opacity {
                                running: root.isDaemonOnline
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            text: root.isDaemonOnline ? "Online" : "Offline"
                            color: root.isDaemonOnline ? palette.green : palette.red
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
            }

            // 2b. Message list
            ListView {
                id: messageListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                topMargin: 16
                bottomMargin: 16
                leftMargin: 20
                rightMargin: 20
                model: messagesModel

                delegate: Item {
                    id: messageDelegate
                    width: messageListView.width - messageListView.leftMargin - messageListView.rightMargin
                    height: messageContent.height + 6

                    property bool isUser: model.sender === "user"
                    property bool isSystem: model.sender === "system"
                    property bool isExecMsg: model.isExec || false

                    // Smooth entry animation
                    opacity: 0
                    transform: Translate {
                        id: animTranslate
                        y: 15
                    }

                    Component.onCompleted: {
                        messageDelegate.opacity = 1;
                        animTranslate.y = 0;
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    Behavior on transform {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    // Message bubble
                    Rectangle {
                        id: messageContent
                        anchors.right: messageDelegate.isUser ? parent.right : undefined
                        anchors.left: !messageDelegate.isUser ? parent.left : undefined
                        width: Math.min(childrenRect.width + 24, messageDelegate.width * 0.8)
                        height: innerColumn.height + 20

                        // User (right, accent) / assistant (left) / exec output (dark, bordered)
                        color: messageDelegate.isUser ? palette.accent :
                               (messageDelegate.isExecMsg ? palette.black : palette.surfaceAlt)

                        radius: 14
                        border.width: messageDelegate.isExecMsg ? 1 : 0
                        border.color: messageDelegate.isExecMsg ? palette.yellow : "transparent"

                        ColumnLayout {
                            id: innerColumn
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            spacing: 4

                            // Sender badge for assistant / exec messages
                            Text {
                                text: messageDelegate.isExecMsg ? "⚡ SYSTEM EXEC" : "Gemini"
                                color: messageDelegate.isExecMsg ? palette.yellow : palette.accent
                                font.pixelSize: 11
                                font.bold: true
                                visible: !messageDelegate.isUser
                            }

                            // Message text
                            Text {
                                Layout.fillWidth: true
                                text: model.text
                                color: messageDelegate.isUser ? palette.black :
                                       (messageDelegate.isExecMsg ? palette.green : palette.text)
                                font.pixelSize: 13
                                font.family: messageDelegate.isExecMsg ? "JetBrains Mono, Fira Code, monospace" : "Sans"
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }

                            // Timestamp
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: model.timestamp || ""
                                color: messageDelegate.isUser ? palette.surfaceAlt : palette.textMuted
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // 2c. Input area
            Rectangle {
                Layout.fillWidth: true
                height: 80
                color: palette.base

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: palette.surfaceAlt
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Text input with focus highlight
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: palette.surface
                        radius: 12
                        border.width: 1
                        border.color: inputTextArea.activeFocus ? palette.accent : palette.surfaceAlt

                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 6
                            clip: true

                            TextArea {
                                id: inputTextArea
                                placeholderText: "Спросите Gemini или введите команду..."
                                placeholderTextColor: palette.textDim
                                color: palette.text
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                verticalAlignment: TextEdit.AlignVCenter
                                selectByMouse: true

                                // Enter sends, Shift+Enter inserts a newline
                                Keys.onPressed: function(event) {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        event.accepted = true;
                                        root.sendMessage();
                                    }
                                }
                            }
                        }
                    }

                    // Spinner while waiting for the daemon response
                    BusyIndicator {
                        id: loadingIndicator
                        running: root.isLoading
                        visible: root.isLoading
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                    }

                    // Send button
                    Rectangle {
                        id: sendButton
                        visible: !root.isLoading
                        width: 44
                        height: 44
                        radius: 12

                        property bool canSend: inputTextArea.text.trim().length > 0
                        color: canSend ? (sendHover.hovered ? palette.accentHover : palette.accent) : palette.surfaceAlt

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "➤"
                            color: sendButton.canSend ? palette.black : palette.textDim
                            font.pixelSize: 16
                        }

                        HoverHandler { id: sendHover }
                        TapHandler {
                            onTapped: {
                                if (sendButton.canSend)
                                    root.sendMessage();
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // run_bash confirmation modal
    // ==========================================
    function openConfirmModal() {
        confirmModal.x = Math.round(root.width / 2 - confirmModal.width / 2);
        confirmModal.y = Math.round(root.height / 2 - confirmModal.height / 2);
        confirmModal.open();
    }

    Popup {
        id: confirmModal
        width: 520
        implicitHeight: column.implicitHeight + 40
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        background: Rectangle {
            color: palette.surface
            radius: 12
            border.width: 1
            border.color: palette.surfaceAlt
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Header with icon
            RowLayout {
                spacing: 12

                Rectangle {
                    width: 40
                    height: 40
                    radius: 10
                    color: {
                        if (confirmDangerNote.visible) return palette.red + "33"
                        return palette.accent + "33"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: confirmDangerNote.visible ? "⚠" : "⚡"
                        color: confirmDangerNote.visible ? palette.red : palette.accent
                        font.pixelSize: 20
                        font.bold: true
                    }
                }

                ColumnLayout {
                    spacing: 4

                    Text {
                        text: "Разрешить выполнение?"
                        color: palette.text
                        font.pixelSize: 17
                        font.bold: true
                    }

                    Text {
                        text: "Модель хочет выполнить команду в терминале"
                        color: palette.textMuted
                        font.pixelSize: 13
                    }
                }
            }

            // Command display
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: confirmCommandText.implicitHeight + 16
                color: palette.black
                radius: 8
                border.width: 1
                border.color: palette.yellow + "66"

                Text {
                    id: confirmCommandText
                    anchors.fill: parent
                    anchors.margins: 12
                    color: palette.green
                    font.pixelSize: 13
                    font.family: "JetBrains Mono, Fira Code, monospace"
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }

            // Danger warning
            Text {
                id: confirmDangerNote
                visible: false
                text: "Опасная команда — аккуратно."
                color: palette.red
                font.pixelSize: 13
                font.bold: true
            }

            // Opencode-style buttons: two main options
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Button {
                    id: confirmDeny
                    Layout.fillWidth: true
                    text: "Отклонить"
                    palette.buttonText: palette.text
                    background: Rectangle {
                        color: palette.red
                        radius: 8
                        implicitHeight: 42
                    }
                    onClicked: root.confirmTool("deny")
                }

                Button {
                    id: confirmOnce
                    Layout.fillWidth: true
                    text: "Один раз"
                    palette.buttonText: palette.black
                    background: Rectangle {
                        color: palette.accent
                        radius: 8
                        implicitHeight: 42
                    }
                    onClicked: root.confirmTool("allow")
                }

                Button {
                    id: confirmAllways
                    Layout.fillWidth: true
                    text: "Всегда"
                    palette.buttonText: palette.black
                    visible: !confirmDangerNote.visible
                    background: Rectangle {
                        color: palette.green
                        radius: 8
                        implicitHeight: 42
                    }
                    onClicked: root.confirmTool("never")
                }
            }
        }
    }
}