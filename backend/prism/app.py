"""FastAPI application assembly and the daemon entry point."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import __version__
from .api import chat, files, providers_api, sessions_api, settings_api, watch
from .config import load_config, rt
from .keyring_store import keyring_get, keyring_set
from .security import ensure_token_file

HOST = "127.0.0.1"
PORT = 5000


def create_app() -> FastAPI:
    load_config(keyring_get, keyring_set)
    ensure_token_file()

    app = FastAPI(title="Prism AI Provider Daemon", version=__version__)

    @app.middleware("http")
    async def no_cors(request: Request, call_next):
        # Reject browser CORS preflight outright. The QML client's XHR is not
        # subject to CORS, so no legitimate cross-origin request is lost, and
        # a web page can never obtain permission to send the token header.
        if request.method == "OPTIONS":
            return JSONResponse(status_code=403, content={"detail": "CORS not allowed"})
        return await call_next(request)

    for router in (watch.router, chat.router, providers_api.router, sessions_api.router,
                   files.router, settings_api.router):
        app.include_router(router)
    return app


app = create_app()


def main() -> None:
    import uvicorn
    print(f"🚀 Prism daemon {__version__} on http://{HOST}:{PORT} (provider: {rt.provider})")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
