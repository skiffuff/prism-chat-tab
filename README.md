<p align="center">
  <img src="assets/logo/prism-holo-sticker.png" width="200" alt="Prism">
</p>

<h3 align="center">Prism as a Caelestia plugin</h3>

<p align="center">
  This is the <code>plugin</code> branch: the same tab as on <a href="https://github.com/skiffuff/prism-chat-tab"><code>main</code></a>,
  repackaged for the plugin system Caelestia is building in
  <a href="https://github.com/caelestia-dots/shell/pull/1703">shell#1703</a>.<br>
  <code>main</code> stays the overlay install that works on today's shell; this branch waits for the plugin system to ship.
</p>

<p align="center">
  <img src="assets/previews/desktop-switch.webp" width="820" alt="Prism on the desktop">
</p>

## Layout

```
plugin/                       ← ~/.local/share/caelestia/plugins/prism/
  manifest.json               id skiffuff/prism · entry point dashboard-tab · requires >= 2.5.0
  Settings.qml                SettingsObject: daemonUrl, userName (stored by the shell in plugins.json)
  PrismTab.qml                the dashboard-tab entry point; receives `settings` from the shell
  GeminiChat.qml              daemon client singleton
  GeminiLogo.qml              provider marks
  theme/                      the plugin's own Colours / StyledText / StyledRect / MaterialIcon / switch / slider
  ui/                         TopBar, EmptyState, composers, panels, PermissionDialog, SettingsPane, …
backend/                      the daemon — unchanged from main
```

Inside the plugin every sibling is imported explicitly, as the plugin loader requires:
`import skiffuff.prism`, `import skiffuff.prism.ui`, `import skiffuff.prism.theme`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/skiffuff/prism-chat-tab/plugin/install.sh | bash
```

Copies `plugin/` to `~/.local/share/caelestia/plugins/prism`, adds `skiffuff/prism` to the `enabled`
list in `~/.config/caelestia/plugins.json`, installs the daemon with its virtualenv and a user unit.
Then, as on main:

```bash
export GEMINI_API_KEY=...            # or ANTHROPIC_API_KEY / OPENAI_API_KEY
systemctl --user enable --now prism-daemon
```

From a checkout, `scripts/deploy-local.sh` copies the plugin folder and the daemon and restarts the
service; the shell hot-reloads an enabled plugin when its files change.

## What this branch does **not** have (compared to `main`)

The plugin system gives a plugin a folder, a manifest, a settings object and entry points — and
nothing else. Everything on `main` that reached into the shell had to go:

| Gone | Why | Instead |
|---|---|---|
| **Screen glow** (`GeminiGlowOverlay`, `GeminiGlow` service, the `shell.qml` line) | needs a full-screen overlay window; there is no overlay entry point yet (the PR lists desktop widgets as deferred) | nothing; the composer glow inside the tab stays |
| **Provider logo in the tab strip** (`Tabs.qml` patch) | `Tabs.qml` is core; a plugin tab gets `label` + `icon` from the manifest | Material icon `auto_awesome` and the label “Prism” |
| **`caelestia shell prism open / toggle`** | needs `ShellState`, which lives in the shell's QML and is not importable from a plugin | `caelestia shell drawers toggle dashboard` (the shell's own IPC) |
| **Shell components and theme** (`qs.components`, `qs.services.Colours`) | `import qs.*` does not resolve for files outside the config root — verified on the `feat/plugins` build | `plugin/theme/`: the plugin's own `Colours` (reads `~/.local/state/caelestia/scheme.json` and `Tokens.transparency`), `StyledText`, `StyledRect`, `MaterialIcon`, `StyledSwitch`, `StyledSlider` |
| **Overlay install** (`frontend/` copied over the shell tree) | plugins live in their own folder | `install.sh` writes `plugin/` and enables it in `plugins.json` |
| **`PRISM_USER_NAME` / `PRISM_DAEMON_URL` as the only knobs** | plugins get a settings object | `Settings.qml` → shell settings UI; the env vars still work as fallbacks |

Still here: the daemon is a separate process installed by the same script — a plugin is QML inside the
shell, it cannot ship a Python service. When the daemon is unreachable the status dot in the tab's header turns red and requests report the failure.

## Status

Verified on a build of Caelestia's `feat/plugins` branch (2026-08-03): the manifest parses without
warnings, the entry point is discovered, the shell's `EntryPointLoader` instantiates `PrismTab.qml`
and injects `Settings.qml`, and the tab renders (empty state, settings, permission prompt) with the
plugin's own theme module.

Not verifiable yet: the `dashboard-tab` entry point is declared but not consumed by the dashboard on
that branch, so the tab has no place to appear in a real shell until upstream adds it. `requires`
in the manifest points at 2.5.0 on the assumption that plugins ship in the next minor; adjust when
they do.

## Everything else

Features, security model, configuration and the API are unchanged — see the
[README on `main`](https://github.com/skiffuff/prism-chat-tab#readme).
