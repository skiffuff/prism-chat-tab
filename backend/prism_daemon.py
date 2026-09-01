import os
import json
import base64
import re
import uuid
import threading
import signal
import time
import asyncio
import subprocess
import shutil
import requests
import uvicorn
from fastapi import FastAPI, Request, Response

app = FastAPI(title="AI Provider Daemon")

CONFIG_FILE = os.environ.get("PRISM_CONFIG", os.path.expanduser("~/.config/prism/config.json"))
ZENITY = shutil.which("zenity") or "zenity"
WORKER_URL = os.environ.get("PRISM_WORKER_URL", "")
# Direct Google AI API base used when no Cloudflare worker is configured
# (the worker is only needed where Google Gemini is geo-blocked).
GEMINI_DIRECT_BASE = "https://generativelanguage.googleapis.com"
ANTHROPIC_URL = "https://api.anthropic.com"

def _gemini_base() -> str:
    """Base URL for Gemini requests: worker proxy if set, otherwise the direct Google API."""
    return WORKER_URL or GEMINI_DIRECT_BASE
RECORD_TRIGGER_RE = re.compile(r'(запис|запиши|запись экрана|просмотр|видь|видишь|посмотри|смотри|что на экране|что происходит|смотр|screen|watch|record)', re.IGNORECASE)

DEFAULT_SYSTEM_INSTRUCTION = "You are a helpful and knowledgeable assistant. Always respond in Russian unless the user writes in another language. CRITICAL: Never use markdown bold (**), bullet dashes (--), or markdown lists in your responses. Output plain conversational text only. You have access to the `run_bash` tool. When the user asks you to execute a command, take a screenshot, interact with the clipboard, or perform any system action, you MUST use the `run_bash` tool to execute it."
SYSTEM_INSTRUCTION = DEFAULT_SYSTEM_INSTRUCTION

# ── Provider registry ──────────────────────────────────────────
PROVIDERS = [
    {
        "id": "gemini",
        "name": "Gemini",
        "style": "gemini",
        "icon": "star",
        "logo": "sparkle",
        "primary": "#4285F4",
        "secondary": "#9B72CB",
        "tertiary": "#D96570",
        "bubble": "#4285F4",
        "gradient": ["#4285F4", "#9B72CB", "#D96570", "#4285F4"],
        "greeting": "Hi, I'm Gemini",
        "key_placeholder": "AIza...",
        "help": "Google AI Studio key (from keyring or GEMINI_API_KEY env)",
        "default_model": "gemini-3.6-flash",
        "default_models": [
            "gemini-3.6-flash", "gemini-2.5-flash", "gemini-1.5-pro",
            "gemini-1.5-flash", "gemma-4-31b-it"
        ],
    },
    {
        "id": "anthropic",
        "name": "Claude",
        "style": "claude",
        "icon": "flare",
        "logo": "claude",
        "primary": "#D97757",
        "secondary": "#E0A458",
        "tertiary": "#8C5A3F",
        "bubble": "#D97757",
        "gradient": ["#D97757", "#E0A458", "#8C5A3F", "#D97757"],
        "greeting": "Hi, I'm Claude",
        "key_placeholder": "sk-ant-...",
        "help": "Anthropic API key (for Claude; from keyring or ANTHROPIC_API_KEY env)",
        "default_model": "claude-sonnet-4-5",
        "default_models": [
            "claude-sonnet-4-5", "claude-opus-4-1", "claude-3-7-sonnet",
            "claude-3-5-sonnet", "claude-3-5-haiku"
        ],
    },
]

PROVIDER_KEYS = {}
current_provider = "gemini"
current_model = PROVIDERS[0]["default_model"]


def run_bash_execution(command: str) -> str:
    try:
        env = _user_env()
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            timeout=30,
            env=env
        )
        stdout_str = result.stdout.decode('utf-8', errors='replace')
        stderr_str = result.stderr.decode('utf-8', errors='replace')
        output = stdout_str + (f"\n[stderr]\n{stderr_str}" if stderr_str else "")
        return output.strip() if output.strip() else "Command executed successfully."
    except Exception as e:
        return f"Execution error: {str(e)}"


BASH_TOOL_DECLARATION = {
    "function_declarations": [{
        "name": "run_bash",
        "description": "Executes bash commands in Linux terminal.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "command": {
                    "type": "STRING",
                    "description": "The bash command to run"
                }
            },
            "required": ["command"]
        }
    }]
}

ANTHROPIC_TOOLS = [{
    "name": "run_bash",
    "description": "Executes bash commands in Linux terminal.",
    "input_schema": {
        "type": "OBJECT",
        "properties": {
            "command": {
                "type": "STRING",
                "description": "The bash command to run"
            }
        },
        "required": ["command"]
    }
}]

GLOW_DEFAULTS = {
    "enabled": True,
    "ring_count": 96,
    "sigma": 28,
    "alpha": 0.42,
    "gradient": None,
}
SESSIONS_FILE = os.path.expanduser("~/.local/share/prism/sessions.json")
USAGE_FILE = os.path.expanduser("~/.cache/prism_usage.json")

DEFAULT_DAILY_LIMIT = 20
usage = {"date": "", "requests": 0, "prompt_tokens": 0, "output_tokens": 0, "by_model": {}, "quota_exceeded": False, "last_error": "", "limits": {}}
def _load_usage():
    global usage
    try:
        if os.path.exists(USAGE_FILE):
            with open(USAGE_FILE, "r") as f:
                usage = json.load(f)
    except Exception:
        pass

def _save_usage():
    try:
        os.makedirs(os.path.dirname(USAGE_FILE), exist_ok=True)
        with open(USAGE_FILE, "w") as f:
            json.dump(usage, f)
    except Exception:
        pass

