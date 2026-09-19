import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "gemini-glow"

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Fully click-through
            mask: Region {}

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Item {
                id: content

                anchors.fill: parent

                // Visible only when the tab is open, the glow setting is on,
                // and no fullscreen game is grabbing the GPU (or watching is active)
                readonly property bool showGlow: (GeminiGlow.active && !content.gameFocused && GeminiChat.glowEnabled) || GeminiChat.watchActive

                opacity: content.showGlow ? 1 : 0

                // Shared rotation angle for the flowing Gemini gradient
                property real flowAngle: 0

                // Pause everything while a game has focus => free GPU for it
                readonly property bool gameFocused: {
                    const t = Hypr.activeToplevel;
                    const c = t?.class ?? "";
                    return !!t?.fullscreen || /cs2|gamescope|steam_app/i.test(c);
                }

                // Intro sweep progress: 0 = nothing, 1 = heads met at bottom center
                property real u: 1

                // Comet color, shimmering through the active provider palette
                property color headColor: GeminiChat.providerPrimary

                Behavior on headColor {
                    // Smooth provider recolour after the intro sweep is over
                    enabled: content.u >= 1

                    ColorAnimation {
                        duration: 400
                        easing.type: Easing.InOutSine
                    }
                }

                readonly property real halfLen: height + width / 2
                readonly property real s: u * halfLen
                readonly property real wallH: Math.min(s, height)
                readonly property real botW: Math.min(width / 2, Math.max(0, s - height))

                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                SequentialAnimation {
                    running: content.showGlow
                    loops: Animation.Infinite

                    NumberAnimation {
                        target: content
                        property: "flowAngle"
                        from: 0
                        to: 360
                        duration: 6000
                    }
                }

                NumberAnimation {
                    id: sweepAnim
                    target: content
                    property: "u"
                    from: 0
                    to: 1
                    duration: 900
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation on headColor {
                    running: content.showGlow && content.u < 1
                    loops: Animation.Infinite

                    ColorAnimation { to: GeminiChat.providerSecondary; duration: 300 }
                    ColorAnimation { to: GeminiChat.providerTertiary; duration: 300 }
                    ColorAnimation { to: GeminiChat.providerPrimary; duration: 300 }
                }

                Connections {
                    target: GeminiGlow

                    function onActiveChanged() {
                        if (GeminiGlow.active) {
                            content.u = 0;
                            sweepAnim.restart();
                        }
                    }
                }

                Component.onCompleted: {
                    if (GeminiGlow.active) {
                        content.u = 0;
                        sweepAnim.restart();
                    }
                }

                // Final state: soft gaussian bloom (60 rings),
                // shimmering with the official Gemini logo gradient
                Item {
                    id: bloom

                    anchors.fill: parent
                    opacity: Math.min(1, content.u * 1.5)

                    Repeater {
                        model: GeminiChat.settingsData?.glow?.ring_count ?? 96

                        delegate: Shape {
                            id: ring

                            required property int modelData

                            readonly property real inset: modelData
                            readonly property real thickness: 2.4
                            readonly property real sigma: GeminiChat.settingsData?.glow?.sigma ?? 28
                            readonly property real ringAlpha: (GeminiChat.settingsData?.glow?.alpha ?? 0.42) * Math.exp(-Math.pow(modelData, 2) / (2 * ring.sigma * ring.sigma))

                            anchors.fill: parent
                            opacity: ringAlpha
                            preferredRendererType: Shape.GeometryRenderer
                            asynchronous: false

                            readonly property real w: content.width - inset * 2
                            readonly property real h: content.height - inset * 2
                            readonly property real r: 2
                            readonly property real ri: 0.75

                            ShapePath {
                                fillRule: ShapePath.OddEvenFill
                                strokeWidth: 0
                                strokeColor: "transparent"

                                fillGradient: ConicalGradient {
                                    centerX: content.width / 2
                                    centerY: content.height / 2
                                    angle: content.flowAngle

                                    GradientStop { position: 0.0; color: GeminiChat.providerGradient[0] ?? "#4285F4"
                                        Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.InOutSine } } }
                                    GradientStop { position: 0.35; color: GeminiChat.providerGradient[1] ?? "#9B72CB"
                                        Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.InOutSine } } }
                                    GradientStop { position: 0.7; color: GeminiChat.providerGradient[2] ?? "#D96570"
                                        Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.InOutSine } } }
                                    GradientStop { position: 1.0; color: GeminiChat.providerGradient[3] ?? "#4285F4"
                                        Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.InOutSine } } }
                                }

                                startX: ring.inset + ring.r
                                startY: ring.inset

                                PathLine { x: ring.inset + ring.w - ring.r; y: ring.inset }
                                PathArc { x: ring.inset + ring.w; y: ring.inset + ring.r; radiusX: ring.r; radiusY: ring.r }
                                PathLine { x: ring.inset + ring.w; y: ring.inset + ring.h - ring.r }
                                PathArc { x: ring.inset + ring.w - ring.r; y: ring.inset + ring.h; radiusX: ring.r; radiusY: ring.r }
                                PathLine { x: ring.inset + ring.r; y: ring.inset + ring.h }
                                PathArc { x: ring.inset; y: ring.inset + ring.h - ring.r; radiusX: ring.r; radiusY: ring.r }
                                PathLine { x: ring.inset; y: ring.inset + ring.r }
                                PathArc { x: ring.inset + ring.r; y: ring.inset; radiusX: ring.r; radiusY: ring.r }

                                PathMove { x: ring.inset + ring.thickness + ring.ri; y: ring.inset + ring.thickness }
                                PathLine { x: ring.inset + ring.w - ring.thickness - ring.ri; y: ring.inset + ring.thickness }
                                PathArc { x: ring.inset + ring.w - ring.thickness; y: ring.inset + ring.thickness + ring.ri; radiusX: ring.ri; radiusY: ring.ri }
                                PathLine { x: ring.inset + ring.w - ring.thickness; y: ring.inset + ring.h - ring.thickness - ring.ri }
                                PathArc { x: ring.inset + ring.w - ring.thickness - ring.ri; y: ring.inset + ring.h - ring.thickness; radiusX: ring.ri; radiusY: ring.ri }
                                PathLine { x: ring.inset + ring.thickness + ring.ri; y: ring.inset + ring.h - ring.thickness }
                                PathArc { x: ring.inset + ring.thickness; y: ring.inset + ring.h - ring.thickness - ring.ri; radiusX: ring.ri; radiusY: ring.ri }
                                PathLine { x: ring.inset + ring.thickness; y: ring.inset + ring.thickness + ring.ri }
                                PathArc { x: ring.inset + ring.thickness + ring.ri; y: ring.inset + ring.thickness; radiusX: ring.ri; radiusY: ring.ri }
                            }
                        }
                    }
                }

                // Intro comets: bright cores + soft halos, revealed by growing
                // clip windows so they travel STRICTLY along the screen edges,
                // through the corners, meeting at bottom center
                Item {
                    id: heads

                    anchors.fill: parent
                    visible: content.u < 1
                    opacity: content.u < 1 ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Right wall segment
                    CometEdge {
                        x: content.width - 6
                        y: 0
                        width: 6
                        height: Math.max(0, content.wallH + 2)
                        headColor: content.headColor
                        canvasWidth: content.width
                        canvasHeight: content.height
                        x1: content.width / 2; y1: 1.5
                        x2: content.width - 1.5; y2: 1.5
                        x3: content.width - 1.5; y3: content.height - 1.5
                    }

                    // Right bottom segment
                    CometEdge {
                        x: content.width - content.botW - 2
                        y: content.height - 6
                        width: Math.max(0, content.botW + 2)
                        height: 6
                        headColor: content.headColor
                        canvasWidth: content.width
                        canvasHeight: content.height
                        x1: content.width - 1.5; y1: content.height - 1.5
                        x3: content.width / 2; y3: content.height - 1.5
                    }

                    // Left wall segment
                    CometEdge {
                        x: 0
                        y: 0
                        width: 6
                        height: Math.max(0, content.wallH + 2)
                        headColor: content.headColor
                        canvasWidth: content.width
                        canvasHeight: content.height
                        x1: content.width / 2; y1: 1.5
                        x2: 1.5; y2: 1.5
                        x3: 1.5; y3: content.height - 1.5
                    }

                    // Left bottom segment
                    CometEdge {
                        x: 0
                        y: content.height - 6
                        width: Math.max(0, content.botW + 2)
                        height: 6
                        headColor: content.headColor
                        canvasWidth: content.width
                        canvasHeight: content.height
                        x1: 1.5; y1: content.height - 1.5
                        x3: content.width / 2; y3: content.height - 1.5
                    }

                    // One straight-or-cornered comet trail, clipped to its own
                    // Item rect; x2/y2 default to the start point, so a
                    // 2-point (bottom) segment just omits the corner.
                    component CometEdge: Item {
                        id: edge

                        required property color headColor
                        required property real canvasWidth
                        required property real canvasHeight
                        required property real x1
                        required property real y1
                        property real x2: x1
                        property real y2: y1
                        required property real x3
                        required property real y3

                        clip: true

                        Shape {
                            width: edge.canvasWidth
                            height: edge.canvasHeight
                            preferredRendererType: Shape.GeometryRenderer
                            asynchronous: false

                            ShapePath {
                                strokeWidth: 9
                                strokeColor: Qt.rgba(edge.headColor.r, edge.headColor.g, edge.headColor.b, 0.25)
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap

                                startX: edge.x1
                                startY: edge.y1
                                PathLine { x: edge.x2; y: edge.y2 }
                                PathLine { x: edge.x3; y: edge.y3 }
                            }

                            ShapePath {
                                strokeWidth: 3
                                strokeColor: edge.headColor
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap

                                startX: edge.x1
                                startY: edge.y1
                                PathLine { x: edge.x2; y: edge.y2 }
                                PathLine { x: edge.x3; y: edge.y3 }
                            }
                        }
                    }
                }
            }
        }
    }
}
