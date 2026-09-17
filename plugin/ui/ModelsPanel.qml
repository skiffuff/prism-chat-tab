import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Dropdown listing the current provider's models with their quota status.
StyledRect {
    id: root

    required property var tab

    visible: root.tab.openPanel === "models"
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
            readonly property bool current: modelDelegate.modelData.id === GeminiChat.currentModel

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
                    color: modelDelegate.quotaStatus === "exhausted" ? "#f38ba8" : (modelDelegate.quotaStatus === "warning" ? "#f9e2af" : "#a6e3a1")
                }

                MaterialIcon {
                    visible: modelDelegate.current
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
                    root.tab.openPanel = "";
                }
            }
        }
    }
}
