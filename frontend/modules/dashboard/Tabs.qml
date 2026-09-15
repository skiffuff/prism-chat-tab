pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property real nonAnimWidth
    required property ScreenState screenState
    required property var tabs
    required property Component geminiComponent

    readonly property alias count: bar.count

    // NOTE: the provider-palette snap lives on GeminiLogo itself (see gemIcon
    // below) — gemIcon/gemIconAnim are created per Repeater delegate, so they
    // are not addressable from this root scope.

    implicitHeight: bar.implicitHeight + bar.anchors.topMargin + indicator.implicitHeight + indicator.anchors.topMargin + separator.implicitHeight

    TabBar {
        id: bar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Tokens.sizes.dashboard.tabIndicatorSpacing

        currentIndex: root.screenState.dashboardTab
        onCurrentIndexChanged: root.screenState.dashboardTab = currentIndex

        implicitHeight: contentHeight
        background: null
        contentItem: RowLayout {
            spacing: 0

            Repeater {
                model: bar.contentModel
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.tabs
            }

            delegate: Tab {
                required property var modelData

                iconName: modelData.iconName
                text: modelData.component === root.geminiComponent ? GeminiChat.providerName : modelData.text
            }
        }
    }

    Item {
        id: indicator

        anchors.top: bar.bottom
        anchors.topMargin: 5

        implicitWidth: {
            const tab = bar.currentItem;
            if (tab)
                return tab.implicitWidth;
            const width = (root.nonAnimWidth - bar.spacing * (bar.count - 1)) / bar.count;
            return width;
        }
        implicitHeight: 3

        x: {
            const tab = bar.currentItem;
            const width = (root.nonAnimWidth - bar.spacing * (bar.count - 1)) / bar.count;
            const tabWidth = tab?.implicitWidth ?? width;
            return width * bar.currentIndex + (width - tabWidth) / 2;
        }

        clip: true

        StyledRect {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight * 2

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
        }

        Behavior on x {
            Anim {}
        }

        Behavior on implicitWidth {
            Anim {}
        }
    }

    StyledRect {
        id: separator

        anchors.top: indicator.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    component Tab: TabButton {
        id: tab

        required property string iconName
        readonly property bool current: TabBar.tabBar.currentItem === this
        readonly property bool isGemini: modelData.component === root.geminiComponent

        Layout.fillWidth: true
        Layout.preferredWidth: 1 // Uniform width across all tabs
        implicitWidth: implicitContentWidth
        implicitHeight: implicitContentHeight
        background: null

        contentItem: CustomMouseArea {
            id: mouse

            function onWheel(event: WheelEvent): void {
                if (event.angleDelta.y < 0)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, bar.count - 1);
                else if (event.angleDelta.y > 0)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            implicitWidth: Math.max(icon.width, label.width)
            implicitHeight: icon.height + label.height

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: root.screenState.dashboardTab = tab.TabBar.index

            StateLayer {
                id: stateLayer

                anchors.fill: undefined
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: parent.height + Tokens.sizes.dashboard.tabIndicatorSpacing * 2

                radius: Tokens.rounding.medium
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                onClicked: root.screenState.dashboardTab = tab.TabBar.index
            }

            MaterialIcon {
                id: icon

                visible: !tab.isGemini
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: label.top

                text: tab.iconName
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fill: tab.current ? 1 : 0
                fontStyle: Tokens.font.icon.medium

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            GeminiLogo {
                id: gemIcon

                visible: tab.isGemini
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: label.top
                implicitWidth: 24
                implicitHeight: 24
                shape: GeminiChat.providerInfo?.logo ?? "sparkle"

                readonly property bool hov: mouse.containsMouse
                property color shimmerColor: GeminiChat.providerPrimary

                // Same tint drive for the SVG Claude logo:
                // hover => cycle through the Claude palette
                // Active/Inactive tab is neutral when not hovered
                property color neutralColor: Colours.palette.m3onSurfaceVariant
                color: hov ? shimmerColor : neutralColor
                tint: hov ? shimmerColor : neutralColor
                tintAmount: hov ? 1 : 0
                scale: hov ? 1.15 : 1.0

                // Bind to provider changes
                Connections {
                    target: GeminiChat
                    function onCurrentProviderChanged() {
                        gemIcon.shimmerColor = GeminiChat.providerPrimary;
                        gemIconAnim.restart();
                    }
                }

                SequentialAnimation {
                    id: gemIconAnim
                    running: tab.isGemini && gemIcon.hov && !tab.current
                    loops: Animation.Infinite

                    ColorAnimation {
                        target: gemIcon
                        property: "shimmerColor"
                        to: GeminiChat.providerSecondary
                        duration: 600 // Faster
                        easing.type: Easing.InOutSine
                    }
                    ColorAnimation {
                        target: gemIcon
                        property: "shimmerColor"
                        to: GeminiChat.providerTertiary
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                    ColorAnimation {
                        target: gemIcon
                        property: "shimmerColor"
                        to: GeminiChat.providerPrimary
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                }
            }

            StyledText {
                id: label

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                text: tab.text
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
