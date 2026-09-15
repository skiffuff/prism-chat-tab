"""Attachments: read a file by path (policy-checked), pick one in a dialog,
or grab the clipboard image."""

import base64
import os

from fastapi import APIRouter, Request

from ..screen import clipboard_image, pick_file_dialog
from ..security import READ_FILE_MAX_BYTES, allowed_read_path, is_sensitive_path
from .common import authed, bad_request, json_body, reply, unauthorized

router = APIRouter()

_MIME_BY_EXT = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
    ".gif": "image/gif", ".mp4": "video/mp4", ".webm": "video/webm",
    ".txt": "text/plain", ".py": "text/plain", ".qml": "text/plain", ".js": "text/plain",
    ".json": "text/plain", ".md": "text/plain", ".sh": "text/plain", ".lua": "text/plain",
    ".nix": "text/plain", ".toml": "text/plain", ".yaml": "text/plain", ".yml": "text/plain",
}


def guess_mime(path: str) -> str:
    return _MIME_BY_EXT.get(os.path.splitext(path)[1].lower(), "application/octet-stream")


def _file_payload(path: str):
    """Read a file into the attachment payload, or an error tuple.

    Size is capped: the payload is base64-encoded into JSON and then into
    the model request, so an unbounded read was a cheap way to exhaust
    memory on both sides.
    """
    try:
        size = os.path.getsize(path)
    except OSError:
        return None, ("not_found", 404)
    if size > READ_FILE_MAX_BYTES:
        return None, ("too_large", 413)
    try:
        with open(path, "rb") as f:
            raw = f.read(READ_FILE_MAX_BYTES + 1)
    except OSError:
        return None, ("read_failed", 500)
    if len(raw) > READ_FILE_MAX_BYTES:
        return None, ("too_large", 413)
    name = os.path.basename(path)
    return {"mime": guess_mime(path), "data": base64.b64encode(raw).decode(),
            "filename": name, "name": name, "path": path}, None


@router.post("/read_file")
async def read_file(request: Request):
    if not authed(request):
        return unauthorized()
    body = await json_body(request)
    if body is None:
        return bad_request("Invalid JSON body")
    path = allowed_read_path(body.get("path"))
    if not path:
        return reply({"error": "forbidden", "message": "Path is outside the allowed area."}, 403)
    if not os.path.isfile(path):
        return reply({"error": "not_found"}, 404)
    payload, err = _file_payload(path)
    if err:
        return reply({"error": err[0]}, err[1])
    return reply(payload)


@router.post("/pick_file")
async def pick_file(request: Request):
    """Let the user choose a file in a dialog and return it as an attachment.

    The choice is the user's own, so it may come from anywhere readable; only
    credential stores stay off limits so a mis-click cannot ship a private
    key to a provider.
    """
    if not authed(request):
        return unauthorized()
    path = pick_file_dialog()
    if path is None:
        return reply({"error": "timeout"}, 400)
    if not path:
        return reply({"error": "cancelled"}, 400)
    real = os.path.realpath(path)
    if is_sensitive_path(real):
        return reply({"error": "forbidden", "message": "That file holds credentials and cannot be attached."}, 403)
    if not os.path.isfile(real):
        return reply({"error": "not_found"}, 404)
    payload, err = _file_payload(real)
    if err:
        return reply({"error": err[0]}, err[1])
    return reply(payload)


@router.post("/clipboard_image")
async def clipboard(request: Request):
    if not authed(request):
        return unauthorized()
    png = clipboard_image()
    if not png:
        return reply({"error": "no_image"}, 400)
    if len(png) > READ_FILE_MAX_BYTES:
        return reply({"error": "too_large"}, 413)
    return reply({"mime": "image/png", "data": base64.b64encode(png).decode(), "name": "clipboard.png"})
