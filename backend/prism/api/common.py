"""Helpers shared by the routers: auth gate, JSON bodies, JSON replies."""

import json

from fastapi import Request
from fastapi.responses import Response

from ..security import authorize


def reply(payload, status: int = 200) -> Response:
    """JSON response that keeps non-ASCII text readable (the UI is Russian)."""
    return Response(content=json.dumps(payload, ensure_ascii=False), status_code=status,
                    media_type="application/json; charset=utf-8")


def unauthorized() -> Response:
    return reply({"error": "unauthorized"}, 401)


def bad_request(message: str) -> Response:
    return reply({"error": message}, 400)


def authed(request: Request) -> bool:
    return authorize(request)


async def json_body(request: Request):
    """The request body as a dict, or None when it is not a JSON object.

    Every mutating route used to call request.json() bare, so a malformed
    body or a JSON array surfaced as a 500 instead of a 400.
    """
    try:
        raw = await request.body()
        data = json.loads(raw.decode("utf-8", errors="replace")) if raw else {}
    except ValueError:
        return None
    return data if isinstance(data, dict) else None
