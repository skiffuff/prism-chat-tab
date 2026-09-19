"""Paths, the provider registry, runtime state and config.json persistence."""

import json
import os
import time
from dataclasses import dataclass, field

# ── Paths ───────────────────────────────────────────────────────────────
HOME = os.path.expanduser("~")
CONFIG_FILE = os.environ.get("PRISM_CONFIG", os.path.join(HOME, ".config/prism/config.json"))
PERMISSIONS_FILE = os.path.join(HOME, ".config/prism/permissions.json")
TOKEN_FILE = os.environ.get("PRISM_TOKEN_FILE", os.path.join(HOME, ".local/share/prism/daemon.token"))
SESSIONS_FILE = os.path.join(HOME, ".local/share/prism/sessions.json")
USAGE_FILE = os.path.join(HOME, ".cache/prism_usage.json")
# Private scratch space for recordings: a fixed name under /tmp could be
# pre-created (or symlinked) by another local user.
CACHE_DIR = os.path.join(HOME, ".cache/prism")
RECORD_FILE = os.path.join(CACHE_DIR, "screen_record.mp4")
# Boolean marker the shell's GeminiGlow service polls; harmless if tampered.
GLOW_FLAG = "/tmp/gemini_glow_active"

# ── Endpoints ───────────────────────────────────────────────────────────
# Direct Google AI API base used when no Cloudflare worker is configured
# (the worker is only needed where Google Gemini is geo-blocked).
GEMINI_DIRECT_BASE = "https://generativelanguage.googleapis.com"
ANTHROPIC_DEFAULT_URL = "https://api.anthropic.com"
OPENAI_DEFAULT_URL = "https://api.openai.com"
# Upper bound on a chat completion, shared by every provider. Every outbound
# request needs one: requests defaults to waiting forever.
CHAT_TIMEOUT = 120

DEFAULT_SYSTEM_INSTRUCTION = (
    "You are a helpful and knowledgeable assistant. Always respond in Russian unless the user "
    "writes in another language. CRITICAL: Never use markdown bold (**), bullet dashes (--), or "
    "markdown lists in your responses. Output plain conversational text only. You have access to "
    "the `run_bash` tool. When the user asks you to execute a command, take a screenshot, interact "
    "with the clipboard, or perform any system action, you MUST use the `run_bash` tool to execute it."
)

# Phrases that switch on screen watching. Deliberately narrow: an earlier
# pattern fired on any word containing "смотр"/"screen", so "посмотри этот код"
# quietly recorded the desktop and shipped it to the provider.
SCREEN_TRIGGER_PHRASES = (
    r"запис(ь|ать|ывай|ыва[йт]|ываешь)\s+(мой\s+)?экран",
    r"(по)?смотри\s+(на\s+)?(мой\s+)?экран",
    r"что\s+(сейчас\s+)?(у\s+меня\s+)?на\s+экране",
    r"что\s+происходит\s+на\s+экране",
    r"(look|watch)\s+(at\s+)?my\s+screen",
    r"record\s+(my\s+)?screen",
    r"screen\s+record",
    r"what('s| is)\s+on\s+my\s+screen",
)

GLOW_DEFAULTS = {
    "enabled": True,
    "ring_count": 96,
    "sigma": 28,
    "alpha": 0.42,
    "gradient": None,
}

