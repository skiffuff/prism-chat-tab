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

                // Intro sweep progress: the frame draws itself from top center,
                // both ways round the edges, meeting at bottom center (opt-in)
                property real u: 1
                readonly property bool sweepEnabled: GeminiChat.settingsData?.glow?.sweep ?? false

                function startSweep(): void {
                    if (!GeminiGlow.active || !content.sweepEnabled)
                        return;
                    content.u = 0;
                    sweepAnim.restart();
                }

                readonly property real s: u * (width + height)
                readonly property real topW: Math.min(width / 2, s)
                readonly property real wallH: Math.min(height, Math.max(0, s - width / 2))
                readonly property real botW: Math.min(width / 2, Math.max(0, s - width / 2 - height))

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
                    duration: GeminiChat.settingsData?.glow?.sweep_ms ?? 1200
                    easing.type: Easing.OutCubic
                }

                Connections {
                    target: GeminiGlow

                    function onActiveChanged() {
                        content.startSweep();
                    }
                }

                Component.onCompleted: content.startSweep()

                // One solid frame of the flowing provider
                // gradient, blurred so it scatters inward as a single soft glow
                Item {
                    id: bloom

                    anchors.fill: parent
                    opacity: (GeminiChat.settingsData?.glow?.alpha ?? 0.8)

                    // Solid band width; the blur pushes the glow ~2x further in
                    readonly property real spread: GeminiChat.settingsData?.glow?.sigma ?? 64

                    Shape {
                        id: frame

                        anchors.fill: parent
                        visible: false
                        preferredRendererType: Shape.GeometryRenderer
                        asynchronous: false

                        ShapePath {
                            fillRule: ShapePath.WindingFill
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

                            // The band as the part of each edge revealed so far
                            PathRectangle { x: content.width / 2 - content.topW; y: 0; width: content.topW; height: bloom.spread }
                            PathRectangle { x: content.width / 2; y: 0; width: content.topW; height: bloom.spread }
                            PathRectangle { x: 0; y: 0; width: bloom.spread; height: content.wallH }
                            PathRectangle { x: content.width - bloom.spread; y: 0; width: bloom.spread; height: content.wallH }
                            PathRectangle { x: 0; y: content.height - bloom.spread; width: content.botW; height: bloom.spread }
                            PathRectangle { x: content.width - content.botW; y: content.height - bloom.spread; width: content.botW; height: bloom.spread }
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
            }
        }
    }
}
