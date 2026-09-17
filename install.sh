#!/usr/bin/env bash
# Prism — one-line installer: Caelestia chat tab + local daemon
# Usage: curl -fsSL https://raw.githubusercontent.com/skiffuff/prism-chat-tab/main/install.sh | bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/skiffuff/prism-chat-tab/main"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
say()  { printf "${CYAN}%s${NC}\n" "$*"; }
ok()   { printf "${GREEN}✓ %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}! %s${NC}\n" "$*"; }

# Download a file from the repo; with a leading -o <path> writes to that file
fetch() {
    if [ "$1" = "-o" ]; then
        curl -fsSL "$REPO_BASE/$3" -o "$2"
    else
        curl -fsSL "$REPO_BASE/$1"
    fi
}

command -v curl >/dev/null 2>&1 || { printf "${RED}curl is required${NC}\n"; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf "${RED}python3 is required${NC}\n"; exit 1; }

say "Installing Prism..."

mkdir -p "$HOME/.config/prism" "$HOME/.local/share/prism"

# --- Tab (Caelestia plugin) ---
# The plugin is a self-contained folder the shell discovers in
# ~/.local/share/caelestia/plugins/<name>/manifest.json (Caelestia >= 2.5 with
# the plugin system). It is enabled through ~/.config/caelestia/plugins.json or
# the shell's Plugins page.
PLUGIN_DIR="${PRISM_PLUGIN_DIR:-$HOME/.local/share/caelestia/plugins/prism}"
PLUGIN_FILES="
manifest.json
Settings.qml
PrismTab.qml
GeminiChat.qml
GeminiLogo.qml
claude_symbol.svg
theme/Colours.qml
theme/StyledText.qml
theme/StyledRect.qml
theme/MaterialIcon.qml
theme/StyledSwitch.qml
theme/StyledSlider.qml
ui/AttachmentStrip.qml
ui/ComposerBox.qml
ui/ComposerField.qml
ui/ComposerGlow.qml
ui/ComposerPill.qml
ui/EmptyState.qml
ui/GradientText.qml
ui/HistoryDrawer.qml
ui/MessageList.qml
ui/ModelsPanel.qml
ui/PermissionDialog.qml
ui/ProviderPanel.qml
ui/QuotaPanel.qml
ui/SendButton.qml
ui/SettingsPane.qml
ui/TopBar.qml
"
for f in $PLUGIN_FILES; do
    mkdir -p "$PLUGIN_DIR/$(dirname "$f")"
    fetch -o "$PLUGIN_DIR/$f" "plugin/$f"
done
ok "Installed plugin -> $PLUGIN_DIR"

# Enable it (plugins.json is the shell's own file; only the enabled list is touched)
PLUGINS_JSON="$HOME/.config/caelestia/plugins.json"
mkdir -p "$(dirname "$PLUGINS_JSON")"
python3 - "$PLUGINS_JSON" <<'PY'
import json, os, sys
p = sys.argv[1]
try:
    data = json.load(open(p))
except (OSError, ValueError):
    data = {}
enabled = data.setdefault("enabled", [])
if "skiffuff/prism" not in enabled:
    enabled.append("skiffuff/prism")
data.setdefault("path", []); data.setdefault("settings", {})
json.dump(data, open(p, "w"), indent=4); open(p, "a").write("\n")
PY
ok "Enabled skiffuff/prism in $PLUGINS_JSON"

# --- Daemon (entry point + prism/ package) ---
BACKEND_FILES="
prism_daemon.py
prism/__init__.py
prism/app.py
prism/config.py
prism/keyring_store.py
prism/screen.py
prism/security.py
prism/sessions.py
prism/api/__init__.py
prism/api/chat.py
prism/api/common.py
prism/api/files.py
prism/api/providers_api.py
prism/api/sessions_api.py
prism/api/settings_api.py
prism/api/watch.py
prism/providers/__init__.py
prism/providers/anthropic.py
prism/providers/canonical.py
prism/providers/gemini.py
prism/providers/openai.py
"
for f in $BACKEND_FILES; do
    mkdir -p "$HOME/.local/share/prism/$(dirname "$f")"
    fetch -o "$HOME/.local/share/prism/$f" "backend/$f"
done
fetch -o "$HOME/.local/share/prism/requirements.txt" requirements.txt
chmod -R go-rwx "$HOME/.local/share/prism/prism"
ok "Installed daemon -> ~/.local/share/prism/prism_daemon.py (+ prism/ package)"

# --- Config ---
if [ ! -f "$HOME/.config/prism/config.json" ]; then
    fetch -o "$HOME/.config/prism/config.json" config.example.json
    ok "Created config -> ~/.config/prism/config.json"
else
    warn "Keeping existing config -> ~/.config/prism/config.json"
fi

# --- Python venv ---
VENV="$HOME/.local/share/prism/venv"
if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv "$VENV"
    ok "Created venv at $VENV"
fi
if [ "${PRISM_SKIP_DEPS:-0}" != "1" ]; then
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet -r "$HOME/.local/share/prism/requirements.txt"
    ok "Installed Python dependencies"
fi

# --- Optional systemd user service ---
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-units >/dev/null 2>&1; then
    SVC="$HOME/.config/systemd/user/prism-daemon.service"
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$SVC" <<EOF
[Unit]
Description=Prism daemon (AI chat backend for the Caelestia tab)
After=graphical-session.target

[Service]
Type=simple
ExecStart=$VENV/bin/python $HOME/.local/share/prism/prism_daemon.py
Restart=on-failure

[Install]
WantedBy=default.target
EOF
    ok "Created systemd unit -> $SVC"
fi

printf "
${GREEN}Done!${NC}

Plugin:  $PLUGIN_DIR  (enabled in ~/.config/caelestia/plugins.json)
         Needs Caelestia >= 2.5 with the plugin system; the tab shows up in
         the dashboard as \"Prism\" once the shell has loaded the plugin.

Daemon:  give it a key and start it
  export GEMINI_API_KEY=your_key     # or ANTHROPIC_API_KEY / OPENAI_API_KEY
  systemctl --user daemon-reload && systemctl --user enable --now prism-daemon

Cloudflare worker is NOT required: the daemon calls the vendor APIs directly.
Set worker_url in ~/.config/prism/config.json only if Gemini is blocked in
your country.
"
