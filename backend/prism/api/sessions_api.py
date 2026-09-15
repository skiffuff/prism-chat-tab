"""Chat session management."""

from fastapi import APIRouter, Request

from .. import sessions
from .common import authed, bad_request, json_body, reply, unauthorized

router = APIRouter()


async def _session_id(request: Request):
    body = await json_body(request)
    sid = body.get("id") if body else None
    return sid if isinstance(sid, str) and sid else None


@router.get("/history")
async def get_history(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({"history": sessions.active_session()["messages"]})


@router.post("/clear")
async def clear_history(request: Request):
    if not authed(request):
        return unauthorized()
    sessions.clear_active()
    return reply({"ok": True})


@router.get("/sessions")
async def get_sessions(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({"sessions": sessions.sessions_meta(), "active_id": sessions.store["active_id"]})


@router.post("/session/new")
async def new_session(request: Request):
    if not authed(request):
        return unauthorized()
    s = sessions.new_session()
    return reply({"ok": True, "active_id": s["id"]})


@router.post("/session/select")
async def select_session(request: Request):
    if not authed(request):
        return unauthorized()
    sid = await _session_id(request)
    if sid is None:
        return bad_request("id is required")
    if not sessions.select_session(sid):
        return reply({"error": "not found"}, 404)
    return reply({"ok": True})


@router.post("/session/rename")
async def rename_session(request: Request):
    if not authed(request):
        return unauthorized()
    body = await json_body(request)
    sid = body.get("id") if body else None
    title = body.get("title") if body else None
    if not isinstance(sid, str) or not sid:
        return bad_request("id is required")
    title = (title if isinstance(title, str) else "").strip()
    if not sessions.rename_session(sid, title):
        return reply({"error": "not found"}, 404)
    return reply({"ok": True})


@router.post("/session/delete")
async def delete_session(request: Request):
    if not authed(request):
        return unauthorized()
    sid = await _session_id(request)
    if sid is None:
        return bad_request("id is required")
    sessions.delete_session(sid)
    return reply({"ok": True})
