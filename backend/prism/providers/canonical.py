"""Provider-neutral message blocks.

Storage keeps BOTH legacy Gemini wire parts and canonical blocks; every
provider converts a history to canonical form before building its request.
Canonical block types: text / image / tool_use / tool_result.
"""

import uuid


def canonical_blocks(parts) -> list:
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
        elif isinstance(pt.get("functionCall"), dict):
            fc = pt["functionCall"]
            out.append({"type": "tool_use", "id": fc.get("id") or pt.get("id", ""),
                        "name": fc.get("name", "run_bash"),
                        "input": fc.get("args", {}),
                        "thought_signature": pt.get("thoughtSignature", "")})
        elif "functionResponse" in pt:
            out.append({"type": "tool_result", "tool_use_id": "",
                        "name": "run_bash",
                        "content": str(pt["functionResponse"].get("response", {}).get("result", ""))})
    return out


def new_tool_id(prefix: str = "toolu") -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def first_tool_call(parts):
    """Find the run_bash call in a model turn.

    Returns (args, tool_id, name) or (None, "", ""). Gemini functionCall parts
    without an id get one assigned in place so the result can be paired.
    """
    for pt in parts:
        if not isinstance(pt, dict):
            continue
        if pt.get("type") == "tool_use":
            if pt.get("name", "run_bash") == "run_bash":
                return pt.get("input", {}) or {}, pt.get("id", ""), "run_bash"
        elif isinstance(pt.get("functionCall"), dict) and pt["functionCall"].get("name") == "run_bash":
            fc = pt["functionCall"]
            tid = fc.get("id") or pt.get("id", "")
            if not tid:
                tid = new_tool_id()
                fc["id"] = tid
            return fc.get("args", {}) or {}, tid, "run_bash"
    return None, "", ""


def text_of(parts) -> str:
    """Concatenate the text blocks of a model turn."""
    text = "".join(pt.get("text", "") for pt in parts
                   if isinstance(pt, dict) and (pt.get("type") == "text" or ("text" in pt and "type" not in pt)))
    return text


def result_part(provider: str, tool_id: str, content: str) -> dict:
    """Provider-correct tool_result part for the history."""
    if provider == "gemini":
        return {"functionResponse": {"name": "run_bash", "response": {"result": content}}}
    return {"type": "tool_result", "tool_use_id": tool_id, "name": "run_bash", "content": content}
