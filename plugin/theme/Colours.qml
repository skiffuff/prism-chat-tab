pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// The shell's colour scheme, read the same way the shell reads it: from
// ~/.local/state/caelestia/scheme.json, live. A plugin cannot import the
// shell's own QML (qs.services.Colours), so this is the plugin's copy of the
// small part of it the tab needs: the Material palette, the translucent
// variant that follows appearance.transparency, and the light/dark flag.
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

    property var colours: ({})
    property string scheme: ""
    property string flavour: ""
    property bool light: false

    readonly property Palette palette: Palette {}
    readonly property TPalette tPalette: TPalette {}

    function pick(name: string, fallback: string): color {
        const v = root.colours[name];
        return v ? (v.startsWith("#") ? v : "#" + v) : fallback;
    }

    // Same rule as the shell: with transparency on, surfaces take the base
    // alpha and stacked layers a lighter/darker tint of the layer alpha.
    function layer(c: color, layerIdx: int): color {
        const tr = Tokens.transparency;   // global, no screen needed
        if (!tr.enabled)
            return c;
        if (layerIdx === 0)
            return Qt.alpha(c, tr.base);
        const offset = (root.light ? -0.5 : 1) * (root.light ? 0.2 : 0.3) * (1 - tr.base);
        return Qt.alpha(Qt.rgba(
            Math.min(1, Math.max(0, c.r + offset)),
            Math.min(1, Math.max(0, c.g + offset)),
            Math.min(1, Math.max(0, c.b + offset)), 1), tr.layers);
    }

    function load(text: string): void {
        try {
            const s = JSON.parse(text);
            root.scheme = s.name ?? "";
            root.flavour = s.flavour ?? "";
            root.light = s.mode === "light";
            root.colours = s.colours ?? {};
        } catch (e) {
            console.warn("prism theme: could not parse scheme.json:", e);
        }
    }

    FileView {
        path: `${root.stateDir}/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text())
    }

    component Palette: QtObject {
        readonly property color m3background: root.pick("background", "#131318")
        readonly property color m3onBackground: root.pick("onBackground", "#e5e1e9")
        readonly property color m3surface: root.pick("surface", "#131318")
        readonly property color m3surfaceDim: root.pick("surfaceDim", "#131318")
        readonly property color m3surfaceBright: root.pick("surfaceBright", "#39383f")
        readonly property color m3surfaceContainerLowest: root.pick("surfaceContainerLowest", "#0e0e13")
        readonly property color m3surfaceContainerLow: root.pick("surfaceContainerLow", "#1c1b20")
        readonly property color m3surfaceContainer: root.pick("surfaceContainer", "#201f25")
        readonly property color m3surfaceContainerHigh: root.pick("surfaceContainerHigh", "#2a292f")
        readonly property color m3surfaceContainerHighest: root.pick("surfaceContainerHighest", "#35343a")
        readonly property color m3onSurface: root.pick("onSurface", "#e5e1e9")
        readonly property color m3onSurfaceVariant: root.pick("onSurfaceVariant", "#c9c4d0")
        readonly property color m3surfaceVariant: root.pick("surfaceVariant", "#47464f")
        readonly property color m3surfaceTint: root.pick("surfaceTint", "#c8bfff")
        readonly property color m3inverseSurface: root.pick("inverseSurface", "#e5e1e9")
        readonly property color m3inverseOnSurface: root.pick("inverseOnSurface", "#313036")
        readonly property color m3inversePrimary: root.pick("inversePrimary", "#5f52a7")
        readonly property color m3outline: root.pick("outline", "#928f99")
        readonly property color m3outlineVariant: root.pick("outlineVariant", "#47464f")
        readonly property color m3shadow: root.pick("shadow", "#000000")
        readonly property color m3scrim: root.pick("scrim", "#000000")
        readonly property color m3primary: root.pick("primary", "#c8bfff")
        readonly property color m3onPrimary: root.pick("onPrimary", "#301e75")
        readonly property color m3primaryContainer: root.pick("primaryContainer", "#473a8d")
        readonly property color m3onPrimaryContainer: root.pick("onPrimaryContainer", "#e5deff")
        readonly property color m3primaryFixed: root.pick("primaryFixed", "#e5deff")
        readonly property color m3primaryFixedDim: root.pick("primaryFixedDim", "#c8bfff")
        readonly property color m3onPrimaryFixed: root.pick("onPrimaryFixed", "#190062")
        readonly property color m3onPrimaryFixedVariant: root.pick("onPrimaryFixedVariant", "#473a8d")
        readonly property color m3primaryDim: root.pick("primaryDim", "#b0a6f0")
        readonly property color m3secondary: root.pick("secondary", "#c9c3dc")
        readonly property color m3onSecondary: root.pick("onSecondary", "#312e41")
        readonly property color m3secondaryContainer: root.pick("secondaryContainer", "#484459")
        readonly property color m3onSecondaryContainer: root.pick("onSecondaryContainer", "#e5dff9")
        readonly property color m3secondaryFixed: root.pick("secondaryFixed", "#e5dff9")
        readonly property color m3secondaryFixedDim: root.pick("secondaryFixedDim", "#c9c3dc")
        readonly property color m3onSecondaryFixed: root.pick("onSecondaryFixed", "#1c192b")
        readonly property color m3onSecondaryFixedVariant: root.pick("onSecondaryFixedVariant", "#484459")
        readonly property color m3secondaryDim: root.pick("secondaryDim", "#b2acc4")
        readonly property color m3tertiary: root.pick("tertiary", "#ecb8cd")
        readonly property color m3onTertiary: root.pick("onTertiary", "#482536")
        readonly property color m3tertiaryContainer: root.pick("tertiaryContainer", "#613b4c")
        readonly property color m3onTertiaryContainer: root.pick("onTertiaryContainer", "#ffd8e7")
        readonly property color m3tertiaryFixed: root.pick("tertiaryFixed", "#ffd8e7")
        readonly property color m3tertiaryFixedDim: root.pick("tertiaryFixedDim", "#ecb8cd")
        readonly property color m3onTertiaryFixed: root.pick("onTertiaryFixed", "#301121")
        readonly property color m3onTertiaryFixedVariant: root.pick("onTertiaryFixedVariant", "#613b4c")
        readonly property color m3tertiaryDim: root.pick("tertiaryDim", "#d3a2b6")
        readonly property color m3error: root.pick("error", "#ffb4ab")
        readonly property color m3onError: root.pick("onError", "#690005")
        readonly property color m3errorContainer: root.pick("errorContainer", "#93000a")
        readonly property color m3onErrorContainer: root.pick("onErrorContainer", "#ffdad6")
        readonly property color m3errorDim: root.pick("errorDim", "#e69e96")
        readonly property color m3success: root.pick("success", "#a6d395")
        readonly property color m3onSuccess: root.pick("onSuccess", "#123800")
        readonly property color m3successContainer: root.pick("successContainer", "#255100")
        readonly property color m3onSuccessContainer: root.pick("onSuccessContainer", "#c1f0ae")
    }

    component TPalette: QtObject {
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground, 1)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest, 1)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow, 1)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer, 1)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh, 1)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest, 1)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface, 1)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant, 1)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 1)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint, 1)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 1)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface, 1)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary, 1)
        readonly property color m3outline: root.layer(root.palette.m3outline, 1)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant, 1)
        readonly property color m3shadow: root.layer(root.palette.m3shadow, 1)
        readonly property color m3scrim: root.layer(root.palette.m3scrim, 1)
        readonly property color m3primary: root.layer(root.palette.m3primary, 1)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary, 1)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer, 1)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer, 1)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed, 1)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim, 1)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed, 1)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant, 1)
        readonly property color m3primaryDim: root.layer(root.palette.m3primaryDim, 1)
        readonly property color m3secondary: root.layer(root.palette.m3secondary, 1)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary, 1)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer, 1)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer, 1)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed, 1)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim, 1)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed, 1)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant, 1)
        readonly property color m3secondaryDim: root.layer(root.palette.m3secondaryDim, 1)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary, 1)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary, 1)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer, 1)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer, 1)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed, 1)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim, 1)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed, 1)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant, 1)
        readonly property color m3tertiaryDim: root.layer(root.palette.m3tertiaryDim, 1)
        readonly property color m3error: root.layer(root.palette.m3error, 1)
        readonly property color m3onError: root.layer(root.palette.m3onError, 1)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer, 1)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer, 1)
        readonly property color m3errorDim: root.layer(root.palette.m3errorDim, 1)
        readonly property color m3success: root.layer(root.palette.m3success, 1)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess, 1)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer, 1)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer, 1)
    }
}
