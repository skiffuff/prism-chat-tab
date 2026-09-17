#!/usr/bin/env bash
# Prism — undo what install.sh did.
#   uninstall.sh            remove the tab from the shell tree and the daemon files
#   uninstall.sh --purge    also delete config, sessions, permission rules and the keyring entries
set -euo pipefail

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { printf "${GREEN}✓ %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}! %s${NC}\n" "$*"; }

DATA="$HOME/.local/share/prism"
SHELL_DIR="${PRISM_SHELL_DIR:-}"
[ -z "$SHELL_DIR" ] && [ -f "$DATA/shell-dir" ] && SHELL_DIR="$(cat "$DATA/shell-dir")"
[ -z "$SHELL_DIR" ] && [ -f "$HOME/.config/quickshell/caelestia/shell.qml" ] && SHELL_DIR="$HOME/.config/quickshell/caelestia"

# --- Tab ---
if [ -n "$SHELL_DIR" ] && [ -f "$SHELL_DIR/shell.qml" ]; then
    if [ -f "$DATA/shell-patch.py" ]; then
        python3 "$DATA/shell-patch.py" revert "$SHELL_DIR"
    else
        warn "shell-patch.py missing; restoring *.prism-orig by hand"
        find "$SHELL_DIR" -name "*.prism-orig" | while read -r orig; do mv "$orig" "${orig%.prism-orig}"; done
        rm -rf "$SHELL_DIR/modules/dashboard/prism" "$SHELL_DIR/modules/dashboard/PrismTab.qml" \
               "$SHELL_DIR/modules/dashboard/GeminiLogo.qml" "$SHELL_DIR/modules/dashboard/GeminiGlowOverlay.qml" \
               "$SHELL_DIR/modules/dashboard/claude_symbol.svg" "$SHELL_DIR/services/GeminiChat.qml" "$SHELL_DIR/services/GeminiGlow.qml"
    fi
    ok "Removed the tab from $SHELL_DIR (restart the shell: caelestia shell -k; caelestia shell -d)"
else
    warn "No shell tree recorded; skipping the tab"
fi

# --- Daemon ---
if systemctl --user list-unit-files prism-daemon.service >/dev/null 2>&1; then
    systemctl --user disable --now prism-daemon.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/prism-daemon.service"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Stopped and removed prism-daemon.service"
fi
rm -rf "$DATA/prism" "$DATA/prism_daemon.py" "$DATA/requirements.txt" "$DATA/venv" "$DATA/shell-patch.py" "$DATA/shell-dir" "$DATA/daemon.token"
ok "Removed the daemon from $DATA"

# --- State ---
if [ "${1:-}" = "--purge" ]; then
    rm -rf "$HOME/.config/prism" "$DATA" "$HOME/.cache/prism"
    if command -v secret-tool >/dev/null 2>&1; then
        for p in gemini anthropic openai; do secret-tool clear application gemini-daemon provider "$p" 2>/dev/null || true; done
        ok "Removed API keys from the keyring"
    else
        warn "secret-tool not found; API keys stay in the keyring (application 'gemini-daemon')"
    fi
    ok "Removed config, sessions and rules"
else
    warn "Kept ~/.config/prism (config, permission rules), sessions and the keyring entries — run with --purge to remove them"
fi
rm -f "$DATA/uninstall.sh" 2>/dev/null || true
printf "${GREEN}Prism is uninstalled.${NC}\n"
