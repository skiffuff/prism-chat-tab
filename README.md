# Prism

Chat tab for the [Caelestia](https://github.com/hyprwm/serpantinum) shell,
backed by a small local daemon that talks to Gemini (or Claude).

## How it works

`PrismTab.qml` (a QtQuick dashboard widget) → local daemon on `:5000` → AI API.

Requests go **directly to the Gemini / Claude API** by default. A Cloudflare
worker is **optional and only needed if Google Gemini is blocked in your
country** — set `worker_url` in the config and requests will go through it
instead.

## Install

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/skiffuff/prism-chat-tab/main/install.sh | bash
```

It installs the tab, the daemon, a venv with dependencies, a starter config
and an optional systemd unit. Or manually:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

cp config.example.json ~/.config/prism/config.json
export GEMINI_API_KEY=...        # or ANTHROPIC_API_KEY=...
.venv/bin/python backend/prism_daemon.py

cp PrismTab.qml ~/.config/caelestia/
```

## Security

The API key lives only in the OS keyring (SecretStorage), with a
`GEMINI_API_KEY` / `ANTHROPIC_API_KEY` env fallback. It is never written to
`config.json` and never committed.