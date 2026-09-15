---
name: qml-dev
description: Rules for working with the Prism tab's QML (frontend/ — PrismTab.qml and the prism/ components inside the Caelestia shell). Use when adding or modifying the chat interface, provider theming, layouts, animations, delegates or the permission dialog. Triggers on keywords: QML, QtQuick, PrismTab, prism/, TopBar, EmptyState, Composer, PermissionDialog, GeminiChat, Caelestia, quickshell.
---

# Prism frontend (QML)

`frontend/` is an overlay onto the Caelestia shell root (quickshell). It is
deployed by copying it over the shell tree (`scripts/deploy-local.sh`);
quickshell hot-reloads files it has already loaded, and loads new ones when
the dashboard opens.

- `modules/dashboard/PrismTab.qml` — shared state (provider flags, open
  panel, confirm state) and layout only. Every visual block is a component
  in `modules/dashboard/prism/` that receives the tab as `required property var tab`.
- `services/GeminiChat.qml` — singleton daemon client (XHR to 127.0.0.1:5000,
  `X-Prism-Token` from `~/.local/share/prism/daemon.token`). Refetches
  providers/models/settings when `/health.started` changes.
- `modules/dashboard/GeminiLogo.qml` — provider marks: `sparkle`, `claude`,
  `openai`. Vector shapes take `color`; the Claude image uses `tint`/`tintAmount`.

## Rules

1. Colours come from the shell theme: `Colours.palette.m3*` / `Colours.tPalette.m3*`
   for surfaces and text, `GeminiChat.providerPrimary/Secondary/Tertiary/Bubble`
   for brand accents. No hardcoded hex except the status greens/reds already used.
2. Fonts and spacing come from `Tokens` (`Tokens.font.body.*`, `.mono.*`,
   `Tokens.padding.*`, `Tokens.spacing.*`, `Tokens.rounding.*`); use the
   builders (`Tokens.font.body.builders.large.size(26).weight(Font.Medium).build()`)
   for one-offs.
3. Provider-specific looks branch on `tab.isGemini / isChatGPT / isClaude`
   (derived from the daemon's `style` field), never on the provider id.
4. Delegates use `required property` and their own `id`; ids inside a
   Repeater/ListView delegate are not addressable from outside. Inline
   `component X:` definitions must not reference outer ids — pass values in
   as properties.
5. Panels open through `tab.togglePanel("provider"|"models"|"quota")`;
   dialogs through `tab.confirm*`. Keep new state on the tab, not in
   singletons (one tab instance per monitor).
6. Verify offscreen before deploying: run an isolated `qs -p <harness>` with
   `QT_QPA_PLATFORM=offscreen`, a stub `services/Colours.qml` (Hypr/Wallpapers
   calls stripped), a `GeminiChat.qml` pointed at a sandboxed daemon, and
   `grabToImage` from a Timer. Never drive the live desktop.
