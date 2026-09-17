#!/usr/bin/env bash
# Deploy this checkout onto the running machine:
#   backend -> ~/.local/share/prism (and restart the daemon service)
#   plugin  -> ~/.local/share/caelestia/plugins/prism (the shell hot-reloads enabled plugins)
# Usage: scripts/deploy-local.sh [plugin-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="${1:-${PRISM_PLUGIN_DIR:-$HOME/.local/share/caelestia/plugins/prism}}"
DAEMON_DIR="$HOME/.local/share/prism"

mkdir -p "$DAEMON_DIR"
rm -rf "$DAEMON_DIR/prism"
cp "$ROOT/backend/prism_daemon.py" "$DAEMON_DIR/"
cp -r "$ROOT/backend/prism" "$DAEMON_DIR/prism"
find "$DAEMON_DIR/prism" -name __pycache__ -prune -exec rm -rf {} +
chmod -R go-rwx "$DAEMON_DIR/prism" "$DAEMON_DIR/prism_daemon.py"
echo "backend  -> $DAEMON_DIR"

mkdir -p "$PLUGIN_DIR"
cp -r "$ROOT/plugin/." "$PLUGIN_DIR/"
echo "plugin   -> $PLUGIN_DIR"

for unit in prism-daemon.service gemini-daemon.service; do
    if systemctl --user list-unit-files "$unit" >/dev/null 2>&1 && systemctl --user is-enabled "$unit" >/dev/null 2>&1; then
        systemctl --user restart "$unit" && echo "restarted $unit"
        break
    fi
done
