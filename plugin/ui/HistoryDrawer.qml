import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Slide-in list of chat sessions (gemini.google.com style overlay) with the
// scrim behind it and the rename / delete context menu.
Item {
    id: root

    required property var tab

    // Session being renamed inline, "" when none
    property string renameId: ""
    // Session the context menu was opened for
    property string ctxSessionId: ""

    anchors.fill: parent
    z: 40

    // ── Scrim ───────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.tab.histOpen
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            onClicked: root.tab.histOpen = false
        }
    }

    // ── Drawer ──────────────────────────────────────────────────
    StyledRect {
        id: histPanel

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.tab.histOpen ? 272 : 0
        // Shapes inside ignore the clip once the width hits 0, so hide the
        // panel outright when it is fully closed.
        visible: width > 0
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
                    shape: root.tab.providerShape
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
                        onClicked: root.tab.histOpen = false
                    }
                }
            }

            StyledRect {
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

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: Colours.palette.m3outline
                        opacity: parent.active ? 0.7 : 0.3

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }
                }

                delegate: StyledRect {
                    id: sessDelegate

                    required property int index
                    required property var modelData

                    readonly property bool isActive: modelData.id === GeminiChat.activeSessionId
                    readonly property bool renaming: root.renameId === modelData.id

                    width: sessionsView.width
                    implicitHeight: 40
                    radius: Tokens.rounding.medium
                    color: isActive ? Colours.palette.m3secondaryContainer : (sessHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : "transparent")

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                            easing.type: Easing.InOutSine
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: dateLabel.left
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.spacing.small
                        visible: !sessDelegate.renaming
                        text: sessDelegate.modelData.title
                        font: Tokens.font.body.medium
                        color: sessDelegate.isActive ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: dateLabel

                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.padding.medium
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !sessDelegate.renaming
                        text: sessDelegate.modelData.updated > 0 ? Qt.formatDateTime(new Date(sessDelegate.modelData.updated * 1000), "d MMM") : ""
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }

                    // Inline rename field
                    Loader {
                        active: sessDelegate.renaming
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium

                        sourceComponent: TextInput {
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
                                    root.renameId = "";
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    root.renameId = "";
                                    event.accepted = true;
                                }
                            }

                            onActiveFocusChanged: {
                                if (!activeFocus)
                                    root.renameId = "";
                            }
                        }
                    }

                    HoverHandler {
                        id: sessHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !sessDelegate.renaming
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.ctxSessionId = sessDelegate.modelData.id;
                                const pos = mapToItem(histPanel, mouse.x, mouse.y);
                                ctxMenu.x = Math.max(4, Math.min(pos.x, histPanel.width - ctxMenu.width - 8));
                                ctxMenu.y = Math.min(pos.y + 4, histPanel.height - ctxMenu.height - 8);
                                ctxMenu.visible = true;
                            } else {
                                GeminiChat.selectSession(sessDelegate.modelData.id);
                            }
                        }
                    }
                }
            }
        }

        // ── Context menu (rename / delete) ──────────────────────
        Rectangle {
            id: ctxMenu

            visible: false
            z: 10
            width: 170
            height: ctxCol.implicitHeight + 12
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHighest

            ColumnLayout {
                id: ctxCol

                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2

                CtxItem {
                    icon: "edit"
                    label: qsTr("Rename")
                    onTriggered: {
                        root.renameId = root.ctxSessionId;
                        ctxMenu.visible = false;
                    }
                }

                CtxItem {
                    icon: "delete"
                    label: qsTr("Delete")
                    destructive: true
                    onTriggered: {
                        GeminiChat.deleteSession(root.ctxSessionId);
                        ctxMenu.visible = false;
                    }
                }
            }
        }

        // Close ctx menu on outside click
        MouseArea {
            anchors.fill: parent
            z: 5
            visible: ctxMenu.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: ctxMenu.visible = false
        }
    }

    component CtxItem: Rectangle {
        id: item

        required property string icon
        required property string label
        property bool destructive: false

        signal triggered()

        readonly property color accent: destructive ? "#f38ba8" : Colours.palette.m3onSurface

        Layout.fillWidth: true
        implicitHeight: 32
        radius: Tokens.rounding.small
        color: itemArea.containsMouse ? (destructive ? "#f38ba8" : Colours.tPalette.m3surfaceContainerHighest) : "transparent"

        RowLayout {
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: item.icon
                fontStyle: Tokens.font.icon.small
                color: itemArea.containsMouse && item.destructive ? "#1b1c1d" : (item.destructive ? item.accent : Colours.palette.m3onSurfaceVariant)
            }

            StyledText {
                text: item.label
                font: Tokens.font.body.small
                color: itemArea.containsMouse && item.destructive ? "#1b1c1d" : item.accent
            }
        }

        MouseArea {
            id: itemArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.triggered()
        }
    }
}