_load_usage()

_config = {}

KEYRING_APP = "gemini-daemon"

def _keyring_env():
    os.environ.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")
    os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus")
    os.environ.setdefault("GNOME_KEYRING_CONTROL", "/run/user/1000/keyring")

def _keyring_get(provider: str) -> str:
    """Return the API key for a provider from the OS keyring, or '' if unavailable."""
    try:
        _keyring_env()
        import secretstorage
        bus = secretstorage.dbus_init()
        col = secretstorage.get_default_collection(bus)
        if col.is_locked():
            col.unlock()
        for item in col.search_items({"application": KEYRING_APP}):
            attrs = {}
            try:
                attrs = item.get_attributes()
            except Exception:
                pass
            item_provider = attrs.get("provider", "")
            if not item_provider:
                # Legacy item (pre-provider) => belongs to Gemini
                item_provider = "gemini"
            if item_provider == provider:
                return item.get_secret().decode("utf-8", errors="replace").strip()
    except Exception:
        pass
    return ""

def _keyring_set(provider: str, key: str) -> bool:
    try:
        _keyring_env()
        import secretstorage
        bus = secretstorage.dbus_init()
        col = secretstorage.get_default_collection(bus)
        if col.is_locked():
            col.unlock()
        col.create_item(
            f"AI Provider key ({provider})",
            {"application": KEYRING_APP, "provider": provider},
            key,
            replace=True,
        )
        return True
    except Exception:
        return False

def _keyring_delete(provider: str):
    try:
        _keyring_env()
        import secretstorage
        bus = secretstorage.dbus_init()
        col = secretstorage.get_default_collection(bus)
        if col.is_locked():
            col.unlock()
        for item in col.search_items({"application": KEYRING_APP}):
            attrs = {}
            try:
                attrs = item.get_attributes()
            except Exception:
                pass
            item_provider = attrs.get("provider", "gemini")
            if item_provider == provider:
                item.delete()
    except Exception:
        pass

def _api_key() -> str:
    """Current provider's API key: keyring -> env fallback."""
    k = PROVIDER_KEYS.get(current_provider, "")
    if k:
        return k
    env_var = "ANTHROPIC_API_KEY" if current_provider == "anthropic" else "GEMINI_API_KEY"
    return os.environ.get(env_var, "") or ""

def _provider_def():
    for p in PROVIDERS:
        if p["id"] == current_provider:
            return p
    return PROVIDERS[0]

def _load_config():
    global _config, SYSTEM_INSTRUCTION, WORKER_URL, ANTHROPIC_URL, current_provider, current_model
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "r") as f:
                _config = json.load(f)
        # Provider selection
        current_provider = _config.get("provider", "gemini")
        if current_provider not in [p["id"] for p in PROVIDERS]:
            current_provider = "gemini"
        # Per-provider keys: keyring first
        for p in PROVIDERS:
            pid = p["id"]
            kk = _keyring_get(pid)
            if not kk:
                # Legacy migrate: old config had gemini api_key
                if pid == "gemini" and _config.get("api_key"):
                    kk = str(_config["api_key"])
                    if _keyring_set("gemini", kk):
                        _config.pop("api_key", None)
            if not kk:
                kk = os.environ.get("GEMINI_API_KEY" if pid == "gemini" else "ANTHROPIC_API_KEY", "")
            PROVIDER_KEYS[pid] = kk
        if "worker_url" in _config and _config["worker_url"]:
            WORKER_URL = _config["worker_url"]
        elif os.environ.get("GEMINI_WORKER_URL"):
            WORKER_URL = os.environ["GEMINI_WORKER_URL"]
        if "anthropic_url" in _config and _config["anthropic_url"]:
            ANTHROPIC_URL = _config["anthropic_url"]
        if "system_instruction" in _config and _config["system_instruction"]:
            SYSTEM_INSTRUCTION = _config["system_instruction"]
        current_model = _config.get("model") or _provider_def()["default_model"]
    except Exception:
        pass

def _save_config():
    try:
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        data = {k: v for k, v in _config.items() if k != "api_key"}
        data["provider"] = current_provider
        data["model"] = current_model
        with open(CONFIG_FILE, "w") as f:
            json.dump(data, f, indent=2)
        os.chmod(CONFIG_FILE, 0o600)
    except Exception:
        pass

_load_config()

def _user_env():
    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = env.get("XDG_RUNTIME_DIR", "/run/user/1000")
    env["WAYLAND_DISPLAY"] = env.get("WAYLAND_DISPLAY", "wayland-1")
    env["DBUS_SESSION_BUS_ADDRESS"] = env.get("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus")
    env["QT_QPA_PLATFORM"] = "wayland"
    env["DISPLAY"] = env.get("DISPLAY", ":0")
    return env


def clean_response_text(txt):
    if not txt:
        return ""
    txt = re.sub(r' thinking.*? response', '', txt, flags=re.DOTALL | re.I)
    txt = txt.replace("**", "")
    txt = re.sub(r'^\s*[-—]{1,2}\s+', '', txt, flags=re.M)
    txt = txt.replace(" -- ", " ")
    return txt.strip()

def _now_ts():
    return int(time.time())

def _load_sessions():
    try:
        if os.path.exists(SESSIONS_FILE):
            with open(SESSIONS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict) and "sessions" in data:
                    return data
    except Exception:
        pass
    return {"sessions": [{"id": str(_now_ts()), "title": "New chat", "updated": _now_ts(), "messages": []}], "active_id": None}

