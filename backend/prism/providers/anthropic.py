"""Anthropic Claude (Messages API)."""

import requests

from ..config import CHAT_TIMEOUT, rt
from ..security import redact
from .canonical import canonical_blocks, new_tool_id

TOOLS = [{
    "name": "run_bash",
    "description": "Executes bash commands in Linux terminal.",
    "input_schema": {
        "type": "object",
        "properties": {
            "command": {
                "type": "string",
                "description": "The bash command to run"
            }
        },
        "required": ["command"]
    }
}]


def headers() -> dict:
    return {
        "x-api-key": rt.api_key(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "accept": "application/json",
    }


def build_messages(messages) -> list:
    out = []
    for m in messages:
        role = "assistant" if m["role"] != "user" else "user"
        blocks = []
        for b in canonical_blocks(m.get("parts", [])):
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
                               "id": b.get("id") or new_tool_id(),
                               "name": b.get("name", "run_bash"),
                               "input": b.get("input", {})})
            elif t == "tool_result":
                blocks.append({"type": "tool_result",
                               "tool_use_id": b.get("tool_use_id") or new_tool_id(),
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


def _post(payload: dict, timeout: int):
    return requests.post(f"{rt.anthropic_url}/v1/messages", json=payload, headers=headers(), timeout=timeout)


def _text(data: dict) -> str:
    return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")


def call(messages):
    """One chat round. Returns (blocks, error, usage)."""
    if not rt.api_key():
        return None, {"message": "Claude API key is not set. Add it in the chat settings."}, {}
    payload = {
        "model": rt.model,
        "max_tokens": 10000,
        "temperature": 0.7,
        "system": rt.system_instruction,
        "messages": build_messages(messages),
        "tools": TOOLS,
    }
    try:
        res = _post(payload, CHAT_TIMEOUT)
        data = res.json()
    except (requests.RequestException, ValueError) as e:
        return None, {"message": redact(e)}, {}
    if res.status_code >= 400 or data.get("type") == "error":
        err = data.get("error", {})
        if isinstance(err, dict):
            return None, {"message": err.get("message", str(err)), "code": res.status_code,
                          "status": data.get("type", "ERROR")}, {}
        return None, {"message": redact(data)}, {}
    blocks = []
    for b in data.get("content", []):
        t = b.get("type")
        if t == "text":
            blocks.append({"type": "text", "text": b.get("text", "")})
        elif t == "tool_use":
            blocks.append({"type": "tool_use", "id": b.get("id", ""),
                           "name": b.get("name", "run_bash"), "input": b.get("input", {})})
    return blocks, "", data.get("usage", {})


def complete_text(prompt: str, max_tokens: int, timeout: int, system: str = None) -> str:
    payload = {
        "model": rt.model,
        "max_tokens": max_tokens,
        "temperature": 0.8,
        "messages": [{"role": "user", "content": prompt}],
    }
    if system:
        payload["system"] = system
    res = _post(payload, timeout)
    return _text(res.json())


def describe_frame(frame_b64: str, prompt: str, timeout: int = 60) -> str:
    """Summarise a screen recording from one extracted frame."""
    blocks = []
    if frame_b64:
        blocks.append({"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": frame_b64}})
    blocks.append({"type": "text", "text": prompt})
    payload = {
        "model": rt.model,
        "max_tokens": 1024,
        "system": rt.system_instruction,
        "messages": [{"role": "user", "content": blocks}],
    }
    res = _post(payload, timeout)
    return _text(res.json())


def validate_key(key: str) -> dict:
    # Anthropic exposes no model-list endpoint, and a probe message would be
    # billed, so only the key shape is checked.
    if isinstance(key, str) and key.strip().startswith("sk-ant-"):
        return {"valid": True, "validated": False}
    return {"valid": False, "error": "Invalid Claude API key format"}


def usage_tokens(um: dict) -> tuple:
    return um.get("input_tokens", 0), um.get("output_tokens", 0)
