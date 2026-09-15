---
name: prism-backend
description: Rules for working with the backend/prism package (FastAPI daemon for Prism chat tab; backend/prism_daemon.py is only the entry point). Use when adding/modifying endpoints, providers (Gemini/Anthropic/OpenAI), tools (run_bash), permissions, sessions, or config. Triggers on keywords: FastAPI, daemon, endpoint, run_bash, provider, uvicorn, prism_daemon, /chat, keyring.
---

# Prism Backend (prism_daemon.py)

FastAPI daemon, package `backend/prism/` (config, security, sessions, screen, providers/, api/); `backend/prism_daemon.py` just imports `prism.app`. Native Python 3, no venv in repo (install.sh creates one). Providers: Gemini (direct or Cloudflare worker), Anthropic and OpenAI (Chat Completions).

## Non-negotiable rules

1. **Security is paramount.** Keep the CORS hardening middleware as-is (reject OPTIONS, no CORS headers). Never log API keys or config secrets — keys live in keyring (`_keyring_*`), never in config or logs.
2. Every mutating endpoint must go through `DaemonToken()` auth (`_authorize`) and the rate limiter (`_rate_limited`). New endpoints MUST call both.
3. **run_bash permission flow**: execution only via `run_bash_execution(command)`. Gate commands through `_command_ok_by_pattern` → if admin is required, `_grant_pattern`, and unresolved requests wait for client confirmation via `/tool/confirm`. Never bypass `_is_dangerous`/pattern checks. Allowed-path checks (`_allowed_read_path`) apply to file access.
4. Successfully executed commands are printed as `[EXEC]: <cmd>` — keep that marker in all execution paths.
5. Endpoints return JSONResponse with explicit status codes. Use `@app.get/@app.post` only, no body parsing bypass.
6. Config: `PRISM_CONFIG` env or `~/.config/prism/config.json`. Sessions persisted via `_load_sessions`/`_save_sessions`. Reuse these helpers; do not invent a parallel store.
7. Provider calls: Gemini uses `_gemini_base()`, Anthropic uses `ANTHROPIC_URL`, OpenAI uses `OPENAI_URL`; one model round goes through `_call_model(provider, hist)`. Follow the existing build_request/parse_function_call flow for generatation  (functionCall → run_bash). Add new providers to `PROVIDERS` in `prism/config.py` and a module in `prism/providers/` exposing call/complete_text/describe_frame/list_models/validate_key/usage_tokens; register it in `prism/providers/__init__.py`. Tests: `python backend/tests/test_daemon.py`.
8. Prompt hygiene: keep `DEFAULT_SYSTEM_INSTRUCTION` style — plain conversational Russian, no markdown emphasis, run_bash for system actions.
9. Before editing, Read the current prism_daemon.py and work against actual code. Run `python -m py_compile backend/prism_daemon.py` after changes.