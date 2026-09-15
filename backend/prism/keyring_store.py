"""API keys live in the OS keyring (Secret Service via secretstorage), never on
disk. Every accessor degrades to "not available" when the keyring is absent."""

import os

KEYRING_APP = "gemini-daemon"


def _keyring_env() -> None:
    uid = os.getuid()
    os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{uid}/bus")
    os.environ.setdefault("GNOME_KEYRING_CONTROL", f"/run/user/{uid}/keyring")


def _collection():
    _keyring_env()
    import secretstorage  # imported lazily: optional dependency
    bus = secretstorage.dbus_init()
    col = secretstorage.get_default_collection(bus)
    if col.is_locked():
        col.unlock()
    return col


def _item_provider(item) -> str:
    try:
        attrs = item.get_attributes()
    except Exception:
        attrs = {}
    # Items created before providers existed belong to Gemini
    return attrs.get("provider", "") or "gemini"


def keyring_get(provider: str) -> str:
    """Return the API key for a provider from the OS keyring, or '' if unavailable."""
    try:
        col = _collection()
        for item in col.search_items({"application": KEYRING_APP}):
            if _item_provider(item) == provider:
                return item.get_secret().decode("utf-8", errors="replace").strip()
    except Exception:
        pass
    return ""


def keyring_set(provider: str, key: str) -> bool:
    try:
        col = _collection()
        col.create_item(
            f"AI Provider key ({provider})",
            {"application": KEYRING_APP, "provider": provider},
            key,
            replace=True,
        )
        return True
    except Exception:
        return False


def keyring_delete(provider: str) -> None:
    try:
        col = _collection()
        for item in col.search_items({"application": KEYRING_APP}):
            if _item_provider(item) == provider:
                item.delete()
    except Exception:
        pass
