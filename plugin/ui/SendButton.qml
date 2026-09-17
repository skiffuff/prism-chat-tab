import QtQuick
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Round send button in the provider colour; grey while there is nothing to
// send. Bounces on click.
StyledRect {
    id: root

    property bool ready: false
    property int size: 38

    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: Tokens.rounding.full
    color: {
        if (!ready)
            return Colours.tPalette.m3surfaceContainer;
        return sendArea.containsMouse ? Qt.darker(GeminiChat.providerBubble, 1.1) : GeminiChat.providerBubble;
    }

    Behavior on scale {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutBack
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "arrow_upward"
        fontStyle: Tokens.font.icon.medium
        color: root.ready ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
    }

    SequentialAnimation {
        id: bounce

        NumberAnimation {
            target: root
            property: "scale"
            to: 0.75
            duration: 80
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root
            property: "scale"
            to: 1.0
            duration: 250
            easing.type: Easing.OutBack
        }
    }

    MouseArea {
        id: sendArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            bounce.restart();
            root.clicked();
        }
    }
}
