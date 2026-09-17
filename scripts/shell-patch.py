#!/usr/bin/env python3
"""Wire the Prism tab into a Caelestia shell tree, or undo it.

    shell-patch.py apply  <shell-dir>
    shell-patch.py revert <shell-dir>
    shell-patch.py check  <shell-dir>     # exit 0 when the tree looks patchable / patched

Four core files get small, anchored edits (each marked `// prism:` so the
script can recognise its own work):

  modules/dashboard/Content.qml      the tab entry + Component, and the glow hook
  shell.qml                          the screen glow overlay
  modules/drawers/ContentWindow.qml  keyboard focus while the dashboard is open
  modules/ServiceLoader.qml          eager-load the GeminiGlow service

Originals are kept next to the files as `<name>.prism-orig`. Every anchor is
checked before anything is written, so an unsupported shell version fails
cleanly with nothing changed. Supported: Caelestia shell 2.4.x.
"""
import os
import shutil
import sys

MARK = "// prism:"

# (relative path, [(anchor, replacement)]) — the anchor must occur exactly once.
EDITS = [
    ("modules/dashboard/Content.qml", [
        # services module for the glow hook
        ("import qs.components.filedialog\n",
         "import qs.components.filedialog\nimport qs.services " + MARK + " GeminiGlow\n"),
        # the tab itself
        ("                enabled: Config.dashboard.showWeather\n            }\n        ];",
         "                enabled: Config.dashboard.showWeather\n            },\n"
         "            { " + MARK + " chat tab\n"
         "                component: prismComponent,\n"
         "                iconName: \"auto_awesome\",\n"
         "                text: \"Prism\",\n"
         "                enabled: true\n"
         "            }\n        ];"),
        # light up the screen glow while the Prism tab is showing
        ("    required property FileDialog facePicker\n",
         "    required property FileDialog facePicker\n\n"
         "    " + MARK + " the screen glow follows the Prism tab\n"
         "    readonly property bool prismActive: screenState.dashboard && dashboardTabs[view.currentIndex]?.component === prismComponent\n"
         "    onPrismActiveChanged: GeminiGlow.tabActive = prismActive\n"),
        # the component next to the other tabs
        ("                WeatherTab {}\n            }\n",
         "                WeatherTab {}\n            }\n\n"
         "            Component { " + MARK + " chat tab\n"
         "                id: prismComponent\n\n"
         "                PrismTab {}\n"
         "            }\n"),
    ]),
    ("shell.qml", [
        ("import \"modules/lock\"\n",
         "import \"modules/lock\"\nimport \"modules/dashboard\" " + MARK + " GeminiGlowOverlay\n"),
        ("    Drawers {}\n",
         "    Drawers {}\n    GeminiGlowOverlay {} " + MARK + " screen glow while the tab is open\n"),
    ]),
    ("modules/drawers/ContentWindow.qml", [
        ("WlrLayershell.keyboardFocus: screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand",
         "WlrLayershell.keyboardFocus: screenState.launcher || screenState.session || screenState.dashboard /* prism: typing in the tab */ ? WlrKeyboardFocus.OnDemand"),
    ]),
    ("modules/ServiceLoader.qml", [
        ("        Brightness;\n",
         "        Brightness;\n        GeminiGlow; " + MARK + " glow service\n"),
    ]),
]

# Files the installer copies into the tree; removed on revert.
PRISM_FILES = [
    "modules/dashboard/PrismTab.qml",
    "modules/dashboard/GeminiLogo.qml",
    "modules/dashboard/GeminiGlowOverlay.qml",
    "modules/dashboard/claude_symbol.svg",
    "modules/dashboard/prism",
    "services/GeminiChat.qml",
    "services/GeminiGlow.qml",
]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def is_patched(text):
    return MARK in text or "prism:" in text


def check(shell):
    """Return (ok, messages). ok means every file is either already patched or patchable."""
    msgs, ok = [], True
    for rel, edits in EDITS:
        p = os.path.join(shell, rel)
        if not os.path.isfile(p):
            msgs.append(f"missing: {rel}"); ok = False; continue
        text = read(p)
        if is_patched(text):
            msgs.append(f"already patched: {rel}"); continue
        for anchor, _ in edits:
            n = text.count(anchor)
            if n != 1:
                msgs.append(f"unsupported {rel}: anchor found {n}× — {anchor.strip().splitlines()[0][:60]!r}"); ok = False
    return ok, msgs


def apply(shell):
    ok, msgs = check(shell)
    for m in msgs:
        print("  " + m)
    if not ok:
        print("Nothing changed. This shell tree is not one the patcher knows (supported: Caelestia 2.4.x).")
        return 1
    for rel, edits in EDITS:
        p = os.path.join(shell, rel)
        text = read(p)
        if is_patched(text):
            continue
        orig = p + ".prism-orig"
        if not os.path.exists(orig):
            shutil.copy2(p, orig)
        for anchor, repl in edits:
            text = text.replace(anchor, repl, 1)
        write(p, text)
        print(f"  patched: {rel}  (original kept as {os.path.basename(orig)})")
    return 0


def revert(shell):
    for rel, _ in EDITS:
        p = os.path.join(shell, rel)
        orig = p + ".prism-orig"
        if os.path.exists(orig):
            shutil.move(orig, p)
            print(f"  restored: {rel}")
        elif os.path.isfile(p) and is_patched(read(p)):
            print(f"  WARNING: {rel} is patched but has no .prism-orig backup — left as is")
    for rel in PRISM_FILES:
        p = os.path.join(shell, rel)
        if os.path.isdir(p):
            shutil.rmtree(p); print(f"  removed: {rel}/")
        elif os.path.exists(p):
            os.remove(p); print(f"  removed: {rel}")
    return 0


def main(argv):
    if len(argv) != 3 or argv[1] not in ("apply", "revert", "check"):
        print(__doc__); return 2
    shell = os.path.abspath(os.path.expanduser(argv[2]))
    if not os.path.isfile(os.path.join(shell, "shell.qml")):
        print(f"{shell} has no shell.qml — not a Caelestia shell tree"); return 2
    if argv[1] == "check":
        ok, msgs = check(shell)
        for m in msgs: print("  " + m)
        return 0 if ok else 1
    return apply(shell) if argv[1] == "apply" else revert(shell)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
