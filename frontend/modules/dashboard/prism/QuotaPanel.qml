import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Dropdown with the daemon's usage counters for the active provider.
StyledRect {
    id: root

    required property var tab

    // A local provider (Ollama) needs no key and has no quota to run out of
    readonly property bool isLocal: GeminiChat.providerInfo?.needs_key === false
    readonly property bool noKey: !isLocal && GeminiChat.providerInfo?.has_key === false
    readonly property bool exhausted: GeminiChat.quotaData?.quota_exceeded ?? false
    readonly property var modelKeys: root.noKey ? [] : Object.keys(GeminiChat.quotaData?.by_model ?? {})
    readonly property color statusColour: noKey ? "#94a3b8" : (exhausted ? "#f38ba8" : "#a6e3a1")

    function usageLine(stats): string {
        if (!stats)
            return "—";
        if (typeof stats === "number")
            return qsTr("%1 req").arg(stats);
        return qsTr("%1 req • in %2 • out %3").arg(stats.requests).arg(stats.prompt_tokens).arg(stats.output_tokens);
    }

    visible: root.tab.openPanel === "quota"
    implicitHeight: quotaContent.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: quotaContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        // ── Overall API status ────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Rectangle {
                width: 8
                height: 8
                radius: 4
                Layout.alignment: Qt.AlignVCenter
                color: root.statusColour
            }

            StyledText {
                text: root.noKey
                    ? qsTr("%1 API key not found").arg(GeminiChat.providerName)
                    : root.isLocal
                        ? qsTr("Local models — no quota")
                        : (root.exhausted ? qsTr("API quota exhausted") : qsTr("API quota available"))
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: root.statusColour
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            StyledText {
                visible: !root.noKey
                text: GeminiChat.quotaData ? root.usageLine(GeminiChat.quotaData) : qsTr("Loading...")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                Layout.alignment: Qt.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.modelKeys.length > 0
            height: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.4
        }

        // ── Per-model status ──────────────────────────
        StyledText {
            visible: root.modelKeys.length > 0
            text: qsTr("Model limits")
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
        }

        Repeater {
            model: root.modelKeys

            delegate: RowLayout {
                id: modelRow

                required property string modelData

                spacing: Tokens.spacing.medium

                StyledText {
                    text: "• " + modelRow.modelData
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                    Layout.maximumWidth: 180
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.usageLine(GeminiChat.quotaData?.by_model?.[modelRow.modelData])
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Colours.palette.m3outlineVariant
            opacity: 0.4
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Updates every 30 seconds")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            opacity: 0.8
        }
    }
}
