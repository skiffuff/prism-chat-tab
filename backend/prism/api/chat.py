"""/chat and /tool/confirm: the model loop with the confirmed run_bash tool."""

import time
import threading

from fastapi import APIRouter, Request

from .. import providers
from ..providers.canonical import first_tool_call, result_part, text_of
from ..screen import clean_response_text, start_recording, user_env, wants_screen
from ..security import (evaluate, grant_pattern, pending_confirm, pending_lock,
                        rate_limited, redact, register_pending, run_bash, expire_pending)
from ..sessions import (MAX_TURNS, active_session, find_session, record_quota_error,
                        record_round, save_sessions, set_session_title)
from ..config import rt
from .common import authed, bad_request, json_body, reply, unauthorized

router = APIRouter()

MAX_ROUNDS = 10          # tool rounds per request
MAX_ATTACHMENTS = 8
MAX_ATTACHMENT_B64 = 15_000_000  # ~11 MB raw per file


def _auto_title(session_id: str, first_text: str) -> None:
    def work():
        title = providers.generate_chat_title(first_text)
        if title:
            set_session_title(session_id, title)
    threading.Thread(target=work, daemon=True).start()


def model_loop(provider: str, model: str, sess: dict) -> dict:
    """Run model rounds until the model answers or asks to run a command.

    Returns one of {"response": text}, {"pending": payload}, {"error": err}.
    Auto-approved commands (a stored allow-pattern) run inline; anything else
    is parked for /tool/confirm.
    """
    hist = sess["messages"]
    for _ in range(MAX_ROUNDS):
        parts, err, um = providers.call_model(provider, hist)
        if err:
            return {"error": err}
        hist.append({"role": "assistant", "parts": parts})
        sess["updated"] = time.time()
        save_sessions()
        in_t, out_t = providers.usage_tokens(provider, um)
        record_round(model, provider, in_t, out_t)

        args, tool_id, name = first_tool_call(parts)
        if name == "run_bash" and args is not None:
            cmd = str(args.get("command", ""))
            verdict = evaluate(cmd)
            if verdict["action"] == "deny":
                # Could never run (or the user has a deny-rule): tell the
                # model why instead of asking the user about it.
                print(f"⛔ [REFUSED]: {redact(cmd)} — {verdict['reason']}")
                result = f"Command refused: {verdict['reason']}"
            elif verdict["action"] == "allow":
                print(f"🔧 [EXEC] ({verdict['rule']}): {redact(cmd)}")
                result = run_bash(cmd, user_env())
            else:
                payload = register_pending(tool_id, cmd, sess["id"], provider, model, verdict)
                print(f"⏳ [PENDING]: {redact(cmd)}")
                return {"pending": payload}
            hist.append({"role": "user", "parts": [result_part(provider, tool_id, result)]})
            save_sessions()
            continue
        return {"response": clean_response_text(text_of(parts))}


DENIED_RESULT = "Пользователь отклонил выполнение команды. Объясни это пользователю и не выполняй команду."
TIMED_OUT_RESULT = "Пользователь не ответил на запрос подтверждения, команда не выполнена. Спроси, нужно ли повторить."


def settle_expired() -> None:
    """Record a denial for prompts nobody answered, so the conversation is
    never left with a tool call that has no result."""
    for pend in expire_pending():
        sess = find_session(pend.get("session_id"))
        if not sess:
            continue
        sess["messages"].append({"role": "user", "parts": [result_part(
            pend.get("provider") or rt.provider, pend["tool_id"], TIMED_OUT_RESULT)]})
        sess["updated"] = time.time()
        print(f"⌛ [TIMEOUT] confirmation for: {redact(pend.get('command', ''))}")
    save_sessions()
    return {"error": {"message": "Request processing iteration count exceeded."}}


