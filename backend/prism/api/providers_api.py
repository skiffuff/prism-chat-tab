"""Provider and model selection, plus the usage/quota view."""

import copy

from fastapi import APIRouter, Request

from .. import providers
from ..config import PROVIDER_PUBLIC_FIELDS, PROVIDERS, provider_by_id, rt, save_config
from ..sessions import DEFAULT_DAILY_LIMIT, usage
from .common import authed, bad_request, json_body, reply, unauthorized

router = APIRouter()


@router.get("/providers")
async def list_providers(request: Request):
    if not authed(request):
        return unauthorized()
    out = []
    for p in PROVIDERS:
        entry = {k: p[k] for k in PROVIDER_PUBLIC_FIELDS}
        entry["has_key"] = bool(rt.keys.get(p["id"]))
        out.append(entry)
    return reply({"providers": out, "current": rt.provider})


@router.post("/provider")
async def set_provider(request: Request):
    if not authed(request):
        return unauthorized()
    body = await json_body(request)
    pid = body.get("provider") if body else None
    if not isinstance(pid, str) or provider_by_id(pid) is None:
        return bad_request("invalid")
    rt.provider = pid
    rt.model = rt.config.get(f"model_{pid}") or rt.provider_def()["default_model"]
    rt.config["provider"] = pid
    save_config()
    return reply({"ok": True, "provider": rt.provider, "model": rt.model})


@router.get("/models")
async def list_models(request: Request):
    if not authed(request):
        return unauthorized()
    pdef = rt.provider_def()
    models = []
    if rt.provider != "anthropic":  # Anthropic exposes no model-list endpoint
        try:
            models = providers.backend().list_models()
        except Exception:
            models = []
    if not models:
        models = [{"id": m, "label": m} for m in pdef["default_models"]]
    return reply({"models": models, "current": rt.model})


@router.get("/model")
async def get_model(request: Request):
    if not authed(request):
        return unauthorized()
    return reply({"model": rt.model})


@router.post("/model")
async def set_model(request: Request):
    if not authed(request):
        return unauthorized()
    body = await json_body(request)
    m = body.get("model") if body else None
    if not isinstance(m, str) or not m.strip() or len(m) > 128:
        return bad_request("invalid")
    rt.model = m.strip()
    rt.config[f"model_{rt.provider}"] = rt.model
    save_config()
    return reply({"ok": True, "model": rt.model})


@router.get("/quota")
async def get_quota(request: Request):
    if not authed(request):
        return unauthorized()
    q = copy.deepcopy(usage)
    limits = q.get("limits", {})
    last_err = q.get("last_error", "") or ""
    pdef = rt.provider_def()
    models = set(pdef.get("default_models", []))
    has_key = bool(rt.keys.get(rt.provider))
    q["provider"] = rt.provider
    q["has_key"] = has_key
    q["by_model"] = {m: s for m, s in q.get("by_model", {}).items() if m in models}
    q["limits"] = {m: l for m, l in limits.items() if m in models}
    if has_key:
        for m in pdef.get("default_models", []):
            q["by_model"].setdefault(m, {"requests": 0, "prompt_tokens": 0, "output_tokens": 0, "status": "ok"})
    for model, st in list(q.get("by_model", {}).items()):
        st_out = dict(st) if isinstance(st, dict) else {"requests": int(st or 0), "prompt_tokens": 0, "output_tokens": 0}
        reqs = st_out.get("requests", 0)
        limit = q["limits"].get(model) or DEFAULT_DAILY_LIMIT
        st_out["limit"] = limit
        if (q.get("quota_exceeded") and model in last_err) or reqs >= limit:
            st_out["status"] = "exhausted"
        elif reqs >= limit * 0.7:
            st_out["status"] = "warning"
        else:
            st_out["status"] = "ok"
        q["by_model"][model] = st_out
    return reply(q)
