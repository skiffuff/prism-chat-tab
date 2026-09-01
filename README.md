# Prism — chat tab for the Caelestia shell

A chat tab for the [Caelestia](https://github.com/hyprwm/serpantinum) shell.
Drop `PrismTab.qml` into `~/.config/caelestia/` and it appears in the
dashboard. The tab talks to a local FastAPI daemon (`backend/prism_daemon.py`)
that proxies requests to a Gemini/Anthropic backend.

## Structure

```
PrismTab.qml            # QML chat tab UI (dashboard widget)
backend/prism_daemon.py # local FastAPI daemon, serves the tab on :5000
config.example.json     # daemon configuration template (no secrets)
requirements.txt        # Python dependencies
```

The tab is a plain QtQuick 2.15 widget: it renders chat history, custom
sidebar with multiple chats, auto-naming, daemon health indicator, and an
exec message view for shell commands run via the daemon.

## Setup

```bash
# 1. Install the daemon
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 2. Configure (see config.example.json)
cp config.example.json ~/.config/prism/config.json
# set worker_url to your Gemini/Anthropic-compatible proxy

# 3. Provide the API key (never written to disk by the daemon)
#    either in the OS keyring ("gemini" / "anthropic" prompts) or via env:
export GEMINI_API_KEY=...          # or ANTHROPIC_API_KEY=...

# 4. Run the daemon
.venv/bin/python backend/prism_daemon.py

# 5. Copy the tab into your Caelestia config
cp PrismTab.qml ~/.config/caelestia/
```

## Security

The API key is stored **only** in the OS keyring (via SecretStorage, e.g.
GNOME Keyring) and falls back to the `GEMINI_API_KEY` / `ANTHROPIC_API_KEY`
environment variables. It is never written to `config.json` and never
committed to the repository.