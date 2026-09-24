"""Provider dispatch: one model round, usage accounting and auxiliary
completions, routed by provider id."""

import re

from ..config import rt
from . import anthropic, gemini, ollama, openai

_BACKENDS = {"gemini": gemini, "anthropic": anthropic, "openai": openai, "ollama": ollama}


def backend(provider: str = None):
    return _BACKENDS.get(provider or rt.provider, gemini)


def call_model(provider: str, messages):
    """Dispatch one model round to the provider's wire format.

    Returns (parts, error, usage_metadata); parts is None on error.
    """
    return backend(provider).call(messages)


def resolve_model(provider: str, model: str) -> str:
    """Let a backend correct a stored model name (Ollama's catalogue is
    whatever is pulled locally); providers with a fixed one keep it."""
    fn = getattr(backend(provider), "resolve_model", None)
    return fn(model) if fn else model


def usage_tokens(provider: str, um) -> tuple:
    try:
        return backend(provider).usage_tokens(um or {})
    except Exception:
        return 0, 0


def is_quota_error(err) -> bool:
    msg = err.get("message", "") if isinstance(err, dict) else str(err)
    code = err.get("code") if isinstance(err, dict) else None
    status = str(err.get("status", "")) if isinstance(err, dict) else ""
    return "quota" in str(msg).lower() or code == 429 or "RESOURCE" in status.upper()


def error_message(err) -> str:
    return err.get("message", str(err)) if isinstance(err, dict) else str(err)


def generate_chat_title(first_text: str) -> str:
    """Short AI-generated chat title, provider-agnostic."""
    prompt = ("Come up with a short title for this chat based on the user's first message. "
              "Requirements: 3-6 words, in English, no quotes, no trailing period, no explanations - title only.\n\n"
              f"First message: {first_text[:200]}")
    try:
        title = backend().complete_text(prompt, max_tokens=64, timeout=30,
                                        system="You only output short chat titles.").strip()
        title = re.sub(r'^["\']+|["\']+$', "", title).strip()
        title = re.sub(r"[«»\"]+", "", title).strip()
        return title[:48]
    except Exception:
        return ""
