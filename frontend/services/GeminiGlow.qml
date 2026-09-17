pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Drives GeminiGlowOverlay. `tabActive` is set by the dashboard while the
// Prism tab is showing (the hook shell-patch.py adds to Content.qml);
// `flagActive` mirrors the /tmp/gemini_glow_active flag that older setups and
// the daemon's screen watching still write.
Singleton {
    id: root

    property bool tabActive: false
    property bool flagActive: false
    readonly property bool active: tabActive || flagActive

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            if (!checkProc.running)
                checkProc.running = true;
        }
    }

    Process {
        id: checkProc

        command: ["test", "-f", "/tmp/gemini_glow_active"]
        onExited: code => {
            root.flagActive = (code === 0);
        }
    }
}
