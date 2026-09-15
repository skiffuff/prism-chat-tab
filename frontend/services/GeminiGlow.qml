pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    Timer {
        interval: 150
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
            root.active = (code === 0);
        }
    }
}
