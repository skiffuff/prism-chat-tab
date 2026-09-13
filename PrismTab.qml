import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    implicitWidth: 840
    implicitHeight: 520

    // Brand palette (follows the active AI provider)
    property color gBlue: GeminiChat.providerPrimary
    property color gViolet: GeminiChat.providerSecondary
    property color gRed: GeminiChat.providerTertiary
    readonly property color cardGreen: "#4FA267"

    // pending run_bash confirmation surfaced by the daemon
    property string pendingToolCallId: ""
    property bool confirmOpen: false
    property string confirmCommand: ""
    property bool confirmDangerous: false

    readonly property string providerLabel: GeminiChat.providerName
    readonly property string providerShape: GeminiChat.providerInfo?.logo ?? "sparkle"
    readonly property bool isClaude: GeminiChat.providerInfo?.style === "claude"

    property bool settingsMode: false

    property bool histOpen: false
    property string ctxSessionId: ""

    // When the provider switches, snap every logo/text shimmer to the new
    // palette quickly.
    Connections {
        target: GeminiChat

        function onCurrentProviderChanged() {
            // Update colors immediately
            headerLogo.shimmerColor = GeminiChat.providerPrimary;
            bigSparkle.spinColor = GeminiChat.providerPrimary;
            claudeSparkle.spinColor = GeminiChat.providerPrimary;
            greetFill.c0 = GeminiChat.providerPrimary;
            greetFill.c1 = GeminiChat.providerSecondary;
            greetFill.c2 = GeminiChat.providerTertiary;

            // Restart animations
            headerLogoAnim.restart();
            bigSparkleAnim.restart();
            claudeSparkleAnim.restart();
            greetGradAnim.restart();
        }
    }

    // Rotating brand greetings (like gemini.google.com)
    readonly property var greetings: [
        qsTr("Hi, I'm %1").arg(providerLabel),
        qsTr("Welcome back, I'm %1").arg(providerLabel),
        qsTr("Good to see you, I'm %1").arg(providerLabel),
        qsTr("I'm here, I'm %1").arg(providerLabel),
        qsTr("What shall we do, I'm %1").arg(providerLabel)
    ]

    property int greetIndex: 0

    function pickGreeting() {
        if (root.greetings.length === 1) {
            root.greetIndex = 0;
            return;
        }
        let next = root.greetIndex;
        while (next === root.greetIndex)
            next = Math.floor(Math.random() * root.greetings.length);
        root.greetIndex = next;
    }

    function mixColour(a: color, b: color, t: real): color {
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t
        );
    }

    Component.onCompleted: root.pickGreeting()

    SequentialAnimation {
        id: greetFade

        NumberAnimation { target: greetLabel; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
        ScriptAction { script: root.pickGreeting() }
        NumberAnimation { target: greetLabel; property: "opacity"; to: 1; duration: 200; easing.type: Easing.InQuad }
    }

    Connections {
        target: GeminiChat

        function onChatReset() {
            greetFade.restart();
        }

        function onToolConfirmRequested(info) {
            if (!info)
                return;
            root.pendingToolCallId = info.tool_call_id || "";
            root.confirmCommand = info.command || "";
            root.confirmDangerous = !!info.dangerous;
            root.confirmOpen = true;
        }
    }

    // Send the user's decision for a pending run_bash call to /tool/confirm.
    function confirmTool(decision) {
        const id = root.pendingToolCallId;
        root.pendingToolCallId = "";
        root.confirmOpen = false;
        if (id !== "")
            GeminiChat.confirmTool(id, decision);
    }

    // ── Transparent backdrop (same as Gemini) ─────────────────
    Rectangle {
        id: claudeBg

        anchors.fill: parent
        z: -10
        visible: root.isClaude
        color: "transparent"
    }

    // ── Context menu (rename / delete) ──────────────────────────
    Rectangle {
        id: ctxMenu

        visible: false
        z: 60
        width: 170
        height: ctxCol.implicitHeight + 12
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHighest

        ColumnLayout {
            id: ctxCol

            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 2

            // Rename
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: ctxRen.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "edit"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Rename")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }

                MouseArea {
                    id: ctxRen

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        histPanel.renameId = root.ctxSessionId;
                        ctxMenu.visible = false;
                    }
                }
            }

            // Delete
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: ctxDel.containsMouse ? "#f38ba8" : "transparent"

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "delete"
                        fontStyle: Tokens.font.icon.small
                        color: ctxDel.containsMouse ? "#1b1c1d" : "#f38ba8"
                    }

                    StyledText {
                        text: qsTr("Delete")
                        font: Tokens.font.body.small
                        color: ctxDel.containsMouse ? "#1b1c1d" : "#f38ba8"
                    }
                }

                MouseArea {
                    id: ctxDel

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        GeminiChat.deleteSession(root.ctxSessionId);
                        ctxMenu.visible = false;
                    }
                }
            }
        }
    }

    // Close ctx menu on outside click
    MouseArea {
        anchors.fill: parent
        z: 55
        visible: ctxMenu.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ctxMenu.visible = false
    }

    // ── Scrim behind drawer ─────────────────────────────────────
    Rectangle {
        id: drawerScrim

        anchors.fill: parent
        z: 40
        visible: root.histOpen
        color: Qt.rgba(0, 0, 0, 0.45)

        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.histOpen = false
        }
    }

    // ── History drawer (gemini.google.com style overlay) ────────
    StyledRect {
        id: histPanel

        property string renameId: ""

        z: 50
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.histOpen ? 272 : 0
        clip: true
        radius: 0
        color: Colours.palette.m3surfaceContainerHigh

        Behavior on width {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutQuint
            }
        }

        ColumnLayout {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.medium
            width: parent.width - Tokens.padding.medium * 2
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                GeminiLogo {
                    implicitWidth: 20
                    implicitHeight: 20
                    shape: root.providerShape
                    color: GeminiChat.providerPrimary
                }

                StyledText {
                    text: GeminiChat.providerName
                    font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledRect {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Tokens.rounding.full
                    color: collapseHover.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "menu_open"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    MouseArea {
                        id: collapseHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.histOpen = false
                    }
                }
            }

            StyledRect {
                id: newChatBtn

                Layout.fillWidth: true
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: newChatHover.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.palette.m3secondaryContainer

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "add"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSecondaryContainer
                    }

                    StyledText {
                        text: qsTr("New chat")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSecondaryContainer
                    }
                }

                MouseArea {
                    id: newChatHover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GeminiChat.newChat()
                }
            }

            StyledText {
                text: qsTr("Recent")
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }

            ListView {
                id: sessionsView

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: GeminiChat.sessionsList
                boundsBehavior: Flickable.StopAtBounds

                // Visible scroll indicator: with many sessions the list was
                // silently clipped at the bottom with no hint that more
                // history exists below the fold ("doesn't fit").
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: Colours.palette.m3outline
                        opacity: parent.active ? 0.7 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                delegate: StyledRect {
                    id: sessDelegate

                    required property int index
                    required property var modelData

                    readonly property bool isActive: modelData.id === GeminiChat.activeSessionId

                    width: sessionsView.width
                    implicitHeight: sessCol.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: isActive ? Colours.palette.m3secondaryContainer : (sessHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : "transparent")

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                            easing.type: Easing.InOutSine
                        }
                    }

                    ColumnLayout {
                        id: sessCol

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: 2

                        StyledText {
                            opacity: histPanel.renameId === sessDelegate.modelData.id ? 0 : 1
                            text: sessDelegate.modelData.title
                            font: Tokens.font.body.medium
                            color: sessDelegate.isActive ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            Layout.maximumWidth: sessDelegate.width - Tokens.padding.large * 2 - 50
                        }
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.padding.medium
                        anchors.verticalCenter: parent.verticalCenter
                        visible: histPanel.renameId !== sessDelegate.modelData.id
                        text: sessDelegate.modelData.updated > 0 ? Qt.formatDateTime(new Date(sessDelegate.modelData.updated * 1000), "d MMM") : ""
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }

                    // Inline rename field
                    Loader {
                        id: renameLoader

                        active: histPanel.renameId === sessDelegate.modelData.id
                        sourceComponent: Component {
                            TextInput {
                                id: renameInput

                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.medium
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurface
                                clip: true
                                activeFocusOnTab: true

                                Component.onCompleted: {
                                    text = sessDelegate.modelData.title;
                                    selectAll();
                                    forceActiveFocus();
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        const t = text.trim();
                                        if (t)
                                            GeminiChat.renameSession(sessDelegate.modelData.id, t);
                                        histPanel.renameId = "";
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        histPanel.renameId = "";
                                        event.accepted = true;
                                    }
                                }

                                onActiveFocusChanged: if (!activeFocus)
                                    histPanel.renameId = ""
                            }
                        }
                    }

                    HoverHandler {
                        id: sessHover
                    }

                    MouseArea {
                        id: sessClick

                        anchors.fill: parent
                        enabled: histPanel.renameId !== sessDelegate.modelData.id
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                ctxSessionId = sessDelegate.modelData.id;
                                const pos = mapToItem(histPanel, mouse.x, mouse.y);
                                ctxMenu.x = Math.max(4, Math.min(pos.x, histPanel.width - ctxMenu.width - 8));
                                ctxMenu.y = Math.min(pos.y + 4, histPanel.height - ctxMenu.height - 8);
                                ctxMenu.visible = true;
                            } else if (histPanel.renameId !== sessDelegate.modelData.id) {
                                GeminiChat.selectSession(sessDelegate.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Main column ─────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // ── Top bar ─────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Hamburger -> opens history drawer
            StyledRect {
                id: hamburgerBtn

                implicitWidth: 34
                implicitHeight: 34
                radius: Tokens.rounding.full
                color: hamburgHover.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "menu"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }

                MouseArea {
                    id: hamburgHover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        GeminiChat.loadSessions();
                        root.histOpen = !root.histOpen;
                    }
                }
            }

            GeminiLogo {
                id: headerLogo

                implicitWidth: 22
                implicitHeight: 22
                Layout.alignment: Qt.AlignVCenter
                shape: root.providerShape

                property color shimmerColor: GeminiChat.providerPrimary
                readonly property color neutralColor: Colours.palette.m3onSurfaceVariant

                color: logoHover.hovered ? shimmerColor : neutralColor
                tint: logoHover.hovered ? shimmerColor : neutralColor
                tintAmount: logoHover.hovered ? 1 : 0
                opacity: logoHover.hovered ? 1.0 : 0.95
                scale: logoHover.hovered ? 1.15 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutBack
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 250 // Faster
                        easing.type: Easing.InOutSine
                    }
                }

                Behavior on tint {
                    ColorAnimation {
                        duration: 250 // Faster
                        easing.type: Easing.InOutSine
                    }
                }

                SequentialAnimation {
                    id: headerLogoAnim
                    running: logoHover.hovered
                    loops: Animation.Infinite

                    ColorAnimation {
                        target: headerLogo
                        property: "shimmerColor"
                        to: GeminiChat.providerSecondary
                        duration: 600 // Faster shimmer
                        easing.type: Easing.InOutSine
                    }
                    ColorAnimation {
                        target: headerLogo
                        property: "shimmerColor"
                        to: GeminiChat.providerTertiary
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                    ColorAnimation {
                        target: headerLogo
                        property: "shimmerColor"
                        to: GeminiChat.providerPrimary
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                }

                HoverHandler {
                    id: logoHover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GeminiChat.newChat()
                }
            }

            // Provider selector chip
            StyledRect {
                id: providerChip

                implicitWidth: providerRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: providerPanel.visible ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                Row {
                    id: providerRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    GeminiLogo {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 16
                        implicitHeight: 16
                        shape: root.providerShape
                        color: GeminiChat.providerPrimary
                    }

                    StyledText {
                        text: root.providerLabel
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MaterialIcon {
                        text: providerPanel.visible ? "arrow_drop_up" : "arrow_drop_down"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (providerPanel.visible) {
                            providerPanel.visible = false;
                        } else {
                            modelsPanel.visible = false;
                            quotaPanel.visible = false;
                            providerPanel.visible = true;
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Live watch indicator / stop button
            StyledRect {
                id: watchChip

                visible: GeminiChat.watchActive
                implicitWidth: watchRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: watchArea.containsMouse ? "#eb6f92" : "#f38ba8"

                Row {
                    id: watchRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#1b1c1d"
                        opacity: 1

                        SequentialAnimation on opacity {
                            running: GeminiChat.watchActive
                            loops: Animation.Infinite

                            SmoothedAnimation {
                                to: 0.3
                                velocity: 1.2
                            }
                            SmoothedAnimation {
                                to: 1.0
                                velocity: 1.2
                            }
                        }
                    }

                    StyledText {
                        text: qsTr("Stop watching")
                        font: Tokens.font.body.small
                        color: "#1b1c1d"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: watchArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GeminiChat.stopWatch()
                }
            }

            // Status dot
            Rectangle {
                width: 8
                height: 8
                radius: 4
                Layout.alignment: Qt.AlignVCenter
                color: GeminiChat.isSending ? "#f9e2af" : (GeminiChat.statusText === "Offline" ? "#f38ba8" : "#a6e3a1")

                Behavior on color {
                    ColorAnimation {
                        duration: 400
                        easing.type: Easing.InOutSine
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GeminiChat.loadQuota()
                }
            }

            // Model selector chip
            StyledRect {
                id: modelChip

                implicitWidth: modelRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: modelsPanel.visible ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                Row {
                    id: modelRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: GeminiChat.currentModel
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MaterialIcon {
                        text: modelsPanel.visible ? "arrow_drop_up" : "arrow_drop_down"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (modelsPanel.visible) {
                            modelsPanel.visible = false;
                        } else {
                            GeminiChat.loadModels();
                            quotaPanel.visible = false;
                            providerPanel.visible = false;
                            modelsPanel.visible = true;
                        }
                    }
                }
            }

            // Quota icon
            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: quotaPanel.visible ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "data_usage"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (quotaPanel.visible) {
                            quotaPanel.visible = false;
                        } else {
                            GeminiChat.loadQuota();
                            modelsPanel.visible = false;
                            providerPanel.visible = false;
                            quotaPanel.visible = true;
                        }
                    }
                }
            }

            // Clear chat
            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: clearArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer

                MaterialIcon {
                    id: clearIcon

                    anchors.centerIn: parent
                    text: "refresh"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                    rotation: 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 600
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: clearArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        clearIcon.rotation += 360;
                        GeminiChat.clearHistory();
                    }
                }
            }

            // Settings
            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: settingsBtnArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : (root.settingsMode ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "settings"
                    fontStyle: Tokens.font.icon.small
                    color: root.settingsMode ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }

                MouseArea {
                    id: settingsBtnArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.settingsMode = !root.settingsMode;
                        modelsPanel.visible = false;
                        quotaPanel.visible = false;
                        providerPanel.visible = false;
                        if (root.settingsMode) GeminiChat.loadSettings();
                    }
                }
            }
        }

        // ── Provider panel ──────────────────────────────────────
        StyledRect {
            id: providerPanel

            visible: false
            Layout.fillWidth: true
            Layout.maximumHeight: 220
            implicitHeight: Math.min(providerList.contentHeight + Tokens.padding.medium * 2, 220)
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHigh
            clip: true

            ListView {
                id: providerList

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                clip: true
                spacing: 2
                model: GeminiChat.providersList

                delegate: StyledRect {
                    required property var modelData
                    readonly property bool provActive: GeminiChat.currentProvider === modelData.id

                    width: providerList.width
                    implicitHeight: 40
                    radius: Tokens.rounding.small
                    color: provActive ? Qt.alpha(root.gBlue, 0.16) : (provHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : "transparent")

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        GeminiLogo {
                            implicitWidth: 20
                            implicitHeight: 20
                            shape: modelData.logo
                            color: modelData.primary
                        }

                        StyledText {
                            text: modelData.name
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                            color: provActive ? root.gBlue : Colours.palette.m3onSurface
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: modelData.has_key ? "#a6e3a1" : "#f9e2af"
                        }

                        StyledText {
                            text: modelData.has_key ? qsTr("key set") : qsTr("no key")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: provHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!provActive)
                                GeminiChat.selectProvider(modelData.id);
                            providerPanel.visible = false;
                        }
                    }
                }
            }
        }

        // ── Models panel ─────────────────────────────────────────
        StyledRect {
            id: modelsPanel

            visible: false
            Layout.fillWidth: true
            Layout.maximumHeight: 200
            implicitHeight: Math.min(modelsList.contentHeight + Tokens.padding.medium * 2, 200)
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHigh
            clip: true

            ListView {
                id: modelsList

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                clip: true
                spacing: 2
                model: GeminiChat.modelsList

                delegate: StyledRect {
                    id: modelDelegate

                    required property var modelData

                    readonly property string quotaStatus: {
                        const byModel = GeminiChat.quotaData?.by_model ?? {};
                        const st = byModel[modelDelegate.modelData.id];
                        return typeof st === "object" && st !== null ? (st.status ?? "ok") : "ok";
                    }

                    width: modelsList.width
                    implicitHeight: 34
                    radius: Tokens.rounding.small
                    color: delegateHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            Layout.alignment: Qt.AlignVCenter
                            color: modelDelegate.quotaStatus === "exhausted"
                                ? "#f38ba8"
                                : modelDelegate.quotaStatus === "warning"
                                    ? "#f9e2af"
                                    : "#a6e3a1"
                        }

                        MaterialIcon {
                            visible: modelDelegate.modelData.id === GeminiChat.currentModel
                            text: "check"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            text: modelDelegate.modelData.label
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            Layout.maximumWidth: modelsList.width - Tokens.padding.large * 2 - 130
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: modelDelegate.modelData.id
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 110
                        }
                    }

                    HoverHandler {
                        id: delegateHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            GeminiChat.selectModel(modelDelegate.modelData.id);
                            modelsPanel.visible = false;
                        }
                    }
                }
            }
        }

        // ── Quota panel ──────────────────────────────────────────
        StyledRect {
            id: quotaPanel

            visible: false
            Layout.fillWidth: true
            implicitHeight: quotaContent.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: quotaContent

                anchors.centerIn: parent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                // ── Overall API status ────────────────────────
                RowLayout {
                    id: quotaStatusRow

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    readonly property bool noKey: GeminiChat.providerInfo?.has_key === false

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        Layout.alignment: Qt.AlignVCenter
                        color: quotaStatusRow.noKey
                            ? "#94a3b8"
                            : GeminiChat.quotaData?.quota_exceeded ? "#f38ba8" : "#a6e3a1"
                    }

                    StyledText {
                        text: quotaStatusRow.noKey
                            ? "API ключ " + GeminiChat.providerName + " не найден"
                            : GeminiChat.quotaData?.quota_exceeded ? qsTr("API quota exhausted") : qsTr("API quota available")
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        color: quotaStatusRow.noKey
                            ? "#94a3b8"
                            : GeminiChat.quotaData?.quota_exceeded ? "#f38ba8" : "#a6e3a1"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: !quotaStatusRow.noKey
                        text: GeminiChat.quotaData
                            ? GeminiChat.quotaData.requests + " запр. • вх. " + GeminiChat.quotaData.prompt_tokens + " • вых. " + GeminiChat.quotaData.output_tokens
                            : qsTr("Loading...")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        Layout.alignment: Qt.AlignRight
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.4
                }

                // ── Per-model status ──────────────────────────
                StyledText {
                    visible: !quotaStatusRow.noKey
                    text: qsTr("Model limits")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }

                Repeater {
                    visible: !quotaStatusRow.noKey
                    model: {
                        const byModel = GeminiChat.quotaData?.by_model ?? {};
                        return Object.keys(byModel);
                    }

                    delegate: RowLayout {
                        required property string modelData
                        spacing: Tokens.spacing.medium

                        StyledText {
                            text: "• " + modelData
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            Layout.maximumWidth: 180
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            readonly property var stats: GeminiChat.quotaData?.by_model?.[modelData]
                            text: stats
                                ? (typeof stats === "number" ? stats + " запр." : stats.requests + " запр. • вх. " + stats.prompt_tokens + " • вых. " + stats.output_tokens)
                                : "—"
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            Layout.maximumWidth: 220
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Colours.palette.m3outlineVariant
                    opacity: 0.4
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Updates every 30 seconds")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: 0.8
                }
            }
        }

        // ── Body: empty state or conversation ────────────────────
        Item {
            id: bodyArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: !root.settingsMode

            // Empty state (gemini.google.com welcome)
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.padding.large * 2, 680)
                spacing: root.isClaude ? Tokens.spacing.medium : Tokens.spacing.large

                visible: GeminiChat.messages.count === 0

                // Big gradient sparkle (Gemini style)
                Item {
                    id: bigSparkleHero

                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    visible: !root.isClaude

                    GeminiLogo {
                        id: bigSparkle

                        anchors.centerIn: parent
                        implicitWidth: 64
                        implicitHeight: 64
                        shape: root.providerShape

                        property color spinColor: GeminiChat.providerPrimary

                        color: spinColor
                        tint: spinColor
                        tintAmount: 1

                        SequentialAnimation {
                            id: bigSparkleAnim
                            running: true
                            loops: Animation.Infinite

                            ColorAnimation {
                                target: bigSparkle
                                property: "spinColor"
                                to: GeminiChat.providerSecondary
                                duration: 3200
                                easing.type: Easing.InOutSine
                            }
                            ColorAnimation {
                                target: bigSparkle
                                property: "spinColor"
                                to: GeminiChat.providerTertiary
                                duration: 3200
                                easing.type: Easing.InOutSine
                            }
                            ColorAnimation {
                                target: bigSparkle
                                property: "spinColor"
                                to: GeminiChat.providerPrimary
                                duration: 3200
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }

                // Claude style hero: Gemini-inspired sparkle
                Item {
                    id: claudeHero

                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    visible: root.isClaude

                    // Claude gradient sparkle
                    GeminiLogo {
                        id: claudeSparkle

                        anchors.centerIn: parent
                        implicitWidth: 64
                        implicitHeight: 64
                        shape: "claude"  // Back to Claude shape, but animated
                        property color spinColor: GeminiChat.providerPrimary

                        color: spinColor
                        tint: spinColor
                        tintAmount: 1

                        SequentialAnimation {
                            id: claudeSparkleAnim
                            running: true
                            loops: Animation.Infinite

                            ColorAnimation { target: claudeSparkle; property: "spinColor"; to: GeminiChat.providerSecondary; duration: 3200; easing.type: Easing.InOutSine }
                            ColorAnimation { target: claudeSparkle; property: "spinColor"; to: GeminiChat.providerTertiary; duration: 3200; easing.type: Easing.InOutSine }
                            ColorAnimation { target: claudeSparkle; property: "spinColor"; to: GeminiChat.providerPrimary; duration: 3200; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // Brand greeting (single line, provider gradient)
                Item {
                    id: greetLabel

                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: greetMask.implicitWidth
                    implicitHeight: greetMask.implicitHeight
                    opacity: 1

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutQuad
                        }
                    }

                    // Provider-gradient text (animated "переливание"), masked to the greeting glyphs
                    Rectangle {
                        id: greetFill

                        anchors.fill: parent

                        property color c0: GeminiChat.providerPrimary
                        property color c1: GeminiChat.providerSecondary
                        property color c2: GeminiChat.providerTertiary

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: greetFill.c0
                            }
                            GradientStop {
                                position: 0.5
                                color: greetFill.c1
                            }
                            GradientStop {
                                position: 1
                                color: greetFill.c2
                            }
                        }

                        layer.enabled: true
                        layer.effect: Mask {
                            maskSource: greetMask
                        }

                        SequentialAnimation {
                            id: greetGradAnim
                            running: true
                            loops: Animation.Infinite

                            ParallelAnimation {
                                ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                            }
                            ParallelAnimation {
                                ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                            }
                            ParallelAnimation {
                                ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                                ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    StyledText {
                        id: greetMask

                        visible: false
                        width: implicitWidth
                        height: implicitHeight
                        text: root.greetings[root.greetIndex]
                        font: Tokens.font.body.builders.large.size(root.isClaude ? 26 : 40).weight(Font.Medium).build()
                        color: "white"
                        renderType: Text.QtRendering
                        layer.enabled: true
                        layer.smooth: false
                    }
                }

                StyledText {
                    text: root.isClaude ? qsTr("How can I help you today?") : qsTr("How can I help?")
                    font: Tokens.font.body.builders.large.size(root.isClaude ? 13 : 16).build()
                    color: Colours.palette.m3onSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // Conversation
            ListView {
                id: chatListView

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium
                clip: true
                visible: GeminiChat.messages.count > 0
                model: GeminiChat.messages

                onCountChanged: positionViewAtEnd()

                delegate: Item {
                    id: msgRoot

                    width: chatListView.width
                    implicitHeight: msgColumn.implicitHeight
                    opacity: 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Component.onCompleted: opacity = 1

                    required property int index
                    required property string sender
                    required property string text
                    required property var images

                    readonly property bool isUser: sender === "user"

                    ColumnLayout {
                        id: msgColumn

                        width: parent.width
                        spacing: Tokens.spacing.small

                        // Assistant sparkle header
                        RowLayout {
                            visible: !msgRoot.isUser
                            spacing: Tokens.spacing.small

                            GeminiLogo {
                                implicitWidth: 18
                                implicitHeight: 18
                                shape: root.providerShape
                                color: msgRoot.index % 3 === 0 ? GeminiChat.providerPrimary : (msgRoot.index % 3 === 1 ? GeminiChat.providerSecondary : GeminiChat.providerTertiary)
                            }

                            StyledText {
                                text: root.providerLabel
                                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        // User bubble (Google blue)
                        StyledRect {
                            id: userBubble

                            visible: msgRoot.isUser
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: chatListView.width * 0.75
                            implicitWidth: userBubbleCol.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: userBubbleCol.implicitHeight + Tokens.padding.medium * 2
                            radius: 20
                            color: userHover.hovered ? Qt.darker(GeminiChat.providerBubble, 1.12) : GeminiChat.providerBubble

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }

                            ColumnLayout {
                                id: userBubbleCol

                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                Repeater {
                                    model: msgRoot.images || []

                                    delegate: Image {
                                        required property var modelData
                                        Layout.preferredWidth: Math.min(220, chatListView.width * 0.6)
                                        Layout.preferredHeight: 140
                                        fillMode: Image.PreserveAspectCrop
                                        source: "data:" + (modelData.mime || "image/png") + ";base64," + (modelData.data || "")
                                    }
                                }

                                StyledText {
                                    id: userText

                                    Layout.maximumWidth: chatListView.width * 0.7 - Tokens.padding.large * 2
                                    wrapMode: Text.Wrap
                                    text: msgRoot.text
                                    font: Tokens.font.body.medium
                                    color: "#ffffff"
                                }
                            }

                            HoverHandler {
                                id: userHover
                            }
                        }

                        // Assistant plain text
                        StyledText {
                            visible: !msgRoot.isUser
                            Layout.fillWidth: true
                            Layout.maximumWidth: chatListView.width * 0.85
                            wrapMode: Text.Wrap
                            text: msgRoot.text
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                        }
                    }
                }
            }
        }

        // ── Input pill (gemini.google.com style) ─────────────────
        StyledRect {
            id: inputPill

            Layout.fillWidth: true
            visible: !root.settingsMode && !root.isClaude
            implicitHeight: attachRow.visible ? 50 + 62 : 50
            radius: 25
            color: Colours.tPalette.m3surfaceContainerHigh

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuint
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: Tokens.spacing.small

                // Attachments strip inside the pill
                RowLayout {
                    id: attachRow

                    visible: GeminiChat.attachments.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: GeminiChat.attachments

                        delegate: StyledRect {
                            id: attChip

                            required property int index
                            required property var modelData

                            readonly property bool isImage: modelData.mime?.startsWith("image/") ?? false

                            implicitWidth: 56
                            implicitHeight: 56
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainer
                            scale: 1.0
                            opacity: 1.0

                            Component.onCompleted: {
                                scale = 0;
                                opacity = 0;
                                scale = 1.0;
                                opacity = 1.0;
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
                                visible: attChip.isImage
                                source: "data:" + attChip.modelData.mime + ";base64," + attChip.modelData.data
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            MaterialIcon {
                                visible: !attChip.isImage
                                anchors.centerIn: parent
                                text: attChip.modelData.mime?.startsWith("video/") ? "movie" : "description"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: -4
                                width: 18
                                height: 18
                                radius: 9
                                color: removeHover.hovered ? "#f38ba8" : Colours.palette.m3surfaceContainerHighest

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "close"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3onSurface
                                }

                                MouseArea {
                                    id: removeHover

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: GeminiChat.removeAttachment(attChip.index)
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.small

                    // "+" attach
                    StyledRect {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Tokens.rounding.full
                        color: plusArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "add"
                            fontStyle: Tokens.font.icon.medium
                            color: plusArea.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: plusArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GeminiChat.pickFile()
                        }
                    }

                    TextInput {
                        id: inputField

                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.small
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        selectedTextColor: Colours.palette.m3onPrimary
                        selectionColor: Colours.palette.m3primary
                        clip: true
                        focus: true
                        text: GeminiChat.draft

                        onTextChanged: {
                            if (GeminiChat.draft !== text)
                                GeminiChat.draft = text
                        }

                        Text {
                            enabled: false
                            text: qsTr("Ask %1").arg(root.providerLabel)
                            color: Colours.palette.m3onSurfaceVariant
                            font: inputField.font
                            visible: !inputField.text && !inputField.activeFocus
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                        }

                        Keys.onPressed: event => {
                            if (event.matches(StandardKey.Paste)) {
                                event.accepted = true;
                                GeminiChat.pasteFromClipboard(() => inputField.paste());
                                return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                console.log("[SENDDBG] Enter msg='" + inputField.text + "' isSending=" + GeminiChat.isSending);
                                GeminiChat.sendMessage(inputField.text);
                                return;
                            }
                            event.accepted = false;
                        }
                    }

                    // Send
                    StyledRect {
                        id: sendBtn

                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Tokens.rounding.full
                        scale: 1.0
                        color: {
                            const has = inputField.text.trim().length > 0 || GeminiChat.attachments.length > 0;
                            if (!has)
                                return Colours.tPalette.m3surfaceContainer;
                            return sendArea.containsMouse ? Qt.darker(GeminiChat.providerBubble, 1.1) : GeminiChat.providerBubble;
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutBack
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "arrow_upward"
                            fontStyle: Tokens.font.icon.medium
                            color: (inputField.text.trim().length > 0 || GeminiChat.attachments.length > 0) ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        SequentialAnimation {
                            id: sendBounce
                            NumberAnimation { target: sendBtn; property: "scale"; to: 0.75; duration: 80; easing.type: Easing.InQuad }
                            NumberAnimation { target: sendBtn; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                        }

                        MouseArea {
                            id: sendArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                console.log("[SENDDBG] Btn msg='" + inputField.text + "' isSending=" + GeminiChat.isSending);
                                sendBounce.restart();
                                GeminiChat.sendMessage(inputField.text);
                            }
                        }
                    }
                }
            }
        }

        // Claude style: signature rounded input with bottom-right send
        StyledRect {
            id: claudeInputBox

            Layout.fillWidth: true
            visible: !root.settingsMode && root.isClaude
            implicitHeight: (GeminiChat.attachments.length > 0 ? 34 : 0) + 82
            radius: 20
            color: Colours.light
                ? root.mixColour(Colours.palette.m3surface, "#F7EFE5", 0.85)
                : root.mixColour(Colours.palette.m3surface, "#4A3A2C", 0.45)
            border.width: claudeField.activeFocus ? 1 : 0
            border.color: Qt.alpha(GeminiChat.providerPrimary, 0.55)

            Behavior on border.width {
                NumberAnimation {
                    duration: 150
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 400
                    easing.type: Easing.InOutSine
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.small
                anchors.topMargin: Tokens.padding.small
                anchors.bottomMargin: 5
                spacing: 4

                RowLayout {
                    visible: GeminiChat.attachments.length > 0
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: GeminiChat.attachments

                        delegate: StyledRect {
                            required property int index
                            required property var modelData

                            implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: 30
                            radius: Tokens.rounding.full
                            color: Colours.tPalette.m3surfaceContainer

                            Row {
                                id: chipRow

                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.mime?.startsWith("image/") ? "image" : "attach_file"
                                    fontStyle: Tokens.font.icon.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                StyledText {
                                    text: {
                                        const n = modelData.name ?? "";
                                        return n.length > 14 ? n.slice(0, 14) + "…" : n;
                                    }
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MaterialIcon {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: -3
                                text: "close"
                                fontStyle: Tokens.font.icon.small
                                color: Colours.palette.m3onSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GeminiChat.removeAttachment(index)
                            }
                        }
                    }
                }

                RowLayout {
                    id: claudeFieldRow

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: claudeField

                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        selectedTextColor: Colours.palette.m3onPrimary
                        selectionColor: Colours.palette.m3primary
                        clip: true
                        text: GeminiChat.draft

                        onTextChanged: {
                            if (GeminiChat.draft !== text)
                                GeminiChat.draft = text
                        }

                        Text {
                            enabled: false
                            text: qsTr("Ask %1…").arg(root.providerLabel)
                            color: Colours.palette.m3onSurfaceVariant
                            font: claudeField.font
                            visible: !claudeField.text && !claudeField.activeFocus
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                        }

                        Keys.onPressed: event => {
                            if (event.matches(StandardKey.Paste)) {
                                event.accepted = true;
                                GeminiChat.pasteFromClipboard(() => claudeField.paste());
                                return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                GeminiChat.sendMessage(claudeField.text);
                                return;
                            }
                            event.accepted = false;
                        }
                    }
                }

                RowLayout {
                    id: attachRowClaude

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Tokens.rounding.full
                        color: claudePlusArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "attach_file"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: claudePlusArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GeminiChat.pickFile()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Claude-style send circle
                    StyledRect {
                        id: claudeSendBtn

                        implicitWidth: 30
                        implicitHeight: 30
                        radius: Tokens.rounding.full
                        scale: 1.0
                        color: {
                            const has = claudeField.text.trim().length > 0 || GeminiChat.attachments.length > 0;
                            if (!has)
                                return Colours.tPalette.m3surfaceContainer;
                            return claudeSendArea.containsMouse ? Qt.darker(GeminiChat.providerBubble, 1.1) : GeminiChat.providerBubble;
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 250
                                easing.type: Easing.OutBack
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "arrow_upward"
                            fontStyle: Tokens.font.icon.medium
                            color: (claudeField.text.trim().length > 0 || GeminiChat.attachments.length > 0) ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        }

                        SequentialAnimation {
                            id: claudeSendBounce

                            NumberAnimation {
                                target: claudeSendBtn
                                property: "scale"
                                to: 0.75
                                duration: 80
                                easing.type: Easing.InQuad
                            }
                            NumberAnimation {
                                target: claudeSendBtn
                                property: "scale"
                                to: 1.0
                                duration: 250
                                easing.type: Easing.OutBack
                            }
                        }

                        MouseArea {
                            id: claudeSendArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                claudeSendBounce.restart();
                                GeminiChat.sendMessage(claudeField.text);
                            }
                        }
                    }
                }
            }
        }
    }
}
