#!/usr/bin/env bash
# Deploy this checkout onto the running machine:
#   backend  -> ~/.local/share/prism (and restart the daemon service)
#   frontend -> the Caelestia shell tree (quickshell reloads it on the fly)
# Usage: scripts/deploy-local.sh [shell-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_DIR="${1:-${PRISM_SHELL_DIR:-$HOME/.local/share/caelestia-shell-store}}"
DAEMON_DIR="$HOME/.local/share/prism"

mkdir -p "$DAEMON_DIR"
rm -rf "$DAEMON_DIR/prism"
cp "$ROOT/backend/prism_daemon.py" "$DAEMON_DIR/"
cp -r "$ROOT/backend/prism" "$DAEMON_DIR/prism"
find "$DAEMON_DIR/prism" -name __pycache__ -prune -exec rm -rf {} +
chmod -R go-rwx "$DAEMON_DIR/prism" "$DAEMON_DIR/prism_daemon.py"
echo "backend  -> $DAEMON_DIR"

if [ -d "$SHELL_DIR/modules/dashboard" ]; then
    cp -r "$ROOT/frontend/." "$SHELL_DIR/"
    echo "frontend -> $SHELL_DIR"
    # Wire the tab in when the tree is a stock one; a tree that is already
    # wired some other way (e.g. a patched package) is left alone.
    if python3 "$ROOT/scripts/shell-patch.py" check "$SHELL_DIR" >/dev/null 2>&1; then
        python3 "$ROOT/scripts/shell-patch.py" apply "$SHELL_DIR"
    else
        echo "shell tree not patched by shell-patch.py (already wired or unsupported); left as is"
    fi
else
    echo "shell dir $SHELL_DIR has no modules/dashboard; frontend not copied" >&2
fi

for unit in prism-daemon.service gemini-daemon.service; do
    if systemctl --user list-unit-files "$unit" >/dev/null 2>&1 && systemctl --user is-enabled "$unit" >/dev/null 2>&1; then
        systemctl --user restart "$unit" && echo "restarted $unit"
        break
    fi
done
