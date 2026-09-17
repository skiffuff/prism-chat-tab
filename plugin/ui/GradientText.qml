import QtQuick
import skiffuff.prism.ui

// One line of text filled with a horizontal three-stop gradient.
//
// Drawn on a Canvas rather than by masking a gradient with a text layer: the
// layer of an invisible mask item is refreshed unreliably, so the old
// approach showed nothing after the greeting changed. Here the glyphs and the
// gradient are painted together in one deterministic pass.
Canvas {
    id: root

    property string text: ""
    property font font
    property color c0: "#4285F4"
    property color c1: "#9B72CB"
    property color c2: "#D96570"

    // Room for glyphs that overhang their advance (italics, swashes)
    readonly property int pad: 4

    implicitWidth: Math.ceil(metrics.advanceWidth) + pad * 2
    implicitHeight: Math.ceil(fontMetrics.height) + pad

    antialiasing: true
    renderStrategy: Canvas.Cooperative

    TextMetrics {
        id: metrics

        font: root.font
        text: root.text
    }

    FontMetrics {
        id: fontMetrics

        font: root.font
    }

    onTextChanged: requestPaint()
    onFontChanged: requestPaint()
    onC0Changed: requestPaint()
    onC1Changed: requestPaint()
    onC2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // Context2D rejects the whole font shorthand when the family is unknown
    // to it, so resolve the family once and fall back to the generic sans.
    readonly property string canvasFamily: {
        const fam = root.font.family;
        return fam && Qt.fontFamilies().indexOf(fam) >= 0 ? `"${fam}"` : "sans-serif";
    }

    function cssFont(): string {
        // Canvas takes a CSS font shorthand; Qt fonts carry point sizes.
        const px = root.font.pixelSize > 0 ? root.font.pixelSize : root.font.pointSize * 96 / 72;
        const style = root.font.italic ? "italic " : "";
        return `${style}${root.font.weight} ${Math.round(px)}px ${root.canvasFamily}`;
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        if (!root.text)
            return;
        const grad = ctx.createLinearGradient(pad, 0, width - pad, 0);
        grad.addColorStop(0, root.c0);
        grad.addColorStop(0.5, root.c1);
        grad.addColorStop(1, root.c2);
        ctx.fillStyle = grad;
        ctx.font = cssFont();
        ctx.textBaseline = "alphabetic";
        ctx.fillText(root.text, pad, pad / 2 + fontMetrics.ascent);
    }
}
