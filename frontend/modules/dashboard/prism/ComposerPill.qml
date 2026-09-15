import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Pill composer used by Gemini and ChatGPT: "+" on the left, the prompt in
// the middle, the send circle on the right. ChatGPT gets the neutral grey of
// its own composer instead of the Material container tint.
StyledRect {
    id: root

    required property var tab

    readonly property alias field: input
    readonly property bool ready: input.text.trim().length > 0 || GeminiChat.attachments.length > 0

    implicitHeight: attachments.visible ? 50 + 62 : 50
    radius: 25
    color: root.tab.isChatGPT
        ? (Colours.light
            ? root.tab.mixColour(Colours.tPalette.m3surfaceContainerHigh, "#F4F4F4", 0.7)
            : root.tab.mixColour(Colours.tPalette.m3surfaceContainerHigh, "#303030", 0.7))
        : Colours.tPalette.m3surfaceContainerHigh

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutQuint
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 300
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.small
        anchors.rightMargin: Tokens.padding.small
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: Tokens.spacing.small

        AttachmentStrip {
            id: attachments

            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.medium
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
                color: plusArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

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

            ComposerField {
                id: input

                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                focus: true
                placeholder: root.tab.isChatGPT ? qsTr("Ask anything") : qsTr("Ask %1").arg(root.tab.providerLabel)
            }

            SendButton {
                ready: root.ready
                onClicked: input.send()
            }
        }
    }
}
