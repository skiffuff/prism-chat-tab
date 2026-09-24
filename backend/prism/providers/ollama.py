"""Ollama: models served from the user's own machine.

Ollama exposes OpenAI's Chat Completions API, so the whole wire format comes
from the openai backend; only the endpoint, the model list and the absent API
key are different. Everything stays on localhost.
"""

import requests

from ..config import rt
from . import openai
from .openai import complete, complete_text, describe_frame, usage_tokens  # noqa: F401


def call(messages):
    """One chat round, guarded: an empty catalogue means nothing is pulled."""
    if not rt.model:
        return None, {"message": "No model yet - run `ollama pull <model>`, then pick it in the model list."}, {}
    return openai.call(messages)


def list_models(timeout: int = 5) -> list:
    """Whatever `ollama list` shows, in alphabetical order."""
    try:
        res = requests.get(f"{rt.ollama_url}/v1/models", timeout=timeout)
        if res.status_code != 200:
            return []
        ids = sorted(m.get("id", "") for m in res.json().get("data", []))
    except (requests.RequestException, ValueError):
        return []
    return [{"id": m, "label": m} for m in ids if m]


def resolve_model(model: str) -> str:
    """Local installs have no fixed catalogue: keep the chosen model while it
    is still pulled, otherwise fall back to the first one Ollama reports."""
    ids = [m["id"] for m in list_models()]
    if model in ids or not ids:
        return model
    return ids[0]


def validate_key(key: str = "") -> dict:
    """No key to check; report whether the local server answers instead."""
    models = list_models()
    if models:
        return {"valid": True, "models": len(models)}
    return {"valid": False, "error": f"No answer from Ollama at {rt.ollama_url}"}