@router.post("/chat")
async def chat(request: Request):
    if not authed(request):
        return unauthorized()
    settle_expired()
    if rate_limited(request):
        return reply({"error": "rate_limited", "message": "Too many requests. Try again in a minute."}, 429)
    data = await json_body(request)
    if data is None:
        return bad_request("Invalid JSON body")

    provider, model = rt.provider, rt.model
    user_message = data.get("message", "")
    if not isinstance(user_message, str):
        user_message = ""
    attachments = data.get("attachments") or []
    if not isinstance(attachments, list):
        attachments = []
    attach_parts = []
    for a in attachments[:MAX_ATTACHMENTS]:
        if not isinstance(a, dict):
            continue
        d = a.get("data") or ""
        if not isinstance(d, str) or not d or len(d) > MAX_ATTACHMENT_B64:
            continue
        attach_parts.append({"type": "image", "mime": str(a.get("mime") or "application/octet-stream"), "data": d})
    if not user_message and not attach_parts:
        return bad_request("Empty message")

    try:
        sess = active_session()
        hist = sess["messages"]
        hist.append({"role": "user", "parts": attach_parts + ([{"type": "text", "text": user_message}] if user_message else [])})
        # "New chat" is the placeholder new_session() starts with, not a title
        if sess.get("title") in ("", None, "New chat"):
            first = attachments[0].get("filename") if attachments and isinstance(attachments[0], dict) else ""
            t0 = user_message.strip() or first or "Chat"
            sess["title"] = t0[:48]
            _auto_title(sess["id"], t0)
        sess["updated"] = time.time()
        if len(hist) > MAX_TURNS:
            del hist[:len(hist) - MAX_TURNS]
        depth = len(hist)

        outcome = model_loop(provider, model, sess)
        if "error" in outcome:
            err = outcome["error"]
            # Roll the user's turn back when nothing came of it, so a failed
            # request does not litter the history.
            if len(hist) == depth and hist and hist[-1].get("role") == "user":
                hist.pop()
                save_sessions()
            msg = redact(providers.error_message(err))
            if providers.is_quota_error(err):
                record_quota_error(msg)
            return reply({"error": msg})
        if "pending" in outcome:
            return reply(outcome["pending"])
        text = outcome["response"]
        if wants_screen(user_message):
            text += "\n\n👁 Включаю просмотр вашего экрана — подсказки будут появляться здесь. Остановить можно кнопкой сверху."
            start_recording(user_message)
        return reply({"response": text})
    except Exception as e:
        print(f"\n[ERROR]: {redact(e)}\n")
        return reply({"error": "Internal server error. Check daemon logs."})


@router.post("/tool/confirm")
async def tool_confirm(request: Request):
    """Resolve a pending run_bash confirmation.

    Body: {"tool_call_id": "...", "decision": "allow"|"deny"|"never",
           "pattern": "..."}   # optional, for "never": which offered pattern to store
    """
    if not authed(request):
        return unauthorized()
    data = await json_body(request)
    if data is None:
        return bad_request("Invalid JSON body")
    tool_call_id = data.get("tool_call_id") or ""
    decision = data.get("decision") or ""
    if decision not in ("allow", "deny", "never"):
        return bad_request('decision must be one of "allow", "deny", "never"')
    if not tool_call_id or not isinstance(tool_call_id, str):
        return bad_request("tool_call_id is required")
    pattern = data.get("pattern")
    if pattern is not None and not isinstance(pattern, str):
        return bad_request("pattern must be a string")

    settle_expired()
    with pending_lock:
        pend = pending_confirm.get(tool_call_id)
        if not pend:
            return reply({"error": "No pending confirmation for this tool call, or it already expired."}, 404)
        if pend.get("resolved") is not None:
            if pend.get("timed_out"):
                return reply({"error": "This confirmation expired unanswered; the command was not run."}, 410)
            return reply({"error": "This confirmation was already resolved."}, 409)
        pend["resolved"] = decision
        pend["resolved_at"] = time.time()

    cmd = pend.get("command", "")
    provider = pend.get("provider") or rt.provider
    model = pend.get("model") or rt.model
    sess = find_session(pend.get("session_id")) or active_session()
    hist = sess["messages"]

    if decision == "deny":
        print(f"⛔ [DENIED] by user: {redact(cmd)}")
        hist.append({"role": "user", "parts": [result_part(provider, tool_call_id, DENIED_RESULT)]})
    else:
        if decision == "never":
            # Stores the chosen (or the most general) offered pattern. Refused
            # for dangerous or network commands; the command still runs once.
            if grant_pattern(cmd, pattern):
                print(f"📌 [RULE] allow {redact(pattern or '')} for: {redact(cmd)}")
        print(f"🔧 [EXEC]: {redact(cmd)}")
        hist.append({"role": "user", "parts": [result_part(provider, tool_call_id, run_bash(cmd, user_env()))]})
    sess["updated"] = time.time()
    save_sessions()

    outcome = model_loop(provider, model, sess)
    if "error" in outcome:
        print(f"⚠ [MODEL-ERR] continuation: {redact(providers.error_message(outcome['error']))}")
        return reply({"error": "Model call failed", "detail": "See daemon logs"}, 502)
    if "pending" in outcome:
        return reply(outcome["pending"])
    return reply({"response": outcome["response"]})
