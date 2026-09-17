import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// The conversation: user turns as brand-coloured bubbles on the right,
// assistant turns as plain text under a small provider header.
ListView {
    id: root

    required property var tab

    spacing: Tokens.spacing.medium
    clip: true
    model: GeminiChat.messages
    boundsBehavior: Flickable.StopAtBounds

    onCountChanged: positionViewAtEnd()

    delegate: Item {
        id: msgRoot

        required property int index
        required property string sender
        required property string text
        required property var images

        readonly property bool isUser: sender === "user"

        width: root.width
        implicitHeight: msgColumn.implicitHeight
        opacity: 0

        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        Component.onCompleted: opacity = 1

        ColumnLayout {
            id: msgColumn

            width: parent.width
            spacing: Tokens.spacing.small

            // Assistant header: logo + provider name
            RowLayout {
                visible: !msgRoot.isUser
                spacing: Tokens.spacing.small

                GeminiLogo {
                    implicitWidth: 18
                    implicitHeight: 18
                    shape: root.tab.providerShape
                    color: msgRoot.index % 3 === 0 ? GeminiChat.providerPrimary : (msgRoot.index % 3 === 1 ? GeminiChat.providerSecondary : GeminiChat.providerTertiary)
                }

                StyledText {
                    text: root.tab.providerLabel
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // User bubble
            StyledRect {
                visible: msgRoot.isUser
                Layout.alignment: Qt.AlignRight
                Layout.maximumWidth: root.width * 0.75
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

                            Layout.preferredWidth: Math.min(220, root.width * 0.6)
                            Layout.preferredHeight: 140
                            fillMode: Image.PreserveAspectCrop
                            source: "data:" + (modelData.mime || "image/png") + ";base64," + (modelData.data || "")
                        }
                    }

                    StyledText {
                        Layout.maximumWidth: root.width * 0.7 - Tokens.padding.large * 2
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
                Layout.maximumWidth: root.width * 0.85
                wrapMode: Text.Wrap
                text: msgRoot.text
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }
        }
    }
}
