import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Settings view: API key + endpoint for the active provider, the system
// instruction and the glow overlay tuning. Saved to the daemon as a whole.
Item {
    id: root

    required property var tab

    readonly property string keyLabel: {
        if (root.tab.isClaude)
            return qsTr("Claude API key");
        if (root.tab.isChatGPT)
            return qsTr("OpenAI API key");
        return qsTr("Google AI Studio API key");
    }

    readonly property string endpointLabel: {
        if (root.tab.isClaude)
            return qsTr("API endpoint (Claude)");
        if (root.tab.isChatGPT)
            return qsTr("API endpoint (OpenAI)");
        return qsTr("Worker URL (Cloudflare proxy, set in config.json)");
    }

    readonly property string endpointValue: {
        if (root.tab.isClaude)
            return GeminiChat.settingsData?.anthropic_url ?? "https://api.anthropic.com";
        if (root.tab.isChatGPT)
            return GeminiChat.settingsData?.openai_url ?? "https://api.openai.com";
        return GeminiChat.settingsData?.worker_url ?? "";
    }

    function save(): void {
        const grad = [];
        for (let i = 0; i < gradRepeater.count; i++) {
            const item = gradRepeater.itemAt(i);
            if (item)
                grad.push(item.currentColor.toString());
        }
        const payload = {
            system_instruction: sysInput.text,
            glow: {
                enabled: glowToggle.checked,
                ring_count: Math.round(ringsSlider.value),
                sigma: Math.round(sigmaSlider.value),
                alpha: Math.round(alphaSlider.value * 100) / 100,
                gradient: grad
            }
        };
        // The endpoint field means a different setting per provider; Gemini's
        // worker URL is read-only here.
        if (root.tab.isClaude)
            payload.anthropic_url = endpointInput.text.trim();
        else if (root.tab.isChatGPT)
            payload.openai_url = endpointInput.text.trim();
        // Only touch the keyring when the user actually enters a key; an
        // empty field never wipes the stored one.
        if (keyInput.text.trim().length > 0)
            payload.api_key = keyInput.text.trim();
        GeminiChat.saveSettings(payload);
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        contentHeight: settingsCol.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol

            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - Tokens.padding.large * 2, 560)
            spacing: Tokens.spacing.large

            StyledText {
                text: qsTr("Settings")
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Tokens.spacing.small
            }

            // ── Section: API & Connection ──────────────
            Section {
                icon: "key"
                title: qsTr("Connection")
                accent: GeminiChat.providerInfo?.primary ?? "#4285F4"

                StyledText {
                    text: root.keyLabel
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Field {
                        Layout.fillWidth: true
                        focused: keyInput.activeFocus

                        TextInput {
                            id: keyInput

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.medium
                            clip: true
                            selectByMouse: true
                            echoMode: TextInput.Password

                            property string lastValidated: ""

                            onActiveFocusChanged: {
                                if (!activeFocus && text !== lastValidated && text.length > 0) {
                                    validationLabel.text = qsTr("Checking...");
                                    validationLabel.color = Colours.palette.m3onSurfaceVariant;
                                    GeminiChat.validateSettings(text, endpointInput.text);
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !keyInput.text && !keyInput.activeFocus
                                text: GeminiChat.settingsData?.api_key_set
                                    ? qsTr("Key is set ••• (%1)").arg(GeminiChat.settingsData?.key_placeholder ?? "")
                                    : (GeminiChat.settingsData?.key_placeholder ?? "AIza...")
                                font: Tokens.font.body.medium
                                color: GeminiChat.settingsData?.api_key_set ? "#a6e3a1" : Colours.palette.m3outline
                            }
                        }
                    }

                    StyledRect {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Tokens.rounding.medium
                        color: showKeyArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: keyInput.echoMode === TextInput.Password ? "visibility" : "visibility_off"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: showKeyArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: keyInput.echoMode = keyInput.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password
                        }
                    }
                }

                StyledText {
                    id: validationLabel

                    Layout.fillWidth: true
                    text: ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant

                    Connections {
                        target: GeminiChat

                        function onSettingsValidated(result) {
                            keyInput.lastValidated = keyInput.text;
                            if (result.valid) {
                                validationLabel.text = result.models !== undefined
                                    ? qsTr("Valid • %1 models").arg(result.models)
                                    : qsTr("Valid");
                                validationLabel.color = "#a6e3a1";
                            } else {
                                validationLabel.text = result.error;
                                validationLabel.color = "#f38ba8";
                            }
                        }
                    }
                }

                Divider {}

                StyledText {
                    text: root.endpointLabel
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Field {
                    Layout.fillWidth: true
                    focused: endpointInput.activeFocus

                    TextInput {
                        id: endpointInput

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        clip: true
                        selectByMouse: true
                        // The Gemini worker URL is fixed at daemon start (the
                        // API refuses to change it), so only show it.
                        readOnly: root.tab.isGemini
                        text: root.endpointValue

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !endpointInput.text && !endpointInput.activeFocus
                            text: "https://..."
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3outline
                        }
                    }
                }
            }

            // ── Section: System Instruction ────────────
            Section {
                icon: "psychology"
                title: qsTr("System instruction")
                accent: GeminiChat.providerInfo?.secondary ?? "#9B72CB"

                StyledText {
                    text: qsTr("Defines how %1 behaves in chat").arg(GeminiChat.providerName)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Field {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    focused: sysInput.activeFocus

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        contentHeight: sysInput.implicitHeight
                        clip: true
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: sysInput

                            width: parent.width
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.medium
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            text: GeminiChat.settingsData?.system_instruction ?? ""
                        }
                    }
                }
            }

            // ── Section: Glow ─────────────────────────
            Section {
                icon: "blur_on"
                title: qsTr("Glow overlay")
                accent: GeminiChat.providerInfo?.tertiary ?? "#D96570"

                header: StyledRect {
                    implicitWidth: 44
                    implicitHeight: 24
                    radius: 12
                    color: glowToggle.checked ? (GeminiChat.providerInfo?.primary ?? "#4285F4") : Colours.palette.m3surfaceContainerHighest

                    Rectangle {
                        x: glowToggle.checked ? parent.width - 22 : 2
                        y: 2
                        width: 20
                        height: 20
                        radius: 10
                        color: "white"

                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }

                    MouseArea {
                        id: glowToggle

                        property bool checked: GeminiChat.settingsData?.glow?.enabled ?? true

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: checked = !checked
                    }

                    Connections {
                        target: GeminiChat

                        function onSettingsDataChanged() {
                            glowToggle.checked = GeminiChat.settingsData?.glow?.enabled ?? true;
                        }
                    }
                }

                SliderRow {
                    id: ringsSlider

                    label: qsTr("Rings")
                    from: 24
                    to: 192
                    stepSize: 8
                    value: GeminiChat.settingsData?.glow?.ring_count ?? 96
                }

                SliderRow {
                    id: sigmaSlider

                    label: "Sigma"
                    from: 4
                    to: 80
                    stepSize: 2
                    value: GeminiChat.settingsData?.glow?.sigma ?? 28
                }

                SliderRow {
                    id: alphaSlider

                    label: "Alpha"
                    from: 0.05
                    to: 1.0
                    stepSize: 0.05
                    decimals: 2
                    value: GeminiChat.settingsData?.glow?.alpha ?? 0.42
                }

                Divider {}

                StyledText {
                    text: qsTr("Gradient")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    Repeater {
                        id: gradRepeater

                        model: GeminiChat.providerInfo?.gradient ?? ["#4285F4", "#9B72CB", "#D96570", "#4285F4"]

                        delegate: Rectangle {
                            id: swatch

                            required property int index
                            required property string modelData

                            property color currentColor: modelData

                            Layout.fillWidth: true
                            height: 36
                            radius: Tokens.rounding.medium
                            color: swatchArea.containsMouse ? Qt.alpha(Colours.palette.m3primary, 0.15) : Colours.tPalette.m3surfaceContainerHigh

                            Rectangle {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                radius: 12
                                color: swatch.currentColor
                            }

                            MouseArea {
                                id: swatchArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Cycle through a small palette for a quick pick
                                    const palette = ["#4285F4", "#9B72CB", "#D96570", "#E9A23B", "#4FA267", "#EA6C69", "#10A37F", "#D97757"];
                                    const cur = swatch.currentColor.toString().toUpperCase();
                                    let idx = 0;
                                    for (let i = 0; i < palette.length; i++) {
                                        if (palette[i].toUpperCase() === cur) {
                                            idx = (i + 1) % palette.length;
                                            break;
                                        }
                                    }
                                    swatch.currentColor = palette[idx];
                                }
                            }
                        }
                    }
                }
            }

            // ── Save button ──────────────────────────
            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Tokens.rounding.medium
                color: saveArea.containsMouse ? root.tab.gBlue : Colours.palette.m3primaryContainer

                Row {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "check"
                        fontStyle: Tokens.font.icon.small
                        color: saveArea.containsMouse ? "#ffffff" : Colours.palette.m3onPrimaryContainer
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Save")
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        color: saveArea.containsMouse ? "#ffffff" : Colours.palette.m3onPrimaryContainer
                    }
                }

                MouseArea {
                    id: saveArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.save()
                }
            }

            Item {
                Layout.fillWidth: true
                height: Tokens.padding.small
            }
        }
    }

    // Card with an icon + title header; children go below the header.
    component Section: StyledRect {
        id: section

        required property string icon
        required property string title
        property color accent: Colours.palette.m3primary
        // Optional control shown at the right end of the header row
        property Item header: null
        default property alias content: sectionCol.data

        Layout.fillWidth: true
        implicitHeight: sectionCol.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerLow

        onHeaderChanged: {
            if (header)
                header.parent = headerSlot;
        }

        Component.onCompleted: {
            if (header)
                header.parent = headerSlot;
        }

        ColumnLayout {
            id: sectionCol

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: Qt.alpha(section.accent, 0.15)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: section.icon
                        fontStyle: Tokens.font.icon.small
                        color: section.accent
                    }
                }

                StyledText {
                    text: section.title
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }

                Item {
                    Layout.fillWidth: true
                }

                Item {
                    id: headerSlot

                    implicitWidth: section.header ? section.header.implicitWidth : 0
                    implicitHeight: section.header ? section.header.implicitHeight : 0
                }
            }
        }
    }

    component Field: Rectangle {
        property bool focused: false

        implicitHeight: 40
        radius: Tokens.rounding.medium
        color: focused ? Qt.alpha(Colours.palette.m3primary, 0.08) : Colours.tPalette.m3surfaceContainerHigh
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Colours.palette.m3outlineVariant
        opacity: 0.4
    }

    component SliderRow: ColumnLayout {
        id: sliderRow

        required property string label
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property alias value: slider.value
        property int decimals: 0

        Layout.fillWidth: true
        spacing: 2

        StyledText {
            text: sliderRow.label
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        RowLayout {
            spacing: Tokens.spacing.small

            StyledSlider {
                id: slider

                Layout.fillWidth: true
            }

            StyledText {
                text: slider.value.toFixed(sliderRow.decimals)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                width: 32
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
