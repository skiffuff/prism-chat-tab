"""OpenAI ChatGPT (Chat Completions API)."""

import json
import re

import requests

from ..config import CHAT_TIMEOUT, rt
from ..security import redact
from .canonical import canonical_blocks, new_tool_id

# Chat Completions "function" tool. OpenAI validates the JSON schema strictly,
# so the types must be lowercase JSON Schema, not Gemini's OBJECT/STRING.
TOOLS = [{
    "type": "function",
    "function": {
        "name": "run_bash",
        "description": "Executes bash commands in Linux terminal.",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The bash command to run"
                }
            },
            "required": ["command"]
        }
    }
}]

UNANSWERED = "Команда не была выполнена: подтверждение пользователя не получено."

# /v1/models mixes chat models with embeddings, audio, image and moderation
# endpoints; keep only the ones Chat Completions will accept.
_NON_CHAT = ("embedding", "whisper", "tts", "dall-e", "moderation", "realtime",
             "audio", "transcribe", "image", "search", "instruct", "babbage",
             "davinci", "codex", "computer-use", "sora", "-preview", "deep-research")


def headers(key: str = None) -> dict:
    return {
        "Authorization": f"Bearer {rt.api_key() if key is None else key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def is_chat_model(model_id: str) -> bool:
    m = model_id.lower()
    if not (m.startswith("gpt-") or re.match(r"^o\d", m) or m.startswith("chatgpt-")):
        return False
    return not any(tag in m for tag in _NON_CHAT)


def is_reasoning_model(model: str) -> bool:
    """gpt-5 / o-series models accept reasoning_effort; the others reject it."""
    m = (model or "").lower()
    if "chat" in m:  # gpt-5-chat-latest is a plain chat model
        return False
    return m.startswith("gpt-5") or bool(re.match(r"^o\d", m))


def payload(messages, max_tokens: int, tools=None) -> dict:
    """Chat Completions request body. Temperature is left at the API default:
    reasoning models reject any other value, and max_tokens is deprecated in
    favour of max_completion_tokens across the whole family."""
    body = {
        "model": rt.model,
        "max_completion_tokens": max_tokens,
        "messages": messages,
    }
    if tools:
        body["tools"] = tools
        # One command per round: the tool loop executes a single run_bash
        # call and expects exactly one tool_call to answer.
        body["parallel_tool_calls"] = False
    if is_reasoning_model(rt.model):
        body["reasoning_effort"] = "low"
    return body


def _post(body: dict, timeout: int):
    return requests.post(f"{rt.openai_base()}/v1/chat/completions", json=body, headers=headers(), timeout=timeout)


def repair_tool_pairs(msgs: list) -> list:
    """Chat Completions rejects a history where a tool_calls turn has no tool
    replies, or a tool reply answers no call. Both happen legitimately here:
    the history window can cut between a call and its result, and an expired
    confirmation leaves a call without one. Drop orphan replies and answer
    unanswered calls with a placeholder so the request stays valid."""
    out = []
    pending = []  # tool_call ids awaiting a reply, in order
    for m in msgs:
        if m["role"] == "tool":
            if m["tool_call_id"] in pending:
                pending.remove(m["tool_call_id"])
                out.append(m)
            continue
        for tid in pending:
            out.append({"role": "tool", "tool_call_id": tid, "content": UNANSWERED})
        pending = [tc["id"] for tc in m.get("tool_calls", [])] if m["role"] == "assistant" else []
        out.append(m)
    for tid in pending:
        out.append({"role": "tool", "tool_call_id": tid, "content": UNANSWERED})
    return out


def build_messages(messages) -> list:
    """Canonical history -> Chat Completions messages.

    Tool results live in user-role turns in storage; OpenAI wants them as
    separate role=tool messages that directly follow the assistant turn that
    issued the call, so they are split out before any text of that turn.
    """
    out = [{"role": "system", "content": rt.system_instruction}]
    for m in messages:
        role = "assistant" if m["role"] != "user" else "user"
        content, tool_calls, tool_results = [], [], []
        for b in canonical_blocks(m.get("parts", [])):
            t = b.get("type")
            if t == "text":
                if b.get("text"):
                    content.append({"type": "text", "text": b["text"]})
            elif t == "image":
                mime = b.get("mime", "image/png")
                if mime.startswith("image/"):
                    content.append({"type": "image_url",
                                    "image_url": {"url": f"data:{mime};base64,{b.get('data', '')}"}})
                else:
                    content.append({"type": "text", "text": "[Прикреплённый файл]"})
            elif t == "tool_use":
                tool_calls.append({
                    "id": b.get("id") or new_tool_id("call"),
                    "type": "function",
                    "function": {"name": b.get("name", "run_bash"),
                                 "arguments": json.dumps(b.get("input", {}), ensure_ascii=False)},
                })
            elif t == "tool_result":
                tool_results.append({"role": "tool",
                                     "tool_call_id": b.get("tool_use_id") or "",
                                     "content": str(b.get("content", ""))})
        if role == "assistant":
            if not content and not tool_calls:
                continue
            msg = {"role": "assistant", "content": "".join(c["text"] for c in content) or None}
            if tool_calls:
                msg["tool_calls"] = tool_calls
            out.append(msg)
        else:
            out.extend(tool_results)
            if content:
                # A text-only turn can be a plain string; keep the array form
                # only when an image is attached.
                if all(c["type"] == "text" for c in content):
                    out.append({"role": "user", "content": "".join(c["text"] for c in content)})
                else:
                    out.append({"role": "user", "content": content})
    return repair_tool_pairs(out)


def _message_text(msg: dict) -> str:
    text = msg.get("content")
    if isinstance(text, list):  # some proxies echo the array form back
        text = "".join(p.get("text", "") for p in text if isinstance(p, dict))
    return text or ""


def call(messages):
    """One chat round. Returns (blocks, error, usage)."""
    if not rt.api_key() and rt.provider_def().get("needs_key", True):
        return None, {"message": "OpenAI API key is not set. Add it in the chat settings."}, {}
    body = payload(build_messages(messages), 10000, tools=TOOLS)
    try:
        res = _post(body, CHAT_TIMEOUT)
        data = res.json()
    except (requests.RequestException, ValueError) as e:
        return None, {"message": redact(e)}, {}
    if res.status_code >= 400 or "error" in data:
        err = data.get("error", {})
        if isinstance(err, dict):
            return None, {"message": err.get("message", str(err)), "code": res.status_code,
                          "status": err.get("type") or err.get("code") or "ERROR"}, {}
        return None, {"message": redact(data), "code": res.status_code}, {}
    choices = data.get("choices") or []
    if not choices:
        return None, {"message": "OpenAI returned no choices"}, {}
    msg = choices[0].get("message", {}) or {}
    blocks = []
    text = _message_text(msg)
    if text:
        blocks.append({"type": "text", "text": text})
    # Only the first tool call is kept: the loop answers one call per round and
    # Chat Completions rejects a history with unanswered tool_call ids.
    for tc in (msg.get("tool_calls") or [])[:1]:
        fn = tc.get("function", {}) or {}
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except (TypeError, ValueError):
            args = {"command": fn.get("arguments") or ""}
        if not isinstance(args, dict):
            args = {"command": str(args)}
        blocks.append({"type": "tool_use", "id": tc.get("id") or new_tool_id("call"),
                       "name": fn.get("name", "run_bash"), "input": args})
    return blocks, "", data.get("usage", {})


def complete(messages: list, max_tokens: int, timeout: int) -> str:
    """Plain-text completion for auxiliary requests (titles, screen summary)."""
    res = _post(payload(messages, max_tokens), timeout)
    data = res.json()
    if res.status_code >= 400 or "error" in data:
        return ""
    return _message_text((data.get("choices") or [{}])[0].get("message", {}) or {})


def complete_text(prompt: str, max_tokens: int, timeout: int, system: str = None) -> str:
    msgs = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": prompt}]
    return complete(msgs, max_tokens, timeout)


def describe_frame(frame_b64: str, prompt: str, timeout: int = 60) -> str:
    """Chat Completions takes images but not video: summarise one frame."""
    content = []
    if frame_b64:
        content.append({"type": "image_url", "image_url": {"url": f"data:image/png;base64,{frame_b64}"}})
    content.append({"type": "text", "text": prompt})
    return complete([{"role": "system", "content": rt.system_instruction},
                     {"role": "user", "content": content}], 1024, timeout)


def list_models(timeout: int = 5) -> list:
    res = requests.get(f"{rt.openai_base()}/v1/models", headers=headers(), timeout=timeout)
    if res.status_code != 200:
        return []
    ids = sorted(m.get("id", "") for m in res.json().get("data", []))
    return [{"id": m, "label": m} for m in ids if is_chat_model(m)]


def validate_key(key: str) -> dict:
    if not (isinstance(key, str) and key.strip().startswith("sk-")):
        return {"valid": False, "error": "Invalid OpenAI API key format"}
    r = requests.get(f"{rt.openai_base()}/v1/models", headers=headers(key.strip()), timeout=10)
    if r.status_code == 200:
        n = sum(1 for m in r.json().get("data", []) if is_chat_model(m.get("id", "")))
        return {"valid": True, "models": n}
    return {"valid": False, "error": f"HTTP {r.status_code}"}


def usage_tokens(um: dict) -> tuple:
    return um.get("prompt_tokens", 0), um.get("completion_tokens", 0)
