import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Thumbnails of the files queued for the next message, each with a remove
// button. Hidden when nothing is attached.
RowLayout {
    id: root

    visible: GeminiChat.attachments.length > 0
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
                source: attChip.isImage ? "data:" + attChip.modelData.mime + ";base64," + attChip.modelData.data : ""
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
                color: removeHover.containsMouse ? "#f38ba8" : Colours.palette.m3surfaceContainerHighest

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
