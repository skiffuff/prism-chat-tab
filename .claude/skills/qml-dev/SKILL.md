---
name: qml-dev
description: Rules for working with QML/QtQuick UI in this project (PrismTab.qml). Use when adding or modifying chat interface, theming, layouts, animations, ListView/ListView delegates, or any QtQuick 2.15 code. Triggers on keywords: QML, QtQuick, PrismTab.qml, UI, layout, theme, Catppuccin.
---

# QML Development for Prism

PrismTab.qml is the single QML file of the chat tab (Caelestia shell). QtQuick 2.15 + QtQuick.Controls 2.15 + QtQuick.Layouts 1.15.

## Non-negotiable rules

1. **Colors come ONLY from `root.palette`** (Catppuccin Mocha). Never hardcode hex colors. Add new shades to the `palette` property if needed, reference them as `root.palette.<name>`.
2. Root is `Rectangle { id: root }` with `implicitWidth: 900`, `implicitHeight: 650`, `color: palette.base`. Match this style for any new component.
3. Use QtQuick.Layouts (RowLayout/ColumnLayout) over anchors for anything that grows with the window. Keep `implicitX` names meaningful.
4. API config comes from the existing properties: `baseUrl`, `backendUrl`, `healthUrl`, `confirmUrl`, `execMark`. Do not invent new URLs — reuse these.
5. Shell-command messages are prefixed with `execMark` ("[EXEC]:"). Preserve this marker in rendering and parsing.
6. All HTTP from QML goes through `XMLHttpRequest` (async). Never block the UI thread; update models only via signals/onX handlers.
7. Keep the file organized with the existing section comments (`// ====...`). Follow existing naming conventions (camelCase properties, PascalCase components).
8. Before editing, Read the current PrismTab.qml and work against the actual code — never assume structure.
9. Test changes mentally for QtQuick 2.15 compatibility: no Qt 6-only APIs, no `Binding on foo` abuse, prefer `PropertyAnimation`/`NumberAnimation` for simple cases.