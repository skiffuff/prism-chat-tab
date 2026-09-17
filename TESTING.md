# Testing Prism

Prism is in beta and looking for people who run the Caelestia shell to try it.
Budget about 20 minutes. Nothing here touches your shell irreversibly: the
installer keeps the originals of the four files it edits and
`~/.local/share/prism/uninstall.sh` puts everything back.

## Before you start

- Caelestia shell **2.4.x** (AUR, the flake, or a manual install). Other versions:
  the installer refuses and changes nothing — please report the version anyway.
- An API key for at least one of Gemini (free tier is enough), Claude or ChatGPT.
- The installer copies a packaged shell (`/etc/xdg/quickshell/caelestia`) to
  `~/.config/quickshell/caelestia` so it can edit it. If you already keep your
  own copy there, it is used as is. NixOS: point `PRISM_SHELL_DIR` at a writable
  mirror of the store path first.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/skiffuff/prism-chat-tab/main/install.sh | bash
export GEMINI_API_KEY=...            # or ANTHROPIC_API_KEY / OPENAI_API_KEY
systemctl --user daemon-reload && systemctl --user enable --now prism-daemon
caelestia shell -k; caelestia shell -d
```

## Checklist

Tick what worked, note what did not. One issue per problem, with the
[bug report template](https://github.com/skiffuff/prism-chat-tab/issues/new?template=bug_report.yml).

| # | Try | Expect |
|---|---|---|
| 1 | Open the dashboard | a fifth tab **Prism** (✦ icon); the tab has a green dot next to the model name |
| 2 | Type a question, Enter | a bubble with your text, then the answer; the dot turns yellow while waiting |
| 3 | Switch provider in the header dropdown | greeting, colours, composer shape and the glow around the screen change |
| 4 | Ask *"run ls -la in /tmp"* | a permission panel docked to the composer; **Allow once** runs it and the answer quotes the listing |
| 5 | Ask the same again, choose **Allow always** with the exact-command pattern (↓) | it runs; the rule appears in Settings → Permissions |
| 6 | Ask *"show me /etc/passwd"* | refused **without** a prompt (outside the allowlist), the model explains |
| 7 | Ask *"ping 1.1.1.1 once"* | prompt with a red notice; **Allow always** is greyed out |
| 8 | Settings → Connection: paste a key, **Test**, Save | key check result; the key lands in the keyring, not in config.json |
| 9 | History drawer (☰): rename, switch, delete a chat | list updates; the deleted chat is gone after a shell restart |
| 10 | `~/.local/share/prism/uninstall.sh`, restart the shell | the tab is gone, the dashboard works as before |

Also worth a look: the glow around the screen while the tab is open, typing
right after opening (keyboard focus), a second monitor, light colour scheme.

## What to report

- Shell version and how the shell is installed (AUR / flake / manual).
- What you did and what you saw; a screenshot of the tab if it is visual.
- `caelestia shell -l 2>&1 | grep -iE 'prism|gemini|error|warn' | tail -50`
- `journalctl --user -u prism-daemon -n 50 --no-pager`

The daemon redacts keys and tokens from its output, but glance over logs before
pasting them anyway.

## Known gaps

- The screen glow needs Hyprland (layer-shell overlay).
- Screen watching ("look at my screen") needs `wf-recorder`.
- The provider logo is not drawn in the tab strip on a stock shell (the tab uses
  a Material icon there).
- No plugin yet: Caelestia's plugin system is unreleased. The `plugin` branch
  tracks it.
