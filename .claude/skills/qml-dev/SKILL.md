---
name: qml-dev
description: Rules for working with the Prism tab's QML (plugin/ — the Caelestia plugin: PrismTab.qml entry point, ui/ components, theme/ module). Use when adding or modifying the chat interface, provider theming, layouts, animations, delegates or the permission dialog. Triggers on keywords: QML, QtQuick, PrismTab, prism/, TopBar, EmptyState, Composer, PermissionDialog, GeminiChat, Caelestia, quickshell.
---

# Prism plugin (QML)

`plugin/` is a Caelestia plugin: a folder with `manifest.json`, `Settings.qml`,
one `dashboard-tab` entry point and QML modules. The shell registers every
`.qml` in the folder as a type of module `skiffuff.prism` (subfolders become
`skiffuff.prism.<dir>`) and hot-reloads the plugin when files change.

- `PrismTab.qml` — the entry point. Shared state (provider flags, open panel,
  confirm state) and layout only; receives the shell's `settings` object.
- `ui/*.qml` — every visual block, each with `required property var tab`.
- `GeminiChat.qml` — singleton daemon client (XHR, `X-Prism-Token`).
- `theme/` — the plugin's own `Colours` (reads the shell's scheme.json),
  `StyledText`, `StyledRect`, `MaterialIcon`, `StyledSwitch`, `StyledSlider`.
- `GeminiLogo.qml` — provider marks: `sparkle`, `claude`, `openai`.

## Rules

1. **No `qs.*` imports.** A plugin cannot import the shell's QML
   (`qs.components`, `qs.services`, …) — it does not resolve outside the
   config root. Use `skiffuff.prism.theme` for components and `Colours`,
   `Caelestia.Config` for `Tokens`, `Quickshell*` and `QtQuick*` as usual.
2. **Explicit self-imports.** Every file that uses a sibling type imports its
   module: `import skiffuff.prism`, `import skiffuff.prism.ui`,
   `import skiffuff.prism.theme`. The loader warns on implicit use.
3. Colours come from `Colours.palette.m3*` / `Colours.tPalette.m3*`; brand
   accents from `GeminiChat.providerPrimary/Secondary/Tertiary/Bubble`.
   Fonts and spacing from `Tokens` (builders for one-offs).
4. Provider-specific looks branch on `tab.isGemini / isChatGPT / isClaude`.
5. Delegates use `required property` and their own `id`; inline
   `component X:` definitions must not reference outer ids.
6. Nothing may depend on shell internals that are not part of the plugin
   contract (`ShellState`, `Tabs.qml`, overlay windows). If a feature needs
   one, it stays on `main` until upstream adds an entry point for it.
7. Verify on the `feat/plugins` build offscreen: install the folder into a
   sandbox `~/.local/share/caelestia/plugins/prism`, enable it in
   `plugins.json`, load it with `EntryPointLoader` from a harness `shell.qml`
   under `QT_QPA_PLATFORM=offscreen` against a daemon on `PRISM_PORT`.
   Never drive the live desktop.
