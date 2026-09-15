"""Screen watching controls and the unauthenticated health probe."""

from fastapi import APIRouter, Request

from ..config import rt
from ..screen import is_recording, start_recording, stop_recording_and_analyze
from .common import authed, reply, unauthorized

router = APIRouter()


@router.post("/watch/start")
async def watch_start(request: Request):
    if not authed(request):
        return unauthorized()
    start_recording()
    return reply({"ok": True, "active": is_recording()})


@router.post("/watch/stop")
async def watch_stop(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({"ok": True, "active": False, "response": stop_recording_and_analyze()})


@router.get("/watch/status")
async def watch_status(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({"active": is_recording(), "hint": "", "updated": 0})


@router.get("/health")
async def health():
    # `started` lets a long-lived client notice a restart and refetch what
    # it cached at startup (providers, models, settings).
    return reply({"status": "ok", "started": rt.started})
