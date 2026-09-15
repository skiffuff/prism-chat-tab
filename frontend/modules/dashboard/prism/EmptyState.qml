import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.modules.dashboard

// Welcome screen shown while the conversation is empty. Each provider gets
// the feel of its own web app: Gemini a shimmering gradient greeting, ChatGPT
// a plain question with a list of starters, Claude a serif greeting with its
// mark inline and a row of chips.
ColumnLayout {
    id: root

    required property var tab

    readonly property string userName: {
        const u = Quickshell.env("USER") || "";
        return u ? u.charAt(0).toUpperCase() + u.slice(1) : qsTr("there");
    }

    readonly property var greetings: {
        if (root.tab.isChatGPT)
            return [qsTr("Where should we begin?"), qsTr("What's on your mind today?"), qsTr("What can I help with?"), qsTr("Ready when you are.")];
        if (root.tab.isClaude)
            return [qsTr("Hey there, %1").arg(userName), qsTr("Good to see you, %1").arg(userName), qsTr("Welcome back, %1").arg(userName), qsTr("How can I help you today?")];
        const p = root.tab.providerLabel;
        return [qsTr("Hi, I'm %1").arg(p), qsTr("Welcome back, I'm %1").arg(p), qsTr("Good to see you, I'm %1").arg(p), qsTr("How can I help?"), qsTr("What shall we do today?")];
    }

    property int greetIndex: 0

    // Starter prompts. ChatGPT lists them, Claude shows chips.
    readonly property var suggestions: root.tab.isClaude ? [
        { icon: "edit", label: qsTr("Write"), prompt: qsTr("Help me write ") },
        { icon: "school", label: qsTr("Learn"), prompt: qsTr("Explain to me ") },
        { icon: "code", label: qsTr("Code"), prompt: qsTr("Write code that ") },
        { icon: "terminal", label: qsTr("System"), prompt: qsTr("Run a command that ") },
        { icon: "lightbulb", label: qsTr("%1's choice").arg(root.tab.providerLabel), prompt: qsTr("Surprise me with something useful for a Linux desktop") }
    ] : [
        { icon: "terminal", label: qsTr("Run a shell command"), prompt: qsTr("Run ") },
        { icon: "visibility", label: qsTr("Look at my screen"), prompt: qsTr("Look at my screen and tell me what is going on") },
        { icon: "description", label: qsTr("Explain a file"), prompt: qsTr("Explain what this file does: ") }
    ]

    function pickGreeting(): void {
        if (root.greetings.length <= 1) {
            root.greetIndex = 0;
            return;
        }
        let next = root.greetIndex;
        while (next === root.greetIndex)
            next = Math.floor(Math.random() * root.greetings.length);
        root.greetIndex = next;
    }

    spacing: root.tab.isChatGPT ? Tokens.spacing.large : Tokens.spacing.medium

    Component.onCompleted: root.pickGreeting()

    SequentialAnimation {
        id: greetFade

        NumberAnimation {
            target: greetLabel
            property: "opacity"
            to: 0
            duration: 200
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: root.pickGreeting()
        }
        NumberAnimation {
            target: greetLabel
            property: "opacity"
            to: 1
            duration: 200
            easing.type: Easing.InQuad
        }
    }

    Connections {
        target: GeminiChat

        function onChatReset() {
            greetFade.restart();
        }

        // Snap the gradient to the new palette the moment the provider changes
        function onCurrentProviderChanged() {
            greetFill.c0 = GeminiChat.providerPrimary;
            greetFill.c1 = GeminiChat.providerSecondary;
            greetFill.c2 = GeminiChat.providerTertiary;
            greetGradAnim.restart();
            root.greetIndex = Math.min(root.greetIndex, root.greetings.length - 1);
        }
    }

    // ── Greeting ────────────────────────────────────────────────
    Item {
        id: greetLabel

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: greetRow.implicitWidth
        implicitHeight: greetRow.implicitHeight

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutQuad
            }
        }

        Row {
            id: greetRow

            spacing: Tokens.spacing.medium

            // Claude puts its mark right before the words
            GeminiLogo {
                visible: root.tab.isClaude
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 30
                implicitHeight: 30
                shape: "claude"
                color: root.tab.gBlue
                tint: root.tab.gBlue
                tintAmount: 1
            }

            Item {
                width: greetMask.implicitWidth
                height: greetMask.implicitHeight

                // Gemini: provider gradient flowing through the glyphs
                Rectangle {
                    id: greetFill

                    anchors.fill: parent
                    visible: root.tab.isGemini

                    property color c0: GeminiChat.providerPrimary
                    property color c1: GeminiChat.providerSecondary
                    property color c2: GeminiChat.providerTertiary

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: greetFill.c0
                        }
                        GradientStop {
                            position: 0.5
                            color: greetFill.c1
                        }
                        GradientStop {
                            position: 1
                            color: greetFill.c2
                        }
                    }

                    layer.enabled: true
                    layer.effect: Mask {
                        maskSource: greetMask
                    }

                    SequentialAnimation {
                        id: greetGradAnim

                        running: root.tab.isGemini && root.visible
                        loops: Animation.Infinite

                        ParallelAnimation {
                            ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                        }
                        ParallelAnimation {
                            ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                        }
                        ParallelAnimation {
                            ColorAnimation { target: greetFill; property: "c0"; to: GeminiChat.providerPrimary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c1"; to: GeminiChat.providerSecondary; duration: 1400; easing.type: Easing.InOutSine }
                            ColorAnimation { target: greetFill; property: "c2"; to: GeminiChat.providerTertiary; duration: 1400; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // Glyph source for the mask; also the plain rendering for
                // ChatGPT (system sans) and Claude (serif).
                StyledText {
                    id: greetMask

                    visible: !root.tab.isGemini
                    width: implicitWidth
                    height: implicitHeight
                    text: root.greetings[Math.min(root.greetIndex, root.greetings.length - 1)]
                    font: {
                        if (root.tab.isClaude)
                            return Tokens.font.body.builders.large.family("Noto Serif").size(26).weight(Font.Normal).build();
                        if (root.tab.isChatGPT)
                            return Tokens.font.body.builders.large.size(18).weight(Font.Medium).build();
                        return Tokens.font.body.builders.large.size(26).weight(Font.Medium).build();
                    }
                    color: root.tab.isGemini ? "white" : Colours.palette.m3onSurface
                    renderType: Text.QtRendering
                    layer.enabled: root.tab.isGemini
                    layer.smooth: false
                }
            }
        }
    }

    // ── Starters ────────────────────────────────────────────────
    // ChatGPT: a quiet left-aligned list
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.large
        visible: root.tab.isChatGPT
        spacing: 2

        Repeater {
            model: root.tab.isChatGPT ? root.suggestions : []

            delegate: Rectangle {
                id: rowItem

                required property var modelData

                implicitWidth: 340
                implicitHeight: 34
                radius: Tokens.rounding.medium
                color: rowArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.modelData.icon
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.modelData.label
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tab.useSuggestion(rowItem.modelData.prompt)
                }
            }
        }
    }

    // Claude: a centered row of chips
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.large
        visible: root.tab.isClaude
        spacing: Tokens.spacing.small

        Repeater {
            model: root.tab.isClaude ? root.suggestions : []

            delegate: Rectangle {
                id: chip

                required property var modelData

                implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 32
                radius: Tokens.rounding.medium
                color: chipArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.icon
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.label
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }

                MouseArea {
                    id: chipArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tab.useSuggestion(chip.modelData.prompt)
                }
            }
        }
    }
}
