#!/usr/bin/env python3
"""Prism daemon entry point.

The implementation lives in the `prism` package next to this file:

    prism/config.py        paths, provider registry, runtime state, config.json
    prism/security.py      token, rate limit, file policy, run_bash sandbox
    prism/sessions.py      chat sessions and usage counters
    prism/providers/       Gemini / Claude / ChatGPT wire formats
    prism/screen.py        screen watching, clipboard, file picker
    prism/api/             FastAPI routers
    prism/app.py           application assembly

Run directly (`python prism_daemon.py`) or import `app` for an ASGI server.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from prism.app import app, main  # noqa: E402

if __name__ == "__main__":
    main()
