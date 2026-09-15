import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// run_bash confirmation in the manner of opencode's permission prompt: a
// monospace body with the request and the command as a pattern list, then a
// footer of Allow once / Allow always / Reject. It sits directly on top of
// the composer, sharing its fill and radius, so the two read as one block,
// and the highlight takes the active provider's colour (red for commands
// on the dangerous list). Keyboard: ←/→ or Tab to move, Enter to confirm,
// Esc to reject.
Rectangle {
    id: root

    required property var tab

    readonly property color danger: "#F38BA8"
    readonly property color accent: root.tab.confirmDangerous ? root.danger : root.tab.gBlue
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color dim: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.85)
    // Text on the highlighted action: dark on light accents, white otherwise
    readonly property color onAccent: (accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114) > 0.55 ? "#1C1C1C" : "#FFFFFF"
    readonly property color footerFill: Colours.light ? Qt.darker(color, 1.05) : Qt.lighter(color, 1.22)

    // "Allow always" would persist a dangerous or network command as an
    // auto-approved pattern, so it is not offered for those.
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

    implicitHeight: body.anchors.topMargin + body.implicitHeight + footer.implicitHeight
    radius: Math.min(root.tab.composerRadius, 20)
    bottomLeftRadius: 0
    bottomRightRadius: 0
    color: root.tab.composerColour
    border.width: root.tab.boxedInput ? 1 : 0
    border.color: Qt.alpha(root.accent, 0.55)
    clip: true
    focus: true

    Behavior on color {
        ColorAnimation {
            duration: 300
        }
    }

    onVisibleChanged: {
        if (visible) {
            selected = root.tab.confirmDangerous ? 2 : 0;
            forceActiveFocus();
        } else if (root.tab.visible) {
            root.tab.focusComposer();
        }
    }

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

    // Keep clicks on the body from reaching whatever is underneath
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    ColumnLayout {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 16
        spacing: 6

        // ⚠ Permission required
        RowLayout {
            spacing: 8

            Text {
                text: "⚠"
                font: Tokens.font.mono.medium
                color: root.accent
            }

            Text {
                text: qsTr("Permission required")
                font: Tokens.font.mono.builders.medium.weight(Font.Bold).build()
                color: root.fg
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

        Text {
            Layout.topMargin: 10
            text: qsTr("Command")
            font: Tokens.font.mono.medium
            color: root.dim
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignTop
                text: "-"
                font: Tokens.font.mono.medium
                color: root.fg
            }

            Text {
                Layout.fillWidth: true
                text: root.tab.confirmCommand
                font: Tokens.font.mono.medium
                color: root.fg
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 6
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
                color: root.accent
            }

            Text {
                Layout.fillWidth: true
                text: root.tab.confirmDangerous
                    ? qsTr("This pattern is on the dangerous list; it cannot be allowed permanently.")
                    : qsTr("This command reaches the network; it can run once but cannot be allowed permanently.")
                font: Tokens.font.mono.small
                color: root.accent
                wrapMode: Text.Wrap
            }
        }

        Item {
            implicitHeight: 10
        }
    }

    // Footer: actions on the left, key hints on the right
    Rectangle {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.border.width
        anchors.rightMargin: root.border.width
        implicitHeight: 42
        color: root.footerFill

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
                    radius: 4
                    color: current ? root.accent : "transparent"
                    opacity: modelData.enabled ? 1 : 0.35

                    Text {
                        id: btnLabel

                        anchors.centerIn: parent
                        text: btn.modelData.label
                        font: Tokens.font.mono.medium
                        color: btn.current ? root.onAccent : root.dim
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
                // Key hints; dropped when the panel is too narrow for them
                visible: root.width >= 640
                spacing: 14

                Hint {
                    key: "⇄"
                    label: qsTr("select")
                    keyColour: Qt.alpha(root.fg, 0.8)
                    labelColour: root.dim
                }

                Hint {
                    key: "enter"
                    label: qsTr("confirm")
                    keyColour: Qt.alpha(root.fg, 0.8)
                    labelColour: root.dim
                }

                Hint {
                    key: "esc"
                    label: qsTr("reject")
                    keyColour: Qt.alpha(root.fg, 0.8)
                    labelColour: root.dim
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
