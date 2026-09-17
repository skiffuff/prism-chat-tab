import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Dropdown listing the AI providers reported by the daemon.
StyledRect {
    id: root

    required property var tab

    visible: root.tab.openPanel === "provider"
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
            id: provDelegate

            required property var modelData

            readonly property bool provActive: GeminiChat.currentProvider === modelData.id

            width: providerList.width
            implicitHeight: 38
            radius: Tokens.rounding.small
            color: provActive ? Colours.palette.m3secondaryContainer : (provHover.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : "transparent")

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                GeminiLogo {
                    implicitWidth: 20
                    implicitHeight: 20
                    shape: provDelegate.modelData.logo
                    color: provDelegate.modelData.primary
                }

                StyledText {
                    text: provDelegate.modelData.name
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    color: provDelegate.provActive ? root.tab.gBlue : Colours.palette.m3onSurface
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: provDelegate.modelData.has_key ? "#a6e3a1" : "#f9e2af"
                }

                StyledText {
                    text: provDelegate.modelData.has_key ? qsTr("key set") : qsTr("no key")
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
                    if (!provDelegate.provActive)
                        GeminiChat.selectProvider(provDelegate.modelData.id);
                    root.tab.openPanel = "";
                }
            }
        }
    }
}