def _save_sessions():
    try:
        os.makedirs(os.path.dirname(SESSIONS_FILE), exist_ok=True)
        with open(SESSIONS_FILE, "w", encoding="utf-8") as f:
            json.dump(_store, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

_store = _load_sessions()
if not _store.get("sessions"):
    _store["sessions"] = [{"id": str(_now_ts()), "title": "New chat", "updated": _now_ts(), "messages": []}]
if not _store.get("active_id") or not any(s["id"] == _store["active_id"] for s in _store["sessions"]):
    _store["active_id"] = _store["sessions"][0]["id"]

_store_lock = threading.Lock()

def _active():
    aid = _store.get("active_id")
    for s in _store["sessions"]:
        if s["id"] == aid:
            return s
    return _store["sessions"][0]


def _set_session_title(session_id: str, title: str):
    with _store_lock:
        _store["active_id"] = _store["active_id"] or _store["sessions"][0]["id"]
        for s in _store["sessions"]:
            if s["id"] == session_id:
                s["title"] = title[:48]
                break
        _save_sessions()


def background_auto_title(session_id: str, first_text: str):
    def job():
        title = _generate_chat_title(first_text)
        if title:
            _set_session_title(session_id, title)
    threading.Thread(target=job, daemon=True).start()


def _generate_chat_title(first_text: str) -> str:
    """Short AI-generated chat title, provider-agnostic."""
    prompt = ("Come up with a short title for this chat based on the user's first message. "
              "Requirements: 3-6 words, in English, no quotes, no trailing period, no explanations - title only.\n\n"
              f"First message: {first_text[:200]}")
    try:
        if current_provider == "anthropic":
            payload = {
                "model": current_model,
                "max_tokens": 64,
                "temperature": 0.8,
                "system": "You only output short chat titles.",
                "messages": [{"role": "user", "content": prompt}],
            }
            res = requests.post(f"{ANTHROPIC_URL}/v1/messages",
                                json=payload,
                                headers=_anthropic_headers(), timeout=30)
            data = res.json()
            title = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text").strip()
        else:
            endpoint = f"{_gemini_base()}/v1beta/models/{current_model}:generateContent?key={_api_key()}"
            payload = {
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.8, "topP": 0.95}
            }
            res = requests.post(endpoint, json=payload, headers={"Content-Type": "application/json; charset=utf-8"}, timeout=30)
            data = res.json()
            title = data["candidates"][0]["content"]["parts"][0]["text"].strip()
        title = re.sub(r'^["\']+|["\']+$', '', title).strip()
        title = re.sub(r'[«»"]+', '', title).strip()
        return title[:48]
    except Exception:
        return ""


record_state = {"active": False, "process": None, "prompt": "Analyze the screen recording and help."}
_watch_lock = threading.Lock()

def _glow_flag(on):
    try:
        if on:
            open("/tmp/gemini_glow_active", "w").close()
        elif os.path.exists("/tmp/gemini_glow_active"):
            os.remove("/tmp/gemini_glow_active")
    except Exception:
        pass

def _find_recorder():
    """Find wf-recorder or fall back to ffmpeg."""
    wf = shutil.which("wf-recorder")
    if wf:
        return ["wf-recorder", "-f", "/tmp/gemini_screen_record.mp4", "-y"]
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        return [ffmpeg, "-f", "pipewire", "-i", "default", "-y", "/tmp/gemini_screen_record.mp4"]
    return None

def start_screen_recording(prompt="Analyze the screen recording and help."):
    with _watch_lock:
        if record_state["active"]:
            return
        record_state["active"] = True
        record_state["prompt"] = prompt or "Analyze the screen recording and help."
        env = _user_env()
        cmd = _find_recorder()
        if not cmd:
            record_state["active"] = False
            return
        try:
            p = subprocess.Popen(cmd, env=env)
            record_state["process"] = p
        except Exception:
            record_state["active"] = False
            return
    _glow_flag(True)

def _extract_video_frame(vid_path):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    try:
        r = subprocess.run([ffmpeg, "-ss", "0.5", "-i", vid_path, "-frames:v", "1",
                            "-f", "image2pipe", "-vcodec", "png", "-"],
                           capture_output=True, timeout=30)
        if r.returncode == 0 and r.stdout:
            return base64.b64encode(r.stdout).decode()
    except Exception:
        pass
    return None

