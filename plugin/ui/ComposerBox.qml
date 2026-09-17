import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Claude-style composer: a warm paper box, the prompt on top, a toolbar row
// underneath with attach on the left and model + send on the right.
StyledRect {
    id: root

    required property var tab

    readonly property alias field: input
    readonly property bool ready: input.text.trim().length > 0 || GeminiChat.attachments.length > 0

    // "claude-sonnet-4-5" -> "Sonnet 4.5", "claude-3-5-haiku" -> "3.5 Haiku"
    readonly property string modelLabel: {
        const parts = GeminiChat.currentModel.replace(/^claude-/, "").split("-");
        const out = [];
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i];
            if (/^\d$/.test(p) && i + 1 < parts.length && /^\d$/.test(parts[i + 1])) {
                out.push(p + "." + parts[i + 1]);
                i++;
            } else {
                out.push(p.charAt(0).toUpperCase() + p.slice(1));
            }
        }
        return out.join(" ");
    }

    implicitHeight: (attachments.visible ? 62 : 0) + 96
    radius: 20
    topLeftRadius: root.tab.confirmOpen ? 0 : radius
    topRightRadius: root.tab.confirmOpen ? 0 : radius
    color: Colours.light
        ? root.tab.mixColour(Colours.palette.m3surface, "#F7EFE5", 0.85)
        : root.tab.mixColour(Colours.palette.m3surface, "#3A3128", 0.55)
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(GeminiChat.providerPrimary, 0.55) : Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutQuint
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 200
            easing.type: Easing.InOutSine
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.medium
        anchors.topMargin: Tokens.padding.medium
        anchors.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        AttachmentStrip {
            id: attachments

            Layout.fillWidth: true
        }

        ComposerField {
            id: input

            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholder: qsTr("How can I help you today?")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: plusArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "add"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                MouseArea {
                    id: plusArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GeminiChat.pickFile()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Current model, like the "Sonnet 5" label on claude.ai
            StyledText {
                text: root.modelLabel
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tab.togglePanel("models")
                }
            }

            SendButton {
                size: 32
                ready: root.ready
                onClicked: input.send()
            }
        }
    }
}
