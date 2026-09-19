"""Chat sessions (sessions.json) and usage counters (prism_usage.json)."""

import json
import os
import threading
import time

from .config import SESSIONS_FILE, USAGE_FILE, write_private

DEFAULT_DAILY_LIMIT = 20
MAX_TURNS = 40  # history window sent to the model



def _new_session() -> dict:
    return {"id": str(time.time()), "title": "New chat", "updated": time.time(), "messages": []}


def _load_sessions() -> dict:
    try:
        if os.path.exists(SESSIONS_FILE):
            with open(SESSIONS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and isinstance(data.get("sessions"), list):
                return data
    except (OSError, ValueError):
        pass
    return {"sessions": [_new_session()], "active_id": None}


store = _load_sessions()
store_lock = threading.Lock()
if not store["sessions"]:
    store["sessions"] = [_new_session()]
if not store.get("active_id") or not any(s["id"] == store["active_id"] for s in store["sessions"]):
    store["active_id"] = store["sessions"][0]["id"]


def save_sessions() -> None:
    try:
        write_private(SESSIONS_FILE, json.dumps(store, ensure_ascii=False, indent=2))
    except OSError:
        pass


def active_session() -> dict:
    aid = store.get("active_id")
    for s in store["sessions"]:
        if s["id"] == aid:
            return s
    return store["sessions"][0]


def find_session(session_id) -> dict | None:
    for s in store["sessions"]:
        if s["id"] == session_id:
            return s
    return None


def new_session() -> dict:
    s = _new_session()
    with store_lock:
        store["sessions"].insert(0, s)
        store["active_id"] = s["id"]
        save_sessions()
    return s


def select_session(session_id) -> bool:
    with store_lock:
        if find_session(session_id) is None:
            return False
        store["active_id"] = session_id
        save_sessions()
        return True


def rename_session(session_id, title: str) -> bool:
    with store_lock:
        s = find_session(session_id)
        if s is None:
            return False
        s["title"] = title[:48]
        save_sessions()
        return True


def set_session_title(session_id, title: str) -> None:
    with store_lock:
        s = find_session(session_id)
        if s is not None:
            s["title"] = title[:48]
            save_sessions()


def delete_session(session_id) -> None:
    with store_lock:
        sessions = store["sessions"]
        if len(sessions) <= 1:
            sessions[0] = _new_session()
            store["active_id"] = sessions[0]["id"]
        else:
            store["sessions"] = [s for s in sessions if s["id"] != session_id]
            if store["active_id"] == session_id:
                store["active_id"] = store["sessions"][0]["id"]
        save_sessions()


def clear_active() -> None:
    with store_lock:
        s = active_session()
        s["messages"] = []
        s["title"] = ""
        save_sessions()


def sessions_meta() -> list:
    return [{"id": s["id"], "title": s["title"] or "New chat", "updated": s.get("updated", 0)}
            for s in store["sessions"]]


# ── Usage counters ──────────────────────────────────────────────────────
usage = {"date": "", "requests": 0, "prompt_tokens": 0, "output_tokens": 0,
         "by_model": {}, "quota_exceeded": False, "last_error": "", "limits": {}}


def load_usage() -> None:
    try:
        if os.path.exists(USAGE_FILE):
            with open(USAGE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                usage.update(data)
    except (OSError, ValueError):
        pass


def save_usage() -> None:
    try:
        write_private(USAGE_FILE, json.dumps(usage))
    except OSError:
        pass


def record_round(model: str, provider: str, in_tokens: int, out_tokens: int) -> None:
    """Count one successful model round against the model's tally."""
    usage["requests"] += 1
    usage["prompt_tokens"] += in_tokens
    usage["output_tokens"] += out_tokens
    usage["quota_exceeded"] = False
    usage["last_error"] = ""
    bm = usage["by_model"].get(model)
    if not isinstance(bm, dict):
        bm = {"requests": int(bm or 0)}
    bm["requests"] = bm.get("requests", 0) + 1
    bm["provider"] = provider
    bm["prompt_tokens"] = bm.get("prompt_tokens", 0) + in_tokens
    bm["output_tokens"] = bm.get("output_tokens", 0) + out_tokens
    usage["by_model"][model] = bm
    save_usage()


def record_quota_error(message: str) -> None:
    """Remember a quota failure (and any per-model limit it mentions)."""
    import re
    usage["quota_exceeded"] = True
    usage["last_error"] = message
    m = re.search(r"limit:\s*(\d+)[^,]*,?\s*model:\s*([\w.\-]+)", message)
    if m:
        usage.setdefault("limits", {})[m.group(2)] = int(m.group(1))
    save_usage()


load_usage()