def stop_screen_recording_and_analyze():
    with _watch_lock:
        if not record_state["active"]:
            _glow_flag(False)
            return "Screen watching was not active."
        record_state["active"] = False
        p = record_state.get("process")
        prompt = record_state.get("prompt", "Analyze the screen recording and help.")

    _glow_flag(False)

    if p:
        try:
            p.send_signal(signal.SIGINT)
            p.wait(timeout=6)
        except Exception:
            try:
                p.kill()
            except Exception:
                pass

    vid_path = "/tmp/gemini_screen_record.mp4"
    if not os.path.exists(vid_path) or os.path.getsize(vid_path) < 1000:
        return "Failed to record screen video."

    try:
        text_prompt = prompt or "Analyze the recording and help."
        ans = ""
        if current_provider == "anthropic":
            frame = _extract_video_frame(vid_path)
            os.remove(vid_path)
            blocks = []
            if frame:
                blocks.append({"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": frame}})
            blocks.append({"type": "text", "text": text_prompt})
            payload = {
                "model": current_model,
                "max_tokens": 1024,
                "system": SYSTEM_INSTRUCTION,
                "messages": [{"role": "user", "content": blocks}],
            }
            res = requests.post(f"{ANTHROPIC_URL}/v1/messages", json=payload,
                                headers=_anthropic_headers(), timeout=60)
            data = res.json()
            ans = clean_response_text("".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text"))
        else:
            with open(vid_path, "rb") as f:
                v_data = base64.b64encode(f.read()).decode()
            os.remove(vid_path)
            endpoint = f"{_gemini_base()}/v1beta/models/{current_model}:generateContent?key={_api_key()}"
            payload = {
                "contents": [{
                    "role": "user",
                    "parts": [
                        {"inline_data": {"mime_type": "video/mp4", "data": v_data}},
                        {"text": text_prompt}
                    ]
                }],
                "system_instruction": {"parts": [{"text": SYSTEM_INSTRUCTION}]},
                "generationConfig": {"maxOutputTokens": 150}
            }
            res = requests.post(endpoint, json=payload, headers={"Content-Type": "application/json; charset=utf-8"}, timeout=60)
            rd = res.json()
            cand = rd.get("candidates", [{}])[0].get("content", {})
            text = next((pt.get("text", "") for pt in cand.get("parts", []) if pt.get("text")), "")
            ans = clean_response_text(text)
        ans = ans or "Analysis finished, but the model returned no text."

        a_sess = _active()
        a_sess["messages"].append({"role": "user", "parts": [{"text": "[Видеозапись экрана]"}]})
        a_sess["messages"].append({"role": "assistant", "parts": [{"text": ans}]})
        _save_sessions()
        return ans
    except Exception as e:
        return f"Video analysis error: {e}"

@app.post("/watch/start")
async def watch_start():
    start_screen_recording()
    return Response(content=json.dumps({"ok": True, "active": True}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/watch/stop")
async def watch_stop():
    ans = stop_screen_recording_and_analyze()
    return Response(content=json.dumps({"ok": True, "active": False, "response": ans}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.get("/watch/status")
async def watch_status():
    return Response(
        content=json.dumps({"active": record_state["active"], "hint": "", "updated": 0}, ensure_ascii=False),
        status_code=200,
        media_type="application/json; charset=utf-8"
    )

@app.get("/health")
async def health():
    return Response(content=json.dumps({"status": "ok"}), status_code=200, media_type="application/json")


# ── Canonical message helpers ──────────────────────────────────
# Canonical block types: text / image / tool_use / tool_result.
# Storage keeps BOTH legacy Gemini wire parts and canonical blocks;
# these helpers convert any mix into canonical form before sending wire.

def _canonical_blocks(parts):
    out = []
    for pt in parts:
        if not isinstance(pt, dict):
            continue
        t = pt.get("type")
        if t in ("text", "image", "tool_use", "tool_result"):
            out.append(pt)
            continue
        if pt.get("text"):
            out.append({"type": "text", "text": pt["text"]})
        elif "inline_data" in pt:
            out.append({"type": "image",
                        "mime": pt["inline_data"].get("mime_type", "image/png"),
                        "data": pt["inline_data"].get("data", "")})
        elif "functionCall" in pt:
            out.append({"type": "tool_use", "id": "",
                        "name": pt["functionCall"].get("name", "run_bash"),
                        "input": pt["functionCall"].get("args", {})})
        elif "functionResponse" in pt:
            out.append({"type": "tool_result", "tool_use_id": "",
                        "name": "run_bash",
                        "content": str(pt["functionResponse"].get("response", {}).get("result", ""))})
    return out

def _canonical_role(role):
    return "user" if role == "user" else "assistant"

def _anthropic_headers():
    return {
        "x-api-key": _api_key(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "accept": "application/json",
    }

def _build_gemini_contents(messages, keep_inline_last_only=True):
    contents = []
    for idx, m in enumerate(messages):
        is_last = (idx == len(messages) - 1)
        role = "model" if m["role"] != "user" else "user"
        new_parts = []
        for b in _canonical_blocks(m.get("parts", [])):
            t = b.get("type")
            if t == "text":
                new_parts.append({"text": b["text"]})
            elif t == "image":
                if keep_inline_last_only and not is_last:
                    new_parts.append({"text": "[Прикрепленное изображение]"})
                else:
                    new_parts.append({"inline_data": {"mime_type": b.get("mime", "image/png"),
                                                       "data": b.get("data", "")}})
            elif t == "tool_use":
                new_parts.append({"functionCall": {"name": b.get("name", "run_bash"),
                                                   "args": b.get("input", {})}})
            elif t == "tool_result":
                new_parts.append({"functionResponse": {"name": b.get("name", "run_bash"),
                                                       "response": {"result": b.get("content", "")}}})
        contents.append({"role": role, "parts": new_parts})
    return contents

def _build_anthropic_messages(messages):
    out = []
    for m in messages:
        role = "assistant" if m["role"] != "user" else "user"
        blocks = []
        for b in _canonical_blocks(m.get("parts", [])):
            t = b.get("type")
            if t == "text":
                if b.get("text"):
                    blocks.append({"type": "text", "text": b["text"]})
            elif t == "image":
                blocks.append({"type": "image",
                               "source": {"type": "base64",
                                          "media_type": b.get("mime", "image/png"),
                                          "data": b.get("data", "")}})
            elif t == "tool_use":
                blocks.append({"type": "tool_use",
                               "id": b.get("id") or f"toolu_{uuid.uuid4().hex[:12]}",
                               "name": b.get("name", "run_bash"),
                               "input": b.get("input", {})})
            elif t == "tool_result":
                blocks.append({"type": "tool_result",
                               "tool_use_id": b.get("tool_use_id") or f"toolu_{uuid.uuid4().hex[:12]}",
                               "content": b.get("content", "")})
        out.append({"role": role, "content": blocks})
    # Anthropic rejects consecutive same-role turns; merge them.
    merged = []
    for m in out:
        if merged and merged[-1]["role"] == m["role"]:
            merged[-1]["content"].extend(m["content"])
        else:
            merged.append(m)
    return [m for m in merged if m["content"]]

def _track_usage_tokens(provider, um):
    try:
        if provider == "anthropic":
            usage["prompt_tokens"] += um.get("input_tokens", 0)
            usage["output_tokens"] += um.get("output_tokens", 0)
            return um.get("input_tokens", 0), um.get("output_tokens", 0)
        else:
            usage["prompt_tokens"] += um.get("promptTokenCount", 0)
            usage["output_tokens"] += um.get("candidatesTokenCount", 0)
            return um.get("promptTokenCount", 0), um.get("candidatesTokenCount", 0)
    except Exception:
        return 0, 0

def _record_round(current_model_name, provider):
    usage["requests"] += 1
    bm = usage["by_model"].setdefault(current_model_name, {})
    if isinstance(bm, dict):
        bm["requests"] = bm.get("requests", 0) + 1
        bm["provider"] = provider
    else:
        usage["by_model"][current_model_name] = {"requests": int(bm or 0) + 1, "provider": provider}
    _save_usage()


def _call_gemini(messages):
    if not _api_key():
        return None, {"message": "Google AI Studio key is not set. Add it in the chat settings."}, {}
    payload = {
        "contents": _build_gemini_contents(messages),
        "system_instruction": {"parts": [{"text": SYSTEM_INSTRUCTION}]},
        "tools": [BASH_TOOL_DECLARATION],
        "generationConfig": {"temperature": 0.7, "topP": 0.95}
    }
    endpoint = f"{_gemini_base()}/v1beta/models/{current_model}:generateContent?key={_api_key()}"
    res = requests.post(endpoint, json=payload,
                        headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        data = res.json()
    except Exception:
        return None, f"HTTP {res.status_code}: не-JSON ответ", {"promptTokenCount": 0, "candidatesTokenCount": 0}
    if "error" in data:
        return None, data["error"], {"promptTokenCount": 0, "candidatesTokenCount": 0}
    cand = data["candidates"][0]["content"]
    return cand.get("parts", []), "", data.get("usageMetadata", {})


def _call_anthropic(messages):
    if not _api_key():
        return None, {"message": "Claude API key is not set. Add it in the chat settings."}, {}
    payload = {
        "model": current_model,
        "max_tokens": 10000,
        "temperature": 0.7,
        "system": SYSTEM_INSTRUCTION,
        "messages": _build_anthropic_messages(messages),
        "tools": ANTHROPIC_TOOLS,
    }
    try:
        res = requests.post(f"{ANTHROPIC_URL}/v1/messages", json=payload,
                            headers=_anthropic_headers(), timeout=120)
        data = res.json()
    except Exception as e:
        return None, {"message": str(e)}, {}
    if res.status_code >= 400 or data.get("type") == "error":
        err = data.get("error", {})
        if isinstance(err, dict):
            msg = err.get("message", str(err))
            return None, {"message": msg, "code": res.status_code,
                          "status": data.get("type", "ERROR")}, {}
        return None, {"message": str(data)}, {}
    blocks = []
    for b in data.get("content", []):
        t = b.get("type")
        if t == "text":
            blocks.append({"type": "text", "text": b.get("text", "")})
        elif t == "tool_use":
            blocks.append({"type": "tool_use", "id": b.get("id", ""),
                           "name": b.get("name", "run_bash"), "input": b.get("input", {})})
    return blocks, "", data.get("usage", {})


@app.post("/chat")
async def chat_endpoint(request: Request):
    provider = current_provider
    model_name = current_model
    try:
        raw_body = await request.body()
        data = json.loads(raw_body.decode('utf-8', errors='replace'))
        user_message = data.get("message", "")
        attachments = data.get("attachments", []) or []

        MAX_B64 = 15_000_000  # ~11MB raw per file
        attach_parts = []
        for a in attachments[:8]:
            d = a.get("data") or ""
            if not d or len(d) > MAX_B64:
                continue
            attach_parts.append({"type": "image",
                                 "mime": a.get("mime") or "application/octet-stream",
                                 "data": d})

        if not user_message and not attach_parts:
            return Response(content=json.dumps({"error": "Empty message"}), status_code=400, media_type="application/json")

        user_blocks = attach_parts + ([{"type": "text", "text": user_message}] if user_message else [])
        a_sess = _active()
        hist = a_sess["messages"]
        hist.append({"role": "user", "parts": user_blocks})
        if not a_sess.get("title"):
            t0 = user_message.strip() or ((attachments[0].get("filename") if attachments else "") or "Chat")
            a_sess["title"] = t0[:48]
            sess_id = a_sess["id"]
            background_auto_title(sess_id, t0)
        a_sess["updated"] = _now_ts()

        # Ограничиваем историю, чтобы не раздувать контекст
        if len(hist) > 40:
            del hist[:len(hist) - 40]

        for _ in range(10):
            if provider == "anthropic":
                parts, err, um = _call_anthropic(hist)
            else:
                parts, err, um = _call_gemini(hist)

            if err:
                # Откатываем сообщение пользователя, чтобы не засорять историю при сбое
                if hist and hist[-1].get("role") == "user":
                    hist.pop()
                msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)
                code = err.get("code") if isinstance(err, dict) else None
                status = err.get("status") if isinstance(err, dict) else None
                if ("quota" in msg.lower() or (code == 429) or (status and "RESOURCE" in str(status).upper())):
                    usage["quota_exceeded"] = True
                    usage["last_error"] = msg
                    m_limit = re.search(r'limit:\s*(\d+)[^,]*,?\s*model:\s*([\w.\-]+)', msg)
                    if m_limit:
                        usage.setdefault("limits", {})[m_limit.group(2)] = int(m_limit.group(1))
                    _save_usage()
                return Response(
                    content=json.dumps({"error": msg}, ensure_ascii=False),
                    status_code=200,
                    media_type="application/json; charset=utf-8"
                )

            hist.append({"role": "assistant", "parts": parts})
            a_sess["updated"] = _now_ts()
            _save_sessions()

            _record_round(model_name, provider)
            in_t, out_t = _track_usage_tokens(provider, um)
            usage["quota_exceeded"] = False
            usage["last_error"] = ""
            bm = usage["by_model"].setdefault(model_name, {})
            if isinstance(bm, dict):
                bm["prompt_tokens"] = bm.get("prompt_tokens", 0) + in_t
                bm["output_tokens"] = bm.get("output_tokens", 0) + out_t
            _save_usage()

            function_call = None
            tool_id = ""
            name = ""
            for pt in parts:
                if pt.get("type") == "tool_use":
                    function_call = pt.get("input", {})
                    tool_id = pt.get("id", "")
                    name = pt.get("name", "run_bash")
                    if name == "run_bash":
                        break
                elif "functionCall" in pt and pt["functionCall"].get("name") == "run_bash":
                    function_call = pt["functionCall"].get("args", {})
                    name = "run_bash"
                    break

            if name == "run_bash" and function_call is not None:
                cmd = function_call.get("command", "")
                print(f"🔧 [EXEC]: {cmd}")
                exec_result = run_bash_execution(cmd)
                misty_part = {"type": "tool_result",
                              "tool_use_id": tool_id,
                              "name": "run_bash",
                              "content": exec_result}
                if provider == "gemini":
                    misty_part = {"functionResponse": {"name": "run_bash",
                                                       "response": {"result": exec_result}}}
                hist.append({"role": "user", "parts": [misty_part]})
                _save_sessions()
                name = ""
            else:
                final_text = clean_response_text("".join(
                    pt.get("text", "") for pt in parts if pt.get("type") == "text"
                ))
                if not final_text:
                    final_text = clean_response_text(parts[0].get("text", "")) if parts and "text" in parts[0] else ""
                if RECORD_TRIGGER_RE.search(user_message or ""):
                    final_text += "\n\n👁 Включаю просмотр вашего экрана — подсказки будут появляться здесь. Остановить можно кнопкой сверху."
                    start_screen_recording(user_message)
                return Response(
                    content=json.dumps({"response": final_text}, ensure_ascii=False),
                    status_code=200,
                    media_type="application/json; charset=utf-8"
                )

        return Response(
            content=json.dumps({"error": "Request processing iteration count exceeded."}, ensure_ascii=False),
            status_code=200,
            media_type="application/json; charset=utf-8"
        )

    except Exception as e:
        print(f"\n[ERROR]: {e}\n")
        return Response(
            content=json.dumps({"error": str(e)}, ensure_ascii=False),
            status_code=200,
            media_type="application/json; charset=utf-8"
        )


@app.get("/providers")
async def list_providers():
    out = []
    for p in PROVIDERS:
        out.append({
            "id": p["id"],
            "name": p["name"],
            "style": p["style"],
            "icon": p["icon"],
            "logo": p["logo"],
            "primary": p["primary"],
            "secondary": p["secondary"],
            "tertiary": p["tertiary"],
            "bubble": p["bubble"],
            "gradient": p["gradient"],
            "greeting": p["greeting"],
            "key_placeholder": p["key_placeholder"],
            "help": p["help"],
            "has_key": bool(PROVIDER_KEYS.get(p["id"]))
        })
    return Response(content=json.dumps({"providers": out, "current": current_provider}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/provider")
async def set_provider(request: Request):
    global current_provider, current_model
    try:
        body = await request.json()
        pid = body.get("provider")
        if pid and any(p["id"] == pid for p in PROVIDERS):
            current_provider = pid
            current_model = _config.get(f"model_{pid}") or _provider_def()["default_model"]
            _config["provider"] = pid
            _save_config()
            return Response(content=json.dumps({"ok": True, "provider": current_provider,
                                                "model": current_model}, ensure_ascii=False),
                            status_code=200, media_type="application/json")
    except Exception:
        pass
    return Response(content=json.dumps({"error": "invalid"}, ensure_ascii=False),
                    status_code=400, media_type="application/json")

@app.get("/models")
async def list_models():
    pdef = _provider_def()
    models = []
    if current_provider == "anthropic":
        models = [{"id": m, "label": m} for m in pdef["default_models"]]
    else:
        try:
            url = f"{_gemini_base()}/v1beta/models?key={_api_key()}"
            res = requests.get(url, timeout=5)
            if res.status_code == 200:
                data = res.json()
                for m in data.get("models", []):
                    m_name = m.get("name", "").replace("models/", "")
                    methods = m.get("supportedGenerationMethods", [])
                    if "generateContent" in methods and ("gemini" in m_name.lower() or "gemma" in m_name.lower()):
                        display_name = m.get("displayName") or m_name
                        models.append({"id": m_name, "label": display_name})
        except Exception:
            pass
    if not models:
        models = [{"id": m, "label": m} for m in pdef["default_models"]]
    return Response(content=json.dumps({"models": models, "current": current_model}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.get("/model")
async def get_model():
    return Response(content=json.dumps({"model": current_model}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/model")
async def set_model(request: Request):
    global current_model
    try:
        body = await request.json()
        m = body.get("model")
        if m:
            current_model = m
            _config[f"model_{current_provider}"] = m
            _save_config()
            return Response(content=json.dumps({"ok": True, "model": current_model}, ensure_ascii=False),
                            status_code=200, media_type="application/json")
    except Exception:
        pass
    return Response(content=json.dumps({"error": "invalid"}, ensure_ascii=False),
                    status_code=400, media_type="application/json")

@app.get("/quota")
async def get_quota():
    q = json.loads(json.dumps(usage))
    limits = q.get("limits", {})
    last_err = q.get("last_error", "") or ""
    pdef = _provider_def()
    models = set(pdef.get("default_models", []))
    has_key = bool(PROVIDER_KEYS.get(current_provider))
    q["provider"] = current_provider
    q["has_key"] = has_key
    q["by_model"] = {m: s for m, s in q.get("by_model", {}).items() if m in models}
    q["limits"] = {m: l for m, l in limits.items() if m in models}
    if has_key:
        for m in pdef.get("default_models", []):
            q["by_model"].setdefault(m, {"requests": 0, "prompt_tokens": 0, "output_tokens": 0, "status": "ok"})
    for model, st in q.get("by_model", {}).items():
        if isinstance(st, dict):
            st_out = dict(st)
            reqs = st_out.get("requests", 0)
        else:
            st_out = {"requests": int(st or 0), "prompt_tokens": 0, "output_tokens": 0}
            reqs = st_out["requests"]
        limit = q["limits"].get(model) or DEFAULT_DAILY_LIMIT
        st_out["limit"] = limit
        if q.get("quota_exceeded") and model in last_err:
            st_out["status"] = "exhausted"
        elif reqs >= limit:
            st_out["status"] = "exhausted"
        elif reqs >= limit * 0.7:
            st_out["status"] = "warning"
        else:
            st_out["status"] = "ok"
        q["by_model"][model] = st_out
    return Response(content=json.dumps(q, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.get("/history")
async def get_history():
    return Response(content=json.dumps({"history": _active()["messages"]}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/clear")
async def clear_history():
    a_sess = _active()
    a_sess["messages"] = []
    a_sess["title"] = ""
    _save_sessions()
    return Response(content=json.dumps({"ok": True}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.get("/sessions")
async def get_sessions():
    sessions_meta = [{"id": s["id"], "title": s["title"] or "New chat", "updated": s.get("updated", 0)}
                     for s in _store["sessions"]]
    return Response(content=json.dumps({"sessions": sessions_meta, "active_id": _store["active_id"]}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/session/new")
async def new_session():
    new_s = {"id": str(_now_ts()), "title": "New chat", "updated": _now_ts(), "messages": []}
    _store["sessions"].insert(0, new_s)
    _store["active_id"] = new_s["id"]
    _save_sessions()
    return Response(content=json.dumps({"ok": True, "active_id": new_s["id"]}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/session/select")
async def select_session(request: Request):
    body = await request.json()
    sid = body.get("id")
    if any(s["id"] == sid for s in _store["sessions"]):
        _store["active_id"] = sid
        _save_sessions()
        return Response(content=json.dumps({"ok": True}, ensure_ascii=False),
                        status_code=200, media_type="application/json")
    return Response(content=json.dumps({"error": "not found"}, ensure_ascii=False),
                    status_code=404, media_type="application/json")

@app.post("/session/rename")
async def rename_session(request: Request):
    body = await request.json()
    sid = body.get("id")
    title = (body.get("title") or "").strip()
    for s in _store["sessions"]:
        if s["id"] == sid:
            s["title"] = title[:48]
            _save_sessions()
            return Response(content=json.dumps({"ok": True}, ensure_ascii=False),
                            status_code=200, media_type="application/json")
    return Response(content=json.dumps({"error": "not found"}, ensure_ascii=False),
                    status_code=404, media_type="application/json")

@app.post("/session/delete")
async def delete_session(request: Request):
    body = await request.json()
    sid = body.get("id")
    sessions = _store["sessions"]
    if len(sessions) <= 1:
        sessions[0] = {"id": str(_now_ts()), "title": "New chat", "updated": _now_ts(), "messages": []}
        _store["active_id"] = sessions[0]["id"]
    else:
        _store["sessions"] = [s for s in sessions if s["id"] != sid]
        if _store["active_id"] == sid:
            _store["active_id"] = _store["sessions"][0]["id"]
    _save_sessions()
    return Response(content=json.dumps({"ok": True}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/clipboard_image")
async def clipboard_image():
    env = _user_env()
    r = subprocess.run([shutil.which("wl-paste") or "wl-paste", "--type", "image/png"],
                       capture_output=True, timeout=5, env=env)
    if r.returncode != 0 or not r.stdout:
        return Response(content=json.dumps({"error": "no_image"}, ensure_ascii=False),
                        status_code=400, media_type="application/json")
    b64 = base64.b64encode(r.stdout).decode()
    return Response(content=json.dumps({"mime": "image/png", "data": b64}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/read_file")
async def read_file(request: Request):
    body = await request.json()
    fpath = body.get("path")
    if not fpath or not os.path.exists(fpath):
        return Response(content=json.dumps({"error": "not_found"}, ensure_ascii=False),
                        status_code=404, media_type="application/json")
    mime = "application/octet-stream"
    if fpath.endswith((".png", ".PNG")): mime = "image/png"
    elif fpath.endswith((".jpg", ".jpeg")): mime = "image/jpeg"
    elif fpath.endswith((".webp",)): mime = "image/webp"
    elif fpath.endswith((".txt", ".py", ".qml", ".js", ".json", ".md")): mime = "text/plain"
    try:
        with open(fpath, "rb") as f:
            raw = f.read()
        b64 = base64.b64encode(raw).decode()
        return Response(content=json.dumps({"mime": mime, "data": b64, "filename": os.path.basename(fpath)}, ensure_ascii=False),
                        status_code=200, media_type="application/json")
    except Exception as e:
        return Response(content=json.dumps({"error": str(e)}, ensure_ascii=False),
                        status_code=500, media_type="application/json")

@app.post("/pick_file")
async def pick_file():
    env = _user_env()
    zenity_bin = ZENITY
    try:
        r = subprocess.run([zenity_bin, "--file-selection"], capture_output=True, timeout=60, env=env)
    except subprocess.TimeoutExpired:
        return Response(content=json.dumps({"error": "timeout"}, ensure_ascii=False),
                        status_code=400, media_type="application/json")
    path = r.stdout.decode('utf-8', errors='replace').strip()
    if not path or r.returncode != 0:
        return Response(content=json.dumps({"error": "cancelled"}, ensure_ascii=False),
                        status_code=400, media_type="application/json")
    mime = "application/octet-stream"
    if path.endswith((".png", ".PNG")): mime = "image/png"
    elif path.endswith((".jpg", ".jpeg")): mime = "image/jpeg"
    elif path.endswith((".webp",)): mime = "image/webp"
    elif path.endswith((".txt", ".py", ".qml", ".js", ".json", ".md", ".sh", ".lua")): mime = "text/plain"
    try:
        with open(path, "rb") as f:
            raw = f.read()
        b64 = base64.b64encode(raw).decode()
        return Response(content=json.dumps({"mime": mime, "data": b64, "filename": os.path.basename(path)}, ensure_ascii=False),
                        status_code=200, media_type="application/json")
    except Exception as e:
        return Response(content=json.dumps({"error": str(e)}, ensure_ascii=False),
                        status_code=500, media_type="application/json")

@app.get("/settings")
async def get_settings():
    glow = {**GLOW_DEFAULTS, **(_config.get("glow", {}) or {})}
    if not glow.get("gradient"):
        glow["gradient"] = _provider_def()["gradient"]
    return Response(content=json.dumps({
        "provider": current_provider,
        "api_key_set": bool(PROVIDER_KEYS.get(current_provider)),
        "key_placeholder": _provider_def()["key_placeholder"],
        "worker_url": WORKER_URL,
        "anthropic_url": ANTHROPIC_URL,
        "system_instruction": SYSTEM_INSTRUCTION,
        "glow": glow
    }, ensure_ascii=False), status_code=200, media_type="application/json")

@app.put("/settings")
async def update_settings(request: Request):
    global SYSTEM_INSTRUCTION, WORKER_URL, ANTHROPIC_URL
    data = await request.json()

    # Security: the key is stored ONLY in the OS keyring, never flushed to disk.
    if "api_key" in data:
        new_key = (data["api_key"] or "").strip()
        if new_key:
            PROVIDER_KEYS[current_provider] = new_key
            _keyring_set(current_provider, new_key)
        else:
            _keyring_delete(current_provider)
            PROVIDER_KEYS[current_provider] = os.environ.get(
                "ANTHROPIC_API_KEY" if current_provider == "anthropic" else "GEMINI_API_KEY", "")
    if "worker_url" in data:
        WORKER_URL = data["worker_url"] or WORKER_URL
        _config["worker_url"] = WORKER_URL
    if "anthropic_url" in data:
        ANTHROPIC_URL = data["anthropic_url"] or ANTHROPIC_URL
        _config["anthropic_url"] = ANTHROPIC_URL
    if "system_instruction" in data:
        SYSTEM_INSTRUCTION = data["system_instruction"] if data["system_instruction"] is not None else SYSTEM_INSTRUCTION
        _config["system_instruction"] = SYSTEM_INSTRUCTION
    if "glow" in data and isinstance(data["glow"], dict):
        current = {**GLOW_DEFAULTS, **_config.get("glow", {})}
        current.update({k: v for k, v in data["glow"].items() if v is not None})
        current["gradient"] = data["glow"].get("gradient") or current.get("gradient") or _provider_def()["gradient"]
        _config["glow"] = current
    _save_config()
    return Response(content=json.dumps({"ok": True}, ensure_ascii=False),
                    status_code=200, media_type="application/json")

@app.post("/settings/validate")
async def validate_settings(request: Request):
    data = await request.json()
    key = data.get("api_key", _api_key())
    pdef = _provider_def()
    try:
        if current_provider == "anthropic":
            # Anthropic exposes no model-list endpoint; validate by hitting /v1/messages
            # with a tiny no-op is not possible, so verify key shape + reachability.
            if isinstance(key, str) and key.strip().startswith("sk-ant-"):
                return Response(content=json.dumps({"valid": True, "validated": False}, ensure_ascii=False),
                                status_code=200, media_type="application/json")
            return Response(content=json.dumps({"valid": False, "error": "Invalid Claude API key format"}, ensure_ascii=False),
                            status_code=200, media_type="application/json")
        else:
            r = requests.get(f"{_gemini_base()}/v1beta/models?key={key}", timeout=10)
            if r.status_code == 200:
                models = r.json().get("models", [])
                return Response(content=json.dumps({"valid": True, "models": len(models)}, ensure_ascii=False),
                                status_code=200, media_type="application/json")
            return Response(content=json.dumps({"valid": False, "error": f"HTTP {r.status_code}"}, ensure_ascii=False),
                            status_code=200, media_type="application/json")
    except Exception as e:
        return Response(content=json.dumps({"valid": False, "error": str(e)}, ensure_ascii=False),
                        status_code=200, media_type="application/json")

if __name__ == "__main__":
    print(f"🚀 AI Daemon запущен на http://127.0.0.1:5000 (provider: {current_provider})")
    uvicorn.run(app, host="127.0.0.1", port=5000, log_level="info")