# ── Provider registry ───────────────────────────────────────────────────
PROVIDERS = [
    {
        "id": "gemini",
        "name": "Gemini",
        "style": "gemini",
        "env": "GEMINI_API_KEY",
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
        "env": "ANTHROPIC_API_KEY",
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
    {
        "id": "openai",
        "name": "ChatGPT",
        "style": "chatgpt",
        "env": "OPENAI_API_KEY",
        "icon": "hub",
        "logo": "openai",
        # OpenAI green, the sage of the ChatGPT avatar, and a brighter mint
        # so the shimmer animations have somewhere to travel.
        "primary": "#10A37F",
        "secondary": "#74AA9C",
        "tertiary": "#19C37D",
        "bubble": "#10A37F",
        "gradient": ["#10A37F", "#74AA9C", "#19C37D", "#10A37F"],
        "greeting": "Hi, I'm ChatGPT",
        "key_placeholder": "sk-...",
        "help": "OpenAI API key (for ChatGPT; from keyring or OPENAI_API_KEY env)",
        "default_model": "gpt-5-mini",
        "default_models": [
            "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1",
            "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini"
        ],
    },
]

# Fields of a provider entry that are safe to hand to clients.
PROVIDER_PUBLIC_FIELDS = (
    "id", "name", "style", "icon", "logo", "primary", "secondary", "tertiary",
    "bubble", "gradient", "greeting", "key_placeholder", "help",
)


def provider_by_id(pid: str):
    for p in PROVIDERS:
        if p["id"] == pid:
            return p
    return None


def provider_env(pid: str) -> str:
    """Environment variable that may hold the API key for a provider."""
    p = provider_by_id(pid)
    return p.get("env", "") if p else ""


# ── Runtime state ───────────────────────────────────────────────────────
@dataclass
class Runtime:
    provider: str = "gemini"
    model: str = PROVIDERS[0]["default_model"]
    # provider id -> API key currently in use (keyring, config or env)
    keys: dict = field(default_factory=dict)
    # where each key came from: "keyring" | "env" | "config" | ""
    key_sources: dict = field(default_factory=dict)
    worker_url: str = os.environ.get("PRISM_WORKER_URL", "")
    anthropic_url: str = ANTHROPIC_DEFAULT_URL
    openai_url: str = OPENAI_DEFAULT_URL
    system_instruction: str = DEFAULT_SYSTEM_INSTRUCTION
    # Raw contents of config.json (minus secrets)
    config: dict = field(default_factory=dict)
    # Exposed by /health so a long-lived client can notice a restart and
    # refetch everything it cached at startup.
    started: float = field(default_factory=time.time)

    def provider_def(self) -> dict:
        return provider_by_id(self.provider) or PROVIDERS[0]

    def api_key(self) -> str:
        """Current provider's API key: keyring/config -> env fallback."""
        k = self.keys.get(self.provider, "")
        if k:
            return k
        return os.environ.get(provider_env(self.provider), "") or ""

    def gemini_base(self) -> str:
        """Base URL for Gemini requests: worker proxy if set, otherwise Google."""
        return self.worker_url or GEMINI_DIRECT_BASE


rt = Runtime()


# ── config.json ─────────────────────────────────────────────────────────
def load_config(keyring_get, keyring_set) -> None:
    """Populate `rt` from config.json, the keyring and the environment.

    The keyring accessors are injected so this module does not depend on
    D-Bus; a legacy plaintext `api_key` in config.json is migrated into the
    keyring and dropped from the file on the next save.
    """
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            rt.config = loaded if isinstance(loaded, dict) else {}
    except (OSError, json.JSONDecodeError):
        rt.config = {}
    cfg = rt.config

    rt.provider = cfg.get("provider", "gemini")
    if provider_by_id(rt.provider) is None:
        rt.provider = "gemini"

    for p in PROVIDERS:
        pid = p["id"]
        key = keyring_get(pid)
        source = "keyring" if key else ""
        if not key and pid == "gemini" and cfg.get("api_key"):
            key = str(cfg["api_key"])
            source = "keyring" if keyring_set("gemini", key) else "config"
            if source == "keyring":
                cfg.pop("api_key", None)
        if not key:
            key = os.environ.get(p["env"], "")
            source = "env" if key else ""
        rt.keys[pid] = key
        rt.key_sources[pid] = source

    if cfg.get("worker_url"):
        rt.worker_url = str(cfg["worker_url"])
    elif os.environ.get("GEMINI_WORKER_URL"):
        rt.worker_url = os.environ["GEMINI_WORKER_URL"]
    if cfg.get("anthropic_url"):
        rt.anthropic_url = str(cfg["anthropic_url"])
    if cfg.get("openai_url"):
        rt.openai_url = str(cfg["openai_url"])
    if cfg.get("system_instruction"):
        rt.system_instruction = str(cfg["system_instruction"])
    rt.model = cfg.get("model") or rt.provider_def()["default_model"]


def save_config() -> None:
    data = {k: v for k, v in rt.config.items() if k != "api_key"}
    data["provider"] = rt.provider
    data["model"] = rt.model
    try:
        write_private(CONFIG_FILE, json.dumps(data, indent=2, ensure_ascii=False))
    except OSError:
        pass


def write_private(path: str, text: str) -> None:
    """Write a daemon state file with 0600 perms, creating its directory."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(path, 0o600)
