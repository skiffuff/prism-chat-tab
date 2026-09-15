"""Google Gemini (generateContent), directly or through the Cloudflare worker."""

import requests

from ..config import CHAT_TIMEOUT, rt
from ..security import redact
from .canonical import canonical_blocks

# Gemini function declaration for run_bash
TOOL_DECLARATION = {
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

_HEADERS = {"Content-Type": "application/json; charset=utf-8"}


def auth(path: str, key: str = None) -> tuple:
    """Build (url, auth_headers) for a Gemini endpoint.

    Talking to Google directly, the key goes in the `x-goog-api-key` header
    so the credential never sits in a URL (the part most likely to be copied
    into logs and tracebacks). A configured worker proxy keeps the historical
    `?key=` query form, because that is the contract the worker was written
    against.
    """
    k = rt.api_key() if key is None else key
    base = rt.gemini_base()
    if rt.worker_url:
        sep = "&" if "?" in path else "?"
        return f"{base}{path}{sep}key={k}", {}
    return f"{base}{path}", {"x-goog-api-key": k}


def build_contents(messages, keep_inline_last_only: bool = True) -> list:
    contents = []
    for idx, m in enumerate(messages):
        is_last = idx == len(messages) - 1
        role = "model" if m["role"] != "user" else "user"
        new_parts = []
        for b in canonical_blocks(m.get("parts", [])):
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
                fc = {"name": b.get("name", "run_bash"), "args": b.get("input", {})}
                if b.get("id"):
                    fc["id"] = b["id"]
                out_part = {"functionCall": fc}
                if b.get("thought_signature"):
                    out_part["thoughtSignature"] = b["thought_signature"]
                new_parts.append(out_part)
            elif t == "tool_result":
                new_parts.append({"functionResponse": {"name": b.get("name", "run_bash"),
                                                       "response": {"result": b.get("content", "")}}})
        contents.append({"role": role, "parts": new_parts})
    return contents


def _post(payload: dict, timeout: int):
    endpoint, headers = auth(f"/v1beta/models/{rt.model}:generateContent")
    return requests.post(endpoint, json=payload, headers={**_HEADERS, **headers}, timeout=timeout)


def call(messages):
    """One chat round. Returns (parts, error, usage_metadata)."""
    empty_usage = {"promptTokenCount": 0, "candidatesTokenCount": 0}
    if not rt.api_key():
        return None, {"message": "Google AI Studio key is not set. Add it in the chat settings."}, {}
    payload = {
        "contents": build_contents(messages),
        "system_instruction": {"parts": [{"text": rt.system_instruction}]},
        "tools": [TOOL_DECLARATION],
        "generationConfig": {"temperature": 0.7, "topP": 0.95},
    }
    try:
        res = _post(payload, CHAT_TIMEOUT)
    except requests.RequestException as e:
        # The exception text carries the request URL, i.e. the key on the
        # worker path — never let it through unredacted.
        return None, {"message": redact(e)}, empty_usage
    try:
        data = res.json()
    except ValueError:
        return None, {"message": f"HTTP {res.status_code}: non-JSON response"}, empty_usage
    if "error" in data:
        return None, data["error"], empty_usage
    try:
        cand = data["candidates"][0]["content"]
    except (KeyError, IndexError, TypeError):
        return None, {"message": "Gemini returned no candidates"}, empty_usage
    return cand.get("parts", []), "", data.get("usageMetadata", {})


def complete_text(prompt: str, max_tokens: int, timeout: int, system: str = None) -> str:
    """Plain-text completion for auxiliary requests (titles)."""
    payload = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.8, "topP": 0.95, "maxOutputTokens": max_tokens},
    }
    if system:
        payload["system_instruction"] = {"parts": [{"text": system}]}
    res = _post(payload, timeout)
    data = res.json()
    return data["candidates"][0]["content"]["parts"][0]["text"]


def describe_video(video_b64: str, prompt: str, timeout: int = 60) -> str:
    """Summarise a screen recording (Gemini takes the video inline)."""
    payload = {
        "contents": [{
            "role": "user",
            "parts": [
                {"inline_data": {"mime_type": "video/mp4", "data": video_b64}},
                {"text": prompt},
            ],
        }],
        "system_instruction": {"parts": [{"text": rt.system_instruction}]},
        "generationConfig": {"maxOutputTokens": 150},
    }
    res = _post(payload, timeout)
    data = res.json()
    cand = data.get("candidates", [{}])[0].get("content", {})
    return next((pt.get("text", "") for pt in cand.get("parts", []) if pt.get("text")), "")


def list_models(timeout: int = 5) -> list:
    url, headers = auth("/v1beta/models")
    res = requests.get(url, headers=headers, timeout=timeout)
    models = []
    if res.status_code == 200:
        for m in res.json().get("models", []):
            name = m.get("name", "").replace("models/", "")
            methods = m.get("supportedGenerationMethods", [])
            if "generateContent" in methods and ("gemini" in name.lower() or "gemma" in name.lower()):
                models.append({"id": name, "label": m.get("displayName") or name})
    return models


def validate_key(key: str) -> dict:
    url, headers = auth("/v1beta/models", key=key)
    r = requests.get(url, headers=headers, timeout=10)
    if r.status_code == 200:
        return {"valid": True, "models": len(r.json().get("models", []))}
    return {"valid": False, "error": f"HTTP {r.status_code}"}


def usage_tokens(um: dict) -> tuple:
    return um.get("promptTokenCount", 0), um.get("candidatesTokenCount", 0)
