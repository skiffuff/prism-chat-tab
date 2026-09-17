import QtQuick
import Caelestia.Config
import skiffuff.prism.theme

// A Material Symbols glyph. `fontStyle` picks the size/weight token, `fill`
// the filled variant (0–1); the grade follows light/dark like the shell.
StyledText {
    property real fill: 0
    property int grade: Colours.light ? 0 : -25
    property font fontStyle: Tokens.font.icon.small

    font: Tokens.font.icon.size(fontStyle.pointSize).weight(fontStyle.weight).vaxes(fontStyle.variableAxes).fill(fill.toFixed(1)).grade(grade).build()
}
