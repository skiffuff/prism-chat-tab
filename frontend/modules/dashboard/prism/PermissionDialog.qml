import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// run_bash confirmation in the style of opencode's permission prompt: a
// monospace card with the request, the command as a pattern list, and a
// footer of Allow once / Allow always / Reject that also drives from the
// keyboard (←/→ or Tab to move, Enter to confirm, Esc to reject).
Item {
    id: root

    required property var tab

    readonly property color amber: "#F5A524"
    readonly property color danger: "#F38BA8"
    readonly property color dim: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.75)

    // "Allow always" would persist a dangerous command as an auto-approved
    // pattern, so it is not offered for those.
    readonly property var actions: [
        { label: qsTr("Allow once"), decision: "allow", enabled: true },
        { label: qsTr("Allow always"), decision: "never", enabled: !root.tab.confirmDangerous && root.tab.confirmPersistable },
        { label: qsTr("Reject"), decision: "deny", enabled: true }
    ]

    property int selected: 0

    function move(step: int): void {
        let i = selected;
        for (let n = 0; n < actions.length; n++) {
            i = (i + step + actions.length) % actions.length;
            if (actions[i].enabled)
                break;
        }
        selected = i;
    }

    function activate(): void {
        const a = actions[selected];
        if (a && a.enabled)
            root.tab.confirmTool(a.decision);
    }

    onVisibleChanged: {
        if (visible) {
            selected = root.tab.confirmDangerous ? 2 : 0;
            card.forceActiveFocus();
        }
    }

    // Scrim: swallows clicks while the decision is pending
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(root.width * 0.9, 720)
        height: body.implicitHeight + body.anchors.margins * 2 + footer.implicitHeight
        radius: 10
        color: Colours.light ? "#F3F3F3" : "#1C1C1C"
        border.width: 1
        border.color: Colours.light ? "#D8D8D8" : "#333333"
        clip: true
        focus: true

        readonly property color fg: Colours.light ? "#1E1E1E" : "#E6E6E6"

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                root.move(-1);
                break;
            case Qt.Key_Right:
            case Qt.Key_Tab:
                root.move(1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.activate();
                break;
            case Qt.Key_Escape:
                root.tab.confirmTool("deny");
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 6

            // ⚠ Permission required
            RowLayout {
                spacing: 8

                Text {
                    text: "⚠"
                    font: Tokens.font.mono.medium
                    color: root.tab.confirmDangerous ? root.danger : root.amber
                }

                Text {
                    text: qsTr("Permission required")
                    font: Tokens.font.mono.builders.medium.weight(Font.Bold).build()
                    color: card.fg
                }
            }

            //   ← Run shell command
            RowLayout {
                Layout.leftMargin: 18
                spacing: 8

                Text {
                    text: "←"
                    font: Tokens.font.mono.medium
                    color: root.dim
                }

                Text {
                    Layout.fillWidth: true
                    text: root.tab.confirmDangerous ? qsTr("Run shell command flagged as dangerous") : qsTr("Run shell command")
                    font: Tokens.font.mono.medium
                    color: root.dim
                    elide: Text.ElideRight
                }
            }

            Item {
                implicitHeight: 10
            }

            Text {
                text: qsTr("Command")
                font: Tokens.font.mono.medium
                color: root.dim
            }

            Item {
                implicitHeight: 6
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignTop
                    text: "-"
                    font: Tokens.font.mono.medium
                    color: card.fg
                }

                Text {
                    Layout.fillWidth: true
                    text: root.tab.confirmCommand
                    font: Tokens.font.mono.medium
                    color: card.fg
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 8
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                visible: root.tab.confirmDangerous || !root.tab.confirmPersistable
                Layout.topMargin: 6
                spacing: 8

                Text {
                    text: "!"
                    font: Tokens.font.mono.builders.medium.weight(Font.Bold).build()
                    color: root.tab.confirmDangerous ? root.danger : root.amber
                }

                Text {
                    Layout.fillWidth: true
                    text: root.tab.confirmDangerous
                        ? qsTr("This pattern is on the dangerous list; it cannot be allowed permanently.")
                        : qsTr("This command reaches the network; it can run once but cannot be allowed permanently.")
                    font: Tokens.font.mono.small
                    color: root.tab.confirmDangerous ? root.danger : root.amber
                    wrapMode: Text.Wrap
                }
            }

            Item {
                implicitHeight: 12
            }
        }

        // Footer: actions on the left, key hints on the right
        Rectangle {
            id: footer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitHeight: 44
            color: Colours.light ? "#E6E6E6" : "#262626"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 14
                spacing: 4

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: btn

                        required property int index
                        required property var modelData

                        readonly property bool current: root.selected === index

                        implicitWidth: btnLabel.implicitWidth + 16
                        implicitHeight: 26
                        radius: 2
                        color: current ? (root.tab.confirmDangerous && modelData.decision !== "deny" ? root.danger : root.amber) : "transparent"
                        opacity: modelData.enabled ? 1 : 0.35

                        Text {
                            id: btnLabel

                            anchors.centerIn: parent
                            text: btn.modelData.label
                            font: Tokens.font.mono.medium
                            color: btn.current ? "#1C1C1C" : root.dim
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: btn.modelData.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = btn.index
                            onClicked: {
                                root.selected = btn.index;
                                root.activate();
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Row {
                    // Key hints; dropped when the card is too narrow for them
                    visible: card.width >= 660
                    spacing: 14

                    Hint {
                        key: "⇄"
                        label: qsTr("select")
                        keyColour: Qt.alpha(card.fg, 0.8)
                        labelColour: root.dim
                    }

                    Hint {
                        key: "enter"
                        label: qsTr("confirm")
                        keyColour: Qt.alpha(card.fg, 0.8)
                        labelColour: root.dim
                    }

                    Hint {
                        key: "esc"
                        label: qsTr("reject")
                        keyColour: Qt.alpha(card.fg, 0.8)
                        labelColour: root.dim
                    }
                }
            }
        }
    }

    component Hint: Row {
        id: hint

        required property string key
        required property string label
        required property color keyColour
        required property color labelColour

        spacing: 5

        Text {
            text: hint.key
            font: Tokens.font.mono.builders.small.weight(Font.Bold).build()
            color: hint.keyColour
        }

        Text {
            text: hint.label
            font: Tokens.font.mono.small
            color: hint.labelColour
        }
    }
}
