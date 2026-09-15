"""Settings: API key (keyring only), provider endpoints, system instruction
and the glow overlay, plus key validation."""

import os
import re
from urllib.parse import urlparse

from fastapi import APIRouter, Request

from .. import providers, security
from ..config import DEFAULT_SYSTEM_INSTRUCTION, GLOW_DEFAULTS, provider_env, rt, save_config
from ..keyring_store import keyring_delete, keyring_set
from .common import authed, bad_request, json_body, reply, unauthorized

router = APIRouter()

MAX_SYSTEM_INSTRUCTION = 20_000
_HEX_COLOUR = re.compile(r"^#[0-9a-fA-F]{6}$")


def _glow_settings() -> dict:
    glow = {**GLOW_DEFAULTS, **(rt.config.get("glow") or {})}
    if not glow.get("gradient"):
        glow["gradient"] = rt.provider_def()["gradient"]
    return glow


@router.get("/settings")
async def get_settings(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({
        "provider": rt.provider,
        "api_key_set": bool(rt.keys.get(rt.provider)),
        "key_placeholder": rt.provider_def()["key_placeholder"],
        "worker_url": rt.worker_url,
        "anthropic_url": rt.anthropic_url,
        "openai_url": rt.openai_url,
        "system_instruction": rt.system_instruction,
        "system_instruction_default": DEFAULT_SYSTEM_INSTRUCTION,
        "glow": _glow_settings(),
        "glow_default_gradient": rt.provider_def()["gradient"],
    })


def valid_https_url(url: str, allowed_host: str) -> bool:
    """True when url is an https URL pointing at the given host."""
    try:
        if not url or not isinstance(url, str):
            return False
        p = urlparse(url)
        # Reject trailing dots (can lead to subdomain takeover via DNS)
        if p.hostname and p.hostname.endswith("."):
            return False
        return p.scheme == "https" and (p.hostname or "").lower() == allowed_host and bool(p.netloc)
    except ValueError:
        return False


def _validate_glow(glow: dict):
    """Type- and range-check the glow block; returns (clean, error)."""
    clean = {}
    if "enabled" in glow and glow["enabled"] is not None:
        if not isinstance(glow["enabled"], bool):
            return None, "glow.enabled must be a boolean"
        clean["enabled"] = glow["enabled"]
    for key, lo, hi in (("ring_count", 8, 512), ("sigma", 1, 200), ("alpha", 0.0, 1.0)):
        if key in glow and glow[key] is not None:
            v = glow[key]
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not (lo <= v <= hi):
                return None, f"glow.{key} must be a number between {lo} and {hi}"
            clean[key] = int(v) if key != "alpha" else float(v)
    if glow.get("gradient"):
        grad = glow["gradient"]
        if not isinstance(grad, list) or not (2 <= len(grad) <= 8) or not all(
                isinstance(c, str) and _HEX_COLOUR.match(c) for c in grad):
            return None, "glow.gradient must be 2-8 #rrggbb colours"
        clean["gradient"] = [c.lower() for c in grad]
    return clean, None


@router.put("/settings")
async def update_settings(request: Request):
    if not authed(request):
        return unauthorized()
    data = await json_body(request)
    if data is None:
        return bad_request("Invalid JSON body")

    def text(field):
        v = data.get(field)
        return v.strip() if isinstance(v, str) else ""

    # worker_url is fixed at startup from config.json / env and must not be
    # switched to an attacker-supplied URL through the API. Echoing the current
    # value back (the settings form round-trips every field) is not a change.
    if "worker_url" in data and text("worker_url") != rt.worker_url:
        return bad_request("worker_url cannot be changed via the API; edit ~/.config/prism/config.json instead")

    # Provider endpoints may only be pointed at the vendor's own host through
    # the API; a proxy for a geo-blocked vendor goes into config.json, and that
    # configured value is accepted back unchanged.
    endpoints = (("anthropic_url", "api.anthropic.com", rt.anthropic_url),
                 ("openai_url", "api.openai.com", rt.openai_url))
    for field, host, current in endpoints:
        if field in data:
            new_url = text(field)
            if new_url and new_url != current and not valid_https_url(new_url, host):
                return bad_request(f"{field} must be an https URL on {host}")

    if "system_instruction" in data and data["system_instruction"] is not None:
        if not isinstance(data["system_instruction"], str):
            return bad_request("system_instruction must be a string")
        if len(data["system_instruction"]) > MAX_SYSTEM_INSTRUCTION:
            return bad_request(f"system_instruction is longer than {MAX_SYSTEM_INSTRUCTION} characters")

    glow_clean = None
    if "glow" in data and data["glow"] is not None:
        if not isinstance(data["glow"], dict):
            return bad_request("glow must be an object")
        glow_clean, err = _validate_glow(data["glow"])
        if err:
            return bad_request(err)

    # Everything validated; apply.
    if "api_key" in data:
        # Security: the key is stored ONLY in the OS keyring, never on disk.
        new_key = text("api_key")
        if new_key:
            rt.keys[rt.provider] = new_key
            keyring_set(rt.provider, new_key)
        else:
            keyring_delete(rt.provider)
            rt.keys[rt.provider] = os.environ.get(provider_env(rt.provider), "")
    if text("anthropic_url"):
        rt.anthropic_url = text("anthropic_url")
        rt.config["anthropic_url"] = rt.anthropic_url
    if text("openai_url"):
        rt.openai_url = text("openai_url")
        rt.config["openai_url"] = rt.openai_url
    if isinstance(data.get("system_instruction"), str):
        rt.system_instruction = data["system_instruction"]
        rt.config["system_instruction"] = rt.system_instruction
    if glow_clean is not None:
        current = {**GLOW_DEFAULTS, **(rt.config.get("glow") or {})}
        current.update(glow_clean)
        current["gradient"] = current.get("gradient") or rt.provider_def()["gradient"]
        rt.config["glow"] = current
    save_config()
    return reply({"ok": True})


@router.post("/settings/validate")
async def validate_settings(request: Request):
    if not authed(request):
        return unauthorized()
    data = await json_body(request)
    if data is None:
        return bad_request("Invalid JSON body")
    key = data.get("api_key", rt.api_key())
    if not isinstance(key, str):
        return reply({"valid": False, "error": "api_key must be a string"})
    try:
        return reply(providers.backend().validate_key(key))
    except Exception:
        return reply({"valid": False, "error": "Validation failed (network error). See daemon logs."})


@router.get("/permissions")
async def get_permissions(request: Request):
    """Commands the user has chosen to allow without asking."""
    if not authed(request):
        return unauthorized()
    return reply({"patterns": security.allowed_patterns()})


@router.delete("/permissions")
async def delete_permission(request: Request):
    if not authed(request):
        return unauthorized()
    data = await json_body(request)
    if data is None:
        return bad_request("Invalid JSON body")
    pattern = data.get("pattern")
    if not isinstance(pattern, str) or not pattern.strip():
        return bad_request("pattern must be a non-empty string")
    if not security.revoke_pattern(pattern.strip()):
        return reply({"error": "pattern not found"}, 404)
    return reply({"ok": True, "patterns": security.allowed_patterns()})
