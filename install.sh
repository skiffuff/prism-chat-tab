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

# --- Tab (QML overlay onto the Caelestia shell tree) ---
# frontend/ mirrors the shell's layout (modules/dashboard, services). It is
# copied over the shell root: PRISM_SHELL_DIR if set, else the quickshell
# config dir, else a staging dir you can merge yourself.
SHELL_DIR="${PRISM_SHELL_DIR:-}"
if [ -z "$SHELL_DIR" ]; then
    if [ -d "$HOME/.config/quickshell/caelestia/modules/dashboard" ]; then
        SHELL_DIR="$HOME/.config/quickshell/caelestia"
    else
        SHELL_DIR="$HOME/.local/share/prism/frontend"
        warn "Caelestia shell dir not found; staging the tab in $SHELL_DIR (copy it over your shell root)"
    fi
fi
FRONTEND_FILES="
modules/dashboard/PrismTab.qml
modules/dashboard/GeminiLogo.qml
modules/dashboard/GeminiGlowOverlay.qml
modules/dashboard/Tabs.qml
modules/dashboard/claude_symbol.svg
modules/dashboard/prism/AttachmentStrip.qml
modules/dashboard/prism/ComposerBox.qml
modules/dashboard/prism/ComposerField.qml
modules/dashboard/prism/ComposerGlow.qml
modules/dashboard/prism/ComposerPill.qml
modules/dashboard/prism/EmptyState.qml
modules/dashboard/prism/HistoryDrawer.qml
modules/dashboard/prism/MessageList.qml
modules/dashboard/prism/ModelsPanel.qml
modules/dashboard/prism/PermissionDialog.qml
modules/dashboard/prism/ProviderPanel.qml
modules/dashboard/prism/QuotaPanel.qml
modules/dashboard/prism/SendButton.qml
modules/dashboard/prism/SettingsPane.qml
modules/dashboard/prism/TopBar.qml
services/GeminiChat.qml
services/GeminiGlow.qml
"
for f in $FRONTEND_FILES; do
    mkdir -p "$SHELL_DIR/$(dirname "$f")"
    fetch -o "$SHELL_DIR/$f" "frontend/$f"
done
ok "Installed tab -> $SHELL_DIR"

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

Now give the daemon your API key (either of these):
  export GEMINI_API_KEY=your_key     # and/or ANTHROPIC_API_KEY
  then start:  $VENV/bin/python $HOME/.local/share/prism/prism_daemon.py

Optional autostart:
  systemctl --user daemon-reload
  systemctl --user enable --now prism-daemon

Cloudflare worker is NOT required: the daemon calls the Gemini/Claude API
directly. Set worker_url / anthropic_url in ~/.config/prism/config.json
only if Google Gemini is blocked in your country.
"