import QtQuick

// Rectangle whose colour changes fade instead of snapping.
Rectangle {
    color: "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 200
            easing.type: Easing.OutQuad
        }
    }
}
