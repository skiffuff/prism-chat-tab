import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.dashboard

// Header row: history toggle, brand logo, provider chip, live-watch chip,
// daemon status dot, model chip and the icon buttons.
RowLayout {
    id: root

    required property var tab

    spacing: Tokens.spacing.small

    // Hamburger -> opens history drawer
    IconChip {
        icon: "menu"
        size: 34
        active: false
        flat: true
        onClicked: {
            GeminiChat.loadSessions();
            root.tab.histOpen = !root.tab.histOpen;
        }
    }

    GeminiLogo {
        id: headerLogo

        implicitWidth: 22
        implicitHeight: 22
        Layout.alignment: Qt.AlignVCenter
        shape: root.tab.providerShape

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
                duration: 250
                easing.type: Easing.InOutSine
            }
        }

        Behavior on tint {
            ColorAnimation {
                duration: 250
                easing.type: Easing.InOutSine
            }
        }

        // Snap to the new palette the moment the provider changes
        Connections {
            target: GeminiChat

            function onCurrentProviderChanged() {
                headerLogo.shimmerColor = GeminiChat.providerPrimary;
                headerLogoAnim.restart();
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
                duration: 600
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
        implicitWidth: providerRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 30
        radius: Tokens.rounding.full
        color: root.tab.openPanel === "provider" ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

        Row {
            id: providerRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            GeminiLogo {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 16
                implicitHeight: 16
                shape: root.tab.providerShape
                color: GeminiChat.providerPrimary
            }

            StyledText {
                text: root.tab.providerLabel
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }

            MaterialIcon {
                text: root.tab.openPanel === "provider" ? "arrow_drop_up" : "arrow_drop_down"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tab.togglePanel("provider")
        }
    }

    Item {
        Layout.fillWidth: true
    }

    // Live watch indicator / stop button
    StyledRect {
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

    // Daemon status dot
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
        implicitWidth: modelRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 30
        radius: Tokens.rounding.full
        color: root.tab.openPanel === "models" ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

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
                text: root.tab.openPanel === "models" ? "arrow_drop_up" : "arrow_drop_down"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tab.togglePanel("models")
        }
    }

    IconChip {
        icon: "data_usage"
        active: root.tab.openPanel === "quota"
        onClicked: root.tab.togglePanel("quota")
    }

    IconChip {
        id: clearChip

        icon: "refresh"
        active: false
        iconRotation: 0

        Behavior on iconRotation {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutCubic
            }
        }

        onClicked: {
            iconRotation += 360;
            GeminiChat.clearHistory();
        }
    }

    IconChip {
        icon: "settings"
        active: root.tab.settingsMode
        accent: true
        onClicked: root.tab.toggleSettings()
    }

    // Round icon button used across the header
    component IconChip: StyledRect {
        id: chip

        required property string icon
        property bool active: false
        // Highlight the active state with the primary container instead of
        // the secondary one (settings)
        property bool accent: false
        // No background unless hovered (hamburger)
        property bool flat: false
        property int size: 30
        property real iconRotation: 0

        signal clicked()

        implicitWidth: size
        implicitHeight: size
        radius: Tokens.rounding.full
        color: {
            if (chipArea.containsMouse)
                return Colours.tPalette.m3surfaceContainerHighest;
            if (active)
                return accent ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer;
            return flat ? "transparent" : Colours.tPalette.m3surfaceContainer;
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: chip.icon
            fontStyle: Tokens.font.icon.small
            color: chip.active && chip.accent ? Colours.palette.m3primary : (chip.flat ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
            rotation: chip.iconRotation
        }

        MouseArea {
            id: chipArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
}
