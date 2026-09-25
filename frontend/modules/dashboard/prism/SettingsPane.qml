import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.dashboard

// Settings, laid out like the web apps' settings dialogs: a section list on
// the left, one page on the right, and a save bar underneath that only
// lights up when something actually changed. Pages: Connection (key and
// endpoint for the active provider), Behaviour (system instruction),
// Appearance (the glow overlay) and Permissions (the "Allow always"
// patterns, with a way to revoke them).
Item {
    id: root

    required property var tab

    readonly property var sd: GeminiChat.settingsData
    readonly property color accent: root.tab.gBlue
    readonly property color ok: "#a6e3a1"
    readonly property color bad: "#f38ba8"

    property int section: 0

    readonly property var sections: [
        { icon: "key", label: qsTr("Connection") },
        { icon: "psychology", label: qsTr("Behaviour") },
        { icon: "blur_on", label: qsTr("Appearance") },
        { icon: "verified_user", label: qsTr("Permissions") }
    ]

    // A provider that runs locally authenticates with nothing
    readonly property bool needsKey: GeminiChat.providerInfo?.needs_key !== false

    readonly property string endpointDefault: {
        if (root.tab.isClaude)
            return "https://api.anthropic.com";
        if (root.tab.isChatGPT)
            return "https://api.openai.com";
        if (root.tab.isOllama)
            return "http://127.0.0.1:11434";
        return "";
    }

    readonly property string endpointValue: {
        if (root.tab.isClaude)
            return root.sd?.anthropic_url ?? root.endpointDefault;
        if (root.tab.isChatGPT)
            return root.sd?.openai_url ?? root.endpointDefault;
        if (root.tab.isOllama)
            return root.sd?.ollama_url ?? root.endpointDefault;
        return root.sd?.worker_url ?? "";
    }

    // Working copy of the glow gradient; swatches edit this, save sends it
    property var gradient: []

    // Cycle order for the swatch click handler below
    readonly property var swatchPalette: ["#4285f4", "#9b72cb", "#d96570", "#e9a23b", "#4fa267", "#ea6c69", "#10a37f", "#74aa9c", "#d97757", "#c96442", "#f5a524", "#ffffff"]

    readonly property bool dirty: keyInput.text.length > 0
        || sysInput.text !== (root.sd?.system_instruction ?? "")
        || (!root.tab.isGemini && endpointInput.text.trim() !== root.endpointValue)
        || glowToggle.checked !== (root.sd?.glow?.enabled ?? true)
        || Math.round(sigmaSlider.value) !== (root.sd?.glow?.sigma ?? 64)
        || Math.abs(alphaSlider.value - (root.sd?.glow?.alpha ?? 0.8)) > 0.001
        || sweepToggle.checked !== (root.sd?.glow?.sweep ?? false)
        || Math.round(sweepSlider.value) !== (root.sd?.glow?.sweep_ms ?? 1200)
        || root.gradient.join(",") !== (root.sd?.glow?.gradient ?? []).join(",")

    // Save bar message: "" | "saving" | "saved" | error text
    property string status: ""
    property bool statusOk: true

    // Pull every field back from the daemon's copy
    function reset(): void {
        keyInput.text = "";
        keyInput.echoMode = TextInput.Password;
        endpointInput.text = root.endpointValue;
        sysInput.text = root.sd?.system_instruction ?? "";
        glowToggle.checked = root.sd?.glow?.enabled ?? true;
        sigmaSlider.value = root.sd?.glow?.sigma ?? 64;
        alphaSlider.value = root.sd?.glow?.alpha ?? 0.8;
        sweepToggle.checked = root.sd?.glow?.sweep ?? false;
        sweepSlider.value = root.sd?.glow?.sweep_ms ?? 1200;
        root.gradient = (root.sd?.glow?.gradient ?? []).slice();
        validationLabel.text = "";
        removeKey.armed = false;
    }

    function save(): void {
        // A gradient equal to the provider's own palette is sent as empty so
        // the glow keeps following the provider instead of being pinned.
        const isDefault = root.gradient.join(",") === (root.sd?.glow_default_gradient ?? []).join(",");
        const payload = {
            system_instruction: sysInput.text,
            glow: {
                enabled: glowToggle.checked,
                sigma: Math.round(sigmaSlider.value),
                alpha: Math.round(alphaSlider.value * 100) / 100,
                sweep: sweepToggle.checked,
                sweep_ms: Math.round(sweepSlider.value),
                gradient: isDefault ? [] : root.gradient
            }
        };
        // The endpoint field means a different setting per provider; Gemini's
        // worker URL is fixed at daemon start and only shown.
        if (root.tab.isClaude)
            payload.anthropic_url = endpointInput.text.trim();
        else if (root.tab.isChatGPT)
            payload.openai_url = endpointInput.text.trim();
        else if (root.tab.isOllama)
            payload.ollama_url = endpointInput.text.trim();
        // Only touch the keyring when a key was typed; an empty field never
        // wipes the stored one (that is what "Remove key" is for).
        if (keyInput.text.trim().length > 0)
            payload.api_key = keyInput.text.trim();
        root.status = "saving";
        GeminiChat.saveSettings(payload);
    }

    function addRule(action: string): void {
        const pat = ruleInput.text.trim();
        if (!pat)
            return;
        GeminiChat.setPermission(pat, action);
        ruleInput.text = "";
    }

    function setSwatch(index: int, colour: string): void {
        const g = root.gradient.slice();
        g[index] = colour;
        root.gradient = g;
    }

    onVisibleChanged: {
        if (visible) {
            root.status = "";
            GeminiChat.loadPermissions();
        }
    }

    Component.onCompleted: root.reset()

    Connections {
        target: GeminiChat

        function onSettingsDataChanged() {
            root.reset();
        }

        function onSettingsSaved(ok, error) {
            root.status = ok ? "saved" : error;
            root.statusOk = ok;
            statusTimer.restart();
        }

        function onSettingsValidated(result) {
            if (result.valid) {
                validationLabel.text = result.models !== undefined
                    ? qsTr("Key works • %1 models available").arg(result.models)
                    : qsTr("Key works");
                validationLabel.color = root.ok;
            } else {
                validationLabel.text = result.error;
                validationLabel.color = root.bad;
            }
        }
    }

    Timer {
        id: statusTimer

        interval: 4000
        onTriggered: {
            if (root.status === "saved")
                root.status = "";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Tokens.padding.small
        spacing: Tokens.spacing.medium

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: 36
                implicitHeight: 36
                radius: Tokens.rounding.full
                color: backArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    fontStyle: Tokens.font.icon.medium
                    color: Colours.palette.m3onSurface
                }

                MouseArea {
                    id: backArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tab.toggleSettings()
                }
            }

            StyledText {
                text: qsTr("Settings")
                font: Tokens.font.body.builders.large.size(20).weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }

            Item {
                Layout.fillWidth: true
            }

            // Which provider these settings belong to
            Rectangle {
                implicitWidth: providerRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 30
                radius: 15
                color: Qt.alpha(root.accent, 0.12)

                Row {
                    id: providerRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    GeminiLogo {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 16
                        implicitHeight: 16
                        shape: root.tab.providerShape
                        color: root.accent
                        tint: root.accent
                        tintAmount: 1
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tab.providerLabel
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        color: root.accent
                    }
                }
            }
        }

        // ── Nav + page ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.large

            ColumnLayout {
                // A nested layout fills by default; keep the nav a fixed strip
                Layout.fillWidth: false
                Layout.preferredWidth: 168
                Layout.maximumWidth: 168
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 2

                Repeater {
                    model: root.sections

                    delegate: Rectangle {
                        id: navItem

                        required property int index
                        required property var modelData

                        readonly property bool current: root.section === index

                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Tokens.rounding.medium
                        color: current ? Qt.alpha(root.accent, 0.14) : (navArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent")

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 18
                            radius: 2
                            color: root.accent
                            visible: navItem.current
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: navItem.modelData.icon
                                fontStyle: Tokens.font.icon.small
                                color: navItem.current ? root.accent : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: navItem.modelData.label
                                font: navItem.current
                                    ? Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                    : Tokens.font.body.medium
                                color: navItem.current ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: navArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.section = navItem.index
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.section

                // ── Connection ────────────────────────────────
                Page {
                    PageTitle {
                        title: qsTr("Connection")
                        subtitle: GeminiChat.providerInfo?.help ?? ""
                    }

                    // Key status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: (!root.needsKey || root.sd?.api_key_set) ? root.ok : Colours.palette.m3outline
                        }

                        StyledText {
                            text: {
                                if (!root.needsKey)
                                    return qsTr("No key needed — the models run on this machine");
                                if (!root.sd?.api_key_set)
                                    return qsTr("No key stored — %1 will not answer until one is set").arg(root.tab.providerLabel);
                                switch (root.sd?.api_key_source) {
                                case "env":
                                    return qsTr("Key taken from the %1 environment variable").arg(root.sd?.api_key_env ?? "");
                                case "memory":
                                    return qsTr("Key set for this run only — the keyring is unavailable");
                                default:
                                    return qsTr("A key is stored in the system keyring");
                                }
                            }
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    FieldLabel {
                        visible: root.needsKey
                        text: root.sd?.api_key_set ? qsTr("Replace API key") : qsTr("API key")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Field {
                            Layout.fillWidth: true
                            visible: root.needsKey
                            focused: keyInput.activeFocus

                            TextInput {
                                id: keyInput

                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.medium
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.medium
                                clip: true
                                selectByMouse: true
                                echoMode: TextInput.Password

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !keyInput.text && !keyInput.activeFocus
                                    text: root.sd?.key_placeholder ?? "..."
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3outline
                                }
                            }
                        }

                        IconChip {
                            visible: root.needsKey
                            icon: keyInput.echoMode === TextInput.Password ? "visibility" : "visibility_off"
                            tip: keyInput.echoMode === TextInput.Password ? qsTr("Show") : qsTr("Hide")
                            onClicked: keyInput.echoMode = keyInput.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password
                        }

                        SmallButton {
                            // Nothing to type for a local provider: the test
                            // just asks whether its server answers.
                            Layout.alignment: root.needsKey ? Qt.AlignVCenter : Qt.AlignLeft
                            label: root.needsKey ? qsTr("Test") : qsTr("Test connection")
                            enabled: !root.needsKey || keyInput.text.trim().length > 0
                            onClicked: {
                                validationLabel.text = qsTr("Checking…");
                                validationLabel.color = Colours.palette.m3onSurfaceVariant;
                                GeminiChat.validateSettings(keyInput.text.trim(), endpointInput.text.trim());
                            }
                        }
                    }

                    StyledText {
                        id: validationLabel

                        Layout.fillWidth: true
                        visible: text.length > 0
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                    }

                    // Two clicks to forget the stored key: the first one arms
                    // the button, the second confirms.
                    SmallButton {
                        id: removeKey

                        property bool armed: false

                        visible: root.needsKey && !!root.sd?.api_key_set
                        label: armed ? qsTr("Click again to remove the stored key") : qsTr("Remove stored key")
                        borderColour: armed ? root.bad : Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
                        labelColour: armed ? root.bad : Colours.palette.m3onSurface
                        onClicked: {
                            if (!armed) {
                                armed = true;
                                disarm.restart();
                                return;
                            }
                            armed = false;
                            root.status = "saving";
                            GeminiChat.saveSettings({ api_key: "" });
                        }

                        Timer {
                            id: disarm

                            interval: 4000
                            onTriggered: removeKey.armed = false
                        }
                    }

                    Divider {}

                    FieldLabel {
                        text: root.tab.isGemini ? qsTr("Worker URL") : root.tab.isOllama ? qsTr("Ollama endpoint") : qsTr("API endpoint")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Field {
                            Layout.fillWidth: true
                            focused: endpointInput.activeFocus
                            opacity: endpointInput.readOnly ? 0.7 : 1

                            TextInput {
                                id: endpointInput

                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.medium
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.medium
                                clip: true
                                selectByMouse: true
                                readOnly: root.tab.isGemini

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !endpointInput.text && !endpointInput.activeFocus
                                    text: root.tab.isGemini ? qsTr("not set — Google is called directly") : root.tab.isOllama ? "http://127.0.0.1:11434" : "https://…"
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3outline
                                }
                            }
                        }

                        SmallButton {
                            visible: !root.tab.isGemini
                            label: qsTr("Default")
                            enabled: endpointInput.text.trim() !== root.endpointDefault
                            onClicked: endpointInput.text = root.endpointDefault
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.tab.isGemini
                            ? qsTr("An optional Cloudflare worker that proxies Gemini. It is read from ~/.config/prism/config.json at daemon start and cannot be changed here.")
                            : root.tab.isOllama
                                ? qsTr("Where the local Ollama server listens. Only a loopback address is accepted here; a server on another machine goes into ~/.config/prism/config.json.")
                                : qsTr("Only the vendor's own https host is accepted here; a proxy for a blocked region goes into ~/.config/prism/config.json.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                        opacity: 0.8
                    }
                }

                // ── Behaviour ─────────────────────────────────
                Page {
                    PageTitle {
                        title: qsTr("Behaviour")
                        subtitle: qsTr("The system instruction is sent with every request and shapes how %1 answers.").arg(root.tab.providerLabel)
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        FieldLabel {
                            text: qsTr("System instruction")
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: qsTr("%1 / 20000").arg(sysInput.length)
                            font: Tokens.font.label.small
                            color: sysInput.length > 20000 ? root.bad : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    Field {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        focused: sysInput.activeFocus

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
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
                            }
                        }
                    }

                    RowLayout {
                        spacing: Tokens.spacing.small

                        SmallButton {
                            label: qsTr("Restore default")
                            enabled: sysInput.text !== (root.sd?.system_instruction_default ?? "")
                            onClicked: sysInput.text = root.sd?.system_instruction_default ?? ""
                        }

                        SmallButton {
                            label: qsTr("Clear")
                            enabled: sysInput.length > 0
                            onClicked: sysInput.text = ""
                        }
                    }
                }

                // ── Appearance ────────────────────────────────
                Page {
                    PageTitle {
                        title: qsTr("Appearance")
                        subtitle: qsTr("The glow drawn around the screen while %1 is looking at it.").arg(root.tab.providerLabel)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: qsTr("Glow overlay")
                                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: glowToggle.checked ? qsTr("Shown during screen analysis") : qsTr("Off")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        StyledSwitch {
                            id: glowToggle
                        }
                    }

                    Divider {}

                    SliderRow {
                        id: sigmaSlider

                        label: qsTr("Spread")
                        hint: qsTr("how far the glow reaches into the screen")
                        from: 16
                        to: 128
                        stepSize: 4
                    }

                    SliderRow {
                        id: alphaSlider

                        label: qsTr("Opacity")
                        from: 0.05
                        to: 1.0
                        stepSize: 0.05
                        decimals: 2
                    }

                    Divider {}

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: qsTr("Intro sweep")
                                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                text: sweepToggle.checked ? qsTr("The frame draws itself in round the edges") : qsTr("Off, the frame just fades in")
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        StyledSwitch {
                            id: sweepToggle
                        }
                    }

                    SliderRow {
                        id: sweepSlider

                        enabled: sweepToggle.checked
                        opacity: enabled ? 1 : 0.5
                        label: qsTr("Sweep duration")
                        hint: qsTr("ms")
                        from: 300
                        to: 3000
                        stepSize: 100
                    }

                    Divider {}

                    RowLayout {
                        Layout.fillWidth: true

                        FieldLabel {
                            text: qsTr("Gradient")
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        SmallButton {
                            label: qsTr("Provider default")
                            enabled: root.gradient.join(",") !== (root.sd?.glow_default_gradient ?? []).join(",")
                            onClicked: root.gradient = (root.sd?.glow_default_gradient ?? []).slice()
                        }
                    }

                    // Live preview of the stops
                    Canvas {
                        id: gradientPreview

                        // Repaint whenever a stop changes
                        property var stops: root.gradient

                        Layout.fillWidth: true
                        implicitHeight: 14
                        onStopsChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            const g = root.gradient;
                            if (!g || g.length === 0)
                                return;
                            const grad = ctx.createLinearGradient(0, 0, width, 0);
                            for (let i = 0; i < g.length; i++)
                                grad.addColorStop(g.length > 1 ? i / (g.length - 1) : 0, g[i]);
                            ctx.fillStyle = grad;
                            ctx.beginPath();
                            ctx.roundedRect(0, 0, width, height, 7, 7);
                            ctx.fill();
                        }
                        onWidthChanged: requestPaint()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: root.gradient

                            delegate: Rectangle {
                                id: swatch

                                required property int index
                                required property string modelData

                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: Tokens.rounding.medium
                                color: swatchArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: swatch.modelData
                                    border.width: 1
                                    border.color: Qt.alpha(Colours.palette.m3outline, 0.4)
                                }

                                MouseArea {
                                    id: swatchArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Click cycles a small palette; right-click goes back
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        const palette = root.swatchPalette;
                                        const cur = swatch.modelData.toLowerCase();
                                        let idx = palette.indexOf(cur);
                                        const step = mouse.button === Qt.RightButton ? -1 : 1;
                                        idx = idx < 0 ? 0 : (idx + step + palette.length) % palette.length;
                                        root.setSwatch(swatch.index, palette[idx]);
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Click a stop to cycle colours, right-click to go back.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        opacity: 0.8
                    }
                }

                // ── Permissions ───────────────────────────────
                Page {
                    PageTitle {
                        title: qsTr("Permissions")
                        subtitle: qsTr("Rules for the run_bash tool. Allow rules run a matching command without asking; deny rules refuse it without asking. Everything else prompts you. Only read-only commands can be allowed, and dangerous or network commands never.")
                    }

                    // Add a rule by hand
                    FieldLabel {
                        text: qsTr("New rule")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        Field {
                            Layout.fillWidth: true
                            focused: ruleInput.activeFocus

                            TextInput {
                                id: ruleInput

                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.medium
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.mono.medium
                                clip: true
                                selectByMouse: true
                                onAccepted: {
                                    if (text.trim().length > 0)
                                        root.addRule("allow");
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !ruleInput.text && !ruleInput.activeFocus
                                    text: qsTr("pattern, e.g.  ls *   or   ping *")
                                    font: Tokens.font.mono.medium
                                    color: Colours.palette.m3outline
                                }
                            }
                        }

                        SmallButton {
                            label: qsTr("Allow")
                            enabled: ruleInput.text.trim().length > 0
                            onClicked: root.addRule("allow")
                        }

                        SmallButton {
                            label: qsTr("Deny")
                            borderColour: root.bad
                            labelColour: root.bad
                            enabled: ruleInput.text.trim().length > 0
                            onClicked: root.addRule("deny")
                        }
                    }

                    StyledText {
                        id: ruleError

                        Layout.fillWidth: true
                        visible: text.length > 0
                        font: Tokens.font.body.small
                        color: root.bad
                        wrapMode: Text.Wrap

                        Connections {
                            target: GeminiChat

                            function onPermissionError(error) {
                                ruleError.text = error;
                            }

                            function onPermissionsChanged() {
                                ruleError.text = "";
                            }
                        }
                    }

                    Divider {}

                    StyledText {
                        Layout.fillWidth: true
                        visible: GeminiChat.permissions.length === 0
                        text: qsTr("No rules yet. Answer “Allow always” in a prompt, or add one above.")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    Repeater {
                        model: GeminiChat.permissions

                        delegate: Rectangle {
                            id: permRow

                            required property var modelData

                            readonly property bool allow: modelData.action !== "deny"

                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainerHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                // Action badge; click flips allow <-> deny
                                Rectangle {
                                    implicitWidth: badgeLabel.implicitWidth + 16
                                    implicitHeight: 24
                                    radius: 12
                                    color: permRow.allow ? Qt.alpha(root.accent, 0.16) : Qt.alpha(root.bad, 0.16)

                                    StyledText {
                                        id: badgeLabel

                                        anchors.centerIn: parent
                                        text: permRow.allow ? qsTr("allow") : qsTr("deny")
                                        font: Tokens.font.mono.small
                                        color: permRow.allow ? root.accent : root.bad
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: GeminiChat.setPermission(permRow.modelData.pattern, permRow.allow ? "deny" : "allow")
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: permRow.modelData.pattern
                                    font: Tokens.font.mono.medium
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideMiddle
                                }

                                StyledText {
                                    visible: permRow.modelData.added > 0
                                    text: new Date(permRow.modelData.added * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    opacity: 0.7
                                }

                                IconChip {
                                    icon: "close"
                                    tip: qsTr("Remove rule")
                                    onClicked: GeminiChat.revokePermission(permRow.modelData.pattern)
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        text: qsTr("Patterns match the whole command, shell-glob style: “ls *” covers every ls invocation, “wc -l README.md” only that command. Click a badge to flip a rule between allow and deny.")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                        opacity: 0.8
                    }
                }
            }
        }

        // ── Save bar ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (root.status === "saving")
                        return qsTr("Saving…");
                    if (root.status === "saved")
                        return qsTr("Saved");
                    if (root.status !== "")
                        return root.status;
                    return root.dirty ? qsTr("Unsaved changes") : "";
                }
                font: Tokens.font.body.small
                color: root.status === "saved" ? root.ok : (root.status !== "" && root.status !== "saving" ? root.bad : Colours.palette.m3onSurfaceVariant)
                elide: Text.ElideRight
            }

            SmallButton {
                label: qsTr("Discard")
                visible: root.dirty
                onClicked: root.reset()
            }

            StyledRect {
                implicitWidth: saveRow.implicitWidth + Tokens.padding.large * 2
                implicitHeight: 38
                radius: Tokens.rounding.medium
                color: root.dirty ? (saveArea.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent) : Colours.tPalette.m3surfaceContainerHigh

                Row {
                    id: saveRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "check"
                        fontStyle: Tokens.font.icon.small
                        color: root.dirty ? "#ffffff" : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Save changes")
                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                        color: root.dirty ? "#ffffff" : Colours.palette.m3onSurfaceVariant
                    }
                }

                MouseArea {
                    id: saveArea

                    anchors.fill: parent
                    enabled: root.dirty
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.save()
                }
            }
        }
    }

    // ── Building blocks ───────────────────────────────────────────
    // Inline components do not see the file's ids, so they read the
    // provider colour from the GeminiChat singleton rather than `root`.

    // One settings page: a scrolling column
    component Page: Flickable {
        id: page

        default property alias content: pageCol.data

        contentHeight: pageCol.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: pageCol

            width: page.width
            spacing: Tokens.spacing.medium
        }
    }

    component PageTitle: ColumnLayout {
        id: pageTitle

        required property string title
        property string subtitle: ""

        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.small
        spacing: 4

        StyledText {
            text: pageTitle.title
            font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            color: Colours.palette.m3onSurface
        }

        StyledText {
            Layout.fillWidth: true
            visible: pageTitle.subtitle.length > 0
            text: pageTitle.subtitle
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }
    }

    component FieldLabel: StyledText {
        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
        color: Colours.palette.m3onSurfaceVariant
    }

    component Field: Rectangle {
        property bool focused: false

        implicitHeight: 40
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh
        border.width: 1
        border.color: focused ? Qt.alpha(GeminiChat.providerPrimary, 0.6) : "transparent"

        Behavior on border.color {
            ColorAnimation {
                duration: 150
            }
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.small
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
        opacity: 0.4
    }

    // Small outlined text button
    component SmallButton: Rectangle {
        id: sb

        required property string label
        property color borderColour: Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
        property color labelColour: Colours.palette.m3onSurface

        signal clicked()

        implicitWidth: sbLabel.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 32
        radius: Tokens.rounding.medium
        color: sbArea.containsMouse && enabled ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
        border.width: 1
        border.color: sb.borderColour
        opacity: enabled ? 1 : 0.45

        StyledText {
            id: sbLabel

            anchors.centerIn: parent
            text: sb.label
            font: Tokens.font.body.small
            color: sb.labelColour
        }

        MouseArea {
            id: sbArea

            anchors.fill: parent
            enabled: sb.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    // Square icon button with a tooltip-ish accessible name
    component IconChip: Rectangle {
        id: chip

        required property string icon
        property string tip: ""

        signal clicked()

        implicitWidth: 36
        implicitHeight: 36
        radius: Tokens.rounding.medium
        color: chipArea.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: chip.icon
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3onSurfaceVariant
        }

        MouseArea {
            id: chipArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component SliderRow: ColumnLayout {
        id: sliderRow

        required property string label
        property string hint: ""
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property alias value: slider.value
        property int decimals: 0

        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: sliderRow.label
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                visible: sliderRow.hint.length > 0
                text: "· " + sliderRow.hint
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                opacity: 0.7
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: slider.value.toFixed(sliderRow.decimals)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurface
            }
        }

        StyledSlider {
            id: slider

            Layout.fillWidth: true
            fgColour: GeminiChat.providerPrimary
            // StyledSlider only reports a 0..1 position; snap it onto the scale ourselves
            onInteraction: v => value = from + Math.round(v * (to - from) / stepSize) * stepSize
        }
    }
}
