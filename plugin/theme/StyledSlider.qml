import QtQuick
import QtQuick.Templates
import Caelestia.Config
import skiffuff.prism.theme

// Material-style slider: a filled track in `fgColour`, a quiet remainder and
// a thin handle that stretches while dragging.
Slider {
    id: root

    property color fgColour: Colours.palette.m3primary
    property color bgColour: Colours.palette.m3secondaryContainer
    property int radius: Tokens.rounding.medium

    implicitWidth: 200
    implicitHeight: 12

    background: Item {
        anchors.fill: parent

        StyledRect {
            id: filled

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, root.handle.x - Tokens.spacing.extraSmall)
            height: parent.height
            radius: root.radius
            color: root.fgColour
        }

        StyledRect {
            // the handle lives outside the background item, so position by x
            x: root.handle.x + root.handle.width + Tokens.spacing.extraSmall
            width: Math.max(0, parent.width - x)
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: root.radius
            color: root.bgColour
        }
    }

    handle: StyledRect {
        x: root.visualPosition * (root.availableWidth - width)
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 4
        implicitHeight: root.pressed ? root.height * 2.6 : root.height * 2
        radius: Tokens.rounding.full
        color: root.fgColour

        Behavior on implicitHeight {
            NumberAnimation {
                duration: 120
            }
        }
    }
}
