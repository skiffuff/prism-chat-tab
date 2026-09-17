import Caelestia.Plugins

// Plugin settings. The shell instantiates this from manifest.json and passes
// it to the dashboard-tab entry point as `settings`; the values are stored in
// ~/.config/caelestia/plugins.json. Everything else (provider, keys, model,
// system instruction, glow, permissions) stays in the daemon and is edited
// from the tab's own Settings pane.
SettingsObject {
    property string daemonUrl: "http://127.0.0.1:5000"
    property string userName: ""

    SettingMeta on daemonUrl {
        label: "Daemon URL"
        description: "Where the Prism daemon listens. Leave the default unless you run it on another port."
        inputType: SettingMeta.TextField
    }

    SettingMeta on userName {
        label: "Your name"
        description: "Used in Claude's greeting. Empty = your login name."
        inputType: SettingMeta.TextField
    }
}
