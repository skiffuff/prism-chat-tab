import QtQuick
import Caelestia.Config
import skiffuff.prism.theme
import skiffuff.prism
import skiffuff.prism.ui

// Single-line prompt input shared by both composers. Mirrors the service's
// draft, sends on Enter and routes paste through the clipboard-image hook.
TextInput {
    id: root

    property string placeholder: ""

    font: Tokens.font.body.medium
    color: Colours.palette.m3onSurface
    selectedTextColor: Colours.palette.m3onPrimary
    selectionColor: Colours.palette.m3primary
    clip: true
    text: GeminiChat.draft

    onTextChanged: {
        if (GeminiChat.draft !== text)
            GeminiChat.draft = text;
    }

    function send(): void {
        GeminiChat.sendMessage(root.text);
    }

    Text {
        enabled: false
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: !root.text && !root.activeFocus
        text: root.placeholder
        font: root.font
        color: Colours.palette.m3onSurfaceVariant
    }

    Keys.onPressed: event => {
        if (event.matches(StandardKey.Paste)) {
            event.accepted = true;
            GeminiChat.pasteFromClipboard(() => root.paste());
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true;
            root.send();
            return;
        }
        event.accepted = false;
    }
}
