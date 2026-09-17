import QtQuick
import QtQuick.Templates
import Caelestia.Config
import skiffuff.prism.theme

// Material-style switch: a pill track and a knob that slides and grows a
// little while pressed.
Switch {
    id: root

    implicitWidth: implicitIndicatorWidth
    implicitHeight: implicitIndicatorHeight

    indicator: StyledRect {
        implicitWidth: implicitHeight * 1.7
        implicitHeight: Tokens.font.body.medium.pointSize + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: root.checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest
        border.width: root.checked ? 0 : 2
        border.color: Colours.palette.m3outline

        StyledRect {
            readonly property real knob: root.pressed ? parent.implicitHeight * 0.9 : root.checked ? parent.implicitHeight * 0.75 : parent.implicitHeight * 0.5

            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.implicitWidth - width - (parent.implicitHeight - height) / 2 : (parent.implicitHeight - height) / 2
            implicitWidth: knob
            implicitHeight: knob
            radius: Tokens.rounding.full
            color: root.checked ? Colours.palette.m3onPrimary : Colours.palette.m3outline

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 120
                }
            }
            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 120
                }
            }
        }
    }
}
