import QtQuick
import QtQuick.Effects
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

                // Final state: one solid frame of the flowing provider
                // gradient, blurred so it scatters inward as a single soft glow
                Item {
                    id: bloom

                    anchors.fill: parent
                    opacity: Math.min(1, content.u * 1.5) * (GeminiChat.settingsData?.glow?.alpha ?? 0.8)

                    // Solid band width; the blur pushes the glow ~2x further in
                    readonly property real spread: GeminiChat.settingsData?.glow?.sigma ?? 64

                    Shape {
                        id: frame

                        anchors.fill: parent
                        visible: false
                        preferredRendererType: Shape.GeometryRenderer
                        asynchronous: false

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

                            startX: 0
                            startY: 0
                            PathLine { x: content.width; y: 0 }
                            PathLine { x: content.width; y: content.height }
                            PathLine { x: 0; y: content.height }
                            PathLine { x: 0; y: 0 }

                            PathMove { x: bloom.spread; y: bloom.spread }
                            PathLine { x: content.width - bloom.spread; y: bloom.spread }
                            PathLine { x: content.width - bloom.spread; y: content.height - bloom.spread }
                            PathLine { x: bloom.spread; y: content.height - bloom.spread }
                            PathLine { x: bloom.spread; y: bloom.spread }
                        }
                    }

                    MultiEffect {
                        anchors.fill: frame
                        source: frame
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blur: 1
                        blurMax: 64
                        blurMultiplier: Math.max(0, bloom.spread / 32 - 1)
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
