import QtQuick
import Caelestia.Config
import skiffuff.prism.theme

// Text in the shell's body font and on-surface colour, with the colour
// animated like the shell's StyledText does.
Text {
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: Colours.palette.m3onSurface
    font: Tokens.font.body.small

    Behavior on color {
        ColorAnimation {
            duration: 200
            easing.type: Easing.OutQuad
        }
    }
}
