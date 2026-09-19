import QtQuick
import QtQuick.Shapes

// Soft elliptical glow in the brand colour, like the blue halo behind the
// prompt on gemini.google.com. Fades in and out with `visible`.
Item {
    id: root

    property color colour: "#4285F4"

    opacity: visible ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 600
            easing.type: Easing.InOutSine
        }
    }

    // A square radial gradient stretched to the item's aspect ratio.
    Shape {
        id: disc

        readonly property real side: root.height

        width: side
        height: side
        anchors.centerIn: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            origin.x: disc.side / 2
            origin.y: disc.side / 2
            xScale: root.height > 0 ? root.width / root.height : 1
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"

            fillGradient: RadialGradient {
                centerX: disc.side / 2
                centerY: disc.side / 2
                focalX: disc.side / 2
                focalY: disc.side / 2
                centerRadius: disc.side / 2

                GradientStop {
                    position: 0
                    color: Qt.alpha(root.colour, 0.32)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.alpha(root.colour, 0.112)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }

            startX: 0
            startY: 0

            PathLine {
                x: disc.side
                y: 0
            }
            PathLine {
                x: disc.side
                y: disc.side
            }
            PathLine {
                x: 0
                y: disc.side
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }
}
