import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import "prism"

// Prism chat tab. This file only holds the shared state and lays the pieces
// out; every visual block lives in prism/ and receives this item as `tab`.
Item {
    id: root

    implicitWidth: 840
    implicitHeight: 520
    // The composer glow spills past the tab's edges
    clip: true

    // Brand palette (follows the active AI provider)
    readonly property color gBlue: GeminiChat.providerPrimary
    readonly property color gViolet: GeminiChat.providerSecondary
    readonly property color gRed: GeminiChat.providerTertiary

    readonly property string providerLabel: GeminiChat.providerName
    readonly property string providerShape: GeminiChat.providerInfo?.logo ?? "sparkle"
    readonly property string providerStyle: GeminiChat.providerInfo?.style ?? "gemini"
    readonly property bool isClaude: providerStyle === "claude"
    readonly property bool isChatGPT: providerStyle === "chatgpt"
    readonly property bool isGemini: !isClaude && !isChatGPT
    // Claude's composer is a box with the send button in the corner; Gemini
    // and ChatGPT both use a pill.
    readonly property bool boxedInput: isClaude
    // The permission panel docks onto the composer and borrows its look
    readonly property color composerColour: boxedInput ? composerBox.color : composerPill.color
    readonly property int composerRadius: boxedInput ? composerBox.radius : composerPill.radius

    property bool settingsMode: false
    property bool histOpen: false
    // Which header dropdown is open: "" | "provider" | "models" | "quota"
    property string openPanel: ""

    // pending run_bash confirmation surfaced by the daemon
    property string pendingToolCallId: ""
    property bool confirmOpen: false
    property string confirmCommand: ""
    property bool confirmDangerous: false
    // false for network commands: they may run once but never be auto-allowed
    property bool confirmPersistable: true

    function mixColour(a: color, b: color, t: real): color {
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t
        );
    }

    function togglePanel(name: string): void {
        if (openPanel === name) {
            openPanel = "";
            return;
        }
        if (name === "models")
            GeminiChat.loadModels();
        else if (name === "quota")
            GeminiChat.loadQuota();
        openPanel = name;
    }

    function toggleSettings(): void {
        settingsMode = !settingsMode;
        openPanel = "";
        if (settingsMode)
            GeminiChat.loadSettings();
    }

    // Put a suggestion into the composer and hand it the keyboard.
    function useSuggestion(text: string): void {
        GeminiChat.draft = text;
        focusComposer();
    }

    function focusComposer(): void {
        (boxedInput ? composerBox : composerPill).field.forceActiveFocus();
    }

    // Send the user's decision for a pending run_bash call to /tool/confirm.
    function confirmTool(decision: string): void {
        const id = root.pendingToolCallId;
        root.pendingToolCallId = "";
        root.confirmOpen = false;
        if (id !== "")
            GeminiChat.confirmTool(id, decision);
    }

    Connections {
        target: GeminiChat

        function onToolConfirmRequested(info) {
            if (!info)
                return;
            root.pendingToolCallId = info.tool_call_id || "";
            root.confirmCommand = info.command || "";
            root.confirmDangerous = !!info.dangerous;
            root.confirmPersistable = info.persistable !== false;
            root.confirmOpen = true;
        }
    }

    // Soft brand glow around the composer (gemini.google.com). Sits behind
    // the layout so it shows both above the prompt and below it.
    ComposerGlow {
        anchors.horizontalCenter: parent.horizontalCenter
        y: composerStack.y + composerStack.height / 2 - height / 2
        width: Math.min(parent.width, 760)
        height: 460
        colour: root.gBlue
        visible: root.isGemini && !root.settingsMode && GeminiChat.messages.count === 0
    }

    HistoryDrawer {
        tab: root
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        TopBar {
            tab: root
            Layout.fillWidth: true
        }

        ProviderPanel {
            tab: root
            Layout.fillWidth: true
        }

        ModelsPanel {
            tab: root
            Layout.fillWidth: true
        }

        QuotaPanel {
            tab: root
            Layout.fillWidth: true
        }

        // ── Body: empty state or conversation ────────────────────
        Item {
            id: bodyArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: !root.settingsMode

            EmptyState {
                tab: root
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.padding.large * 2, 680)
                visible: GeminiChat.messages.count === 0
            }

            MessageList {
                tab: root
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                visible: GeminiChat.messages.count > 0
            }
        }

        // Permission panel + composer, joined with no gap
        ColumnLayout {
            id: composerStack

            Layout.fillWidth: true
            spacing: 0
            visible: !root.settingsMode

            PermissionDialog {
                tab: root
                Layout.fillWidth: true
                visible: root.confirmOpen
            }

            ComposerPill {
                id: composerPill

                tab: root
                Layout.fillWidth: true
                visible: !root.boxedInput
            }

            ComposerBox {
                id: composerBox

                tab: root
                Layout.fillWidth: true
                visible: root.boxedInput
            }
        }

        // Disclaimer hint under the input
        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.padding.small
            visible: !root.settingsMode
            text: qsTr("%1 can make mistakes. Check important info.").arg(root.providerLabel)
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
        }

        SettingsPane {
            tab: root
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.settingsMode
        }
    }
}
