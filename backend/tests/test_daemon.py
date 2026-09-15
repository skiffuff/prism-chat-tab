"""Offline test-suite for the Prism daemon.

Runs against a sandboxed HOME and a fake OpenAI server, never touching the
real config, keyring or sessions. Plain asserts, so it works with or without
pytest:

    python backend/tests/test_daemon.py
    pytest backend/tests
"""

import json
import os
import shutil
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

# ── Sandbox before anything from the package is imported ────────────────
SANDBOX = tempfile.mkdtemp(prefix="prism-test-")
for sub in (".config/prism", ".local/share/prism", ".cache", "run", "docs", ".ssh"):
    os.makedirs(os.path.join(SANDBOX, sub), exist_ok=True)
os.environ["HOME"] = SANDBOX
os.environ["PRISM_CONFIG"] = os.path.join(SANDBOX, ".config/prism/config.json")
os.environ["PRISM_TOKEN_FILE"] = os.path.join(SANDBOX, ".local/share/prism/daemon.token")
os.environ["XDG_RUNTIME_DIR"] = os.path.join(SANDBOX, "run")
os.environ["DBUS_SESSION_BUS_ADDRESS"] = ""
os.environ.pop("GEMINI_API_KEY", None)
os.environ["OPENAI_API_KEY"] = "sk-good"
with open(os.environ["PRISM_CONFIG"], "w") as f:
    json.dump({"provider": "openai", "model": "gpt-5-mini", "system_instruction": "SYS"}, f)

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from fastapi.testclient import TestClient  # noqa: E402

from prism import security, sessions  # noqa: E402
from prism.app import app  # noqa: E402
from prism.config import rt  # noqa: E402
from prism.providers import openai as oa  # noqa: E402
from prism.providers.canonical import canonical_blocks, first_tool_call, result_part  # noqa: E402

# Keyring is unavailable in the sandbox, so the provider key comes from env.
assert rt.provider == "openai" and rt.api_key() == "sk-good"


# ── Fake OpenAI upstream ────────────────────────────────────────────────
class FakeOpenAI(BaseHTTPRequestHandler):
    mode = "text"
    next_mode = None   # switch to this mode after serving one response
    seen = []

    def log_message(self, *a):
        pass

    def _send(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        FakeOpenAI.seen.append(("GET", self.path, dict(self.headers), None))
        if self.headers.get("Authorization") != "Bearer sk-good":
            return self._send(401, {"error": {"message": "bad key"}})
        self._send(200, {"data": [{"id": "gpt-5-mini"}, {"id": "gpt-4.1"}, {"id": "whisper-1"},
                                  {"id": "text-embedding-3-small"}, {"id": "o3"}]})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n))
        FakeOpenAI.seen.append(("POST", self.path, dict(self.headers), body))
        if self.headers.get("Authorization") != "Bearer sk-good":
            return self._send(401, {"error": {"message": "Incorrect API key provided", "type": "invalid_request_error"}})
        mode = FakeOpenAI.mode
        if FakeOpenAI.next_mode:
            FakeOpenAI.mode, FakeOpenAI.next_mode = FakeOpenAI.next_mode, None
        if mode == "text":
            self._send(200, {"choices": [{"message": {"role": "assistant", "content": "Четыре"}}],
                             "usage": {"prompt_tokens": 11, "completion_tokens": 2}})
        elif mode in ("tool", "tool-dig", "tool-ssh", "tool-zero", "tool-cat"):
            cmd = {"tool": "date", "tool-dig": "dig example.com", "tool-ssh": "base64 ~/.ssh/id_ed25519",
                   "tool-zero": "od -v /dev/zero", "tool-cat": "cat /etc/passwd"}[mode]
            self._send(200, {"choices": [{"message": {"role": "assistant", "content": None, "tool_calls": [
                {"id": "call_abc", "type": "function", "function": {"name": "run_bash", "arguments": json.dumps({"command": cmd})}},
                {"id": "call_def", "type": "function", "function": {"name": "run_bash", "arguments": "{\"command\": \"ls\"}"}}]}}],
                "usage": {"prompt_tokens": 20, "completion_tokens": 9}})
        elif mode == "quota":
            self._send(429, {"error": {"message": "You exceeded your current quota", "type": "insufficient_quota"}})


srv = HTTPServer(("127.0.0.1", 0), FakeOpenAI)
threading.Thread(target=srv.serve_forever, daemon=True).start()
rt.openai_url = f"http://127.0.0.1:{srv.server_address[1]}"

client = TestClient(app)
TOKEN = security.daemon_token()
H = {"X-Prism-Token": TOKEN}


def _last_request():
    return FakeOpenAI.seen[-1][3]


# ── Security primitives ─────────────────────────────────────────────────
def test_dangerous_classifier():
    for cmd in ("rm -rf /", "git status", "tee x", "python3 -c 1", "find . -exec rm {} ;",
                "sed -i s/a/b/ f", "ls; rm x", "echo $(id)", "dd if=/dev/zero", "sudo ls"):
        assert security.is_dangerous(cmd), cmd
    for cmd in ("ls -la", "date", "wc -l README.md", "dig example.com"):
        assert not security.is_dangerous(cmd), cmd


def test_persistability_excludes_network_and_dangerous():
    assert security.can_persist("ls -la")
    assert not security.can_persist("dig example.com")
    assert not security.can_persist("ping 1.1.1.1")
    assert not security.can_persist("rm -rf /")
    assert security.grant_pattern("dig example.com") is False
    assert security.grant_pattern("tee x") is False
    assert "dig *" not in security.allowed_patterns()

    # An unanswered prompt times out into a recorded denial, never a dangling tool call
    sessions.new_session()
    FakeOpenAI.mode = "tool"
    j = client.post("/chat", headers=H, json={"message": "какая дата?"}).json()
    assert j["pending"] and j["patterns"] == ["date *"]
    saved_ttl, security.PENDING_CONFIRM_TTL = security.PENDING_CONFIRM_TTL, -1
    try:
        r = client.post("/tool/confirm", headers=H, json={"tool_call_id": j["tool_call_id"], "decision": "allow"})
    finally:
        security.PENDING_CONFIRM_TTL = saved_ttl
    assert r.status_code == 410
    last = sessions.active_session()["messages"][-1]
    assert last["role"] == "user" and "не ответил" in json.dumps(last, ensure_ascii=False)
    FakeOpenAI.mode = "text"

    # A command outside the allowlist is refused without asking the user
    sessions.new_session()
    FakeOpenAI.mode, FakeOpenAI.next_mode = "tool-cat", "text"
    j = client.post("/chat", headers=H, json={"message": "покажи passwd"}).json()
    assert "response" in j, j
    tool_msgs = [m for m in _last_request()["messages"] if m["role"] == "tool"]
    assert tool_msgs and "not in the allowed list" in tool_msgs[-1]["content"]


def test_grant_and_match_patterns():
    assert security.grant_pattern("ls -la")
    assert "ls *" in security.allowed_patterns()
    assert security.command_ok_by_pattern("ls /tmp")
    assert security.command_ok_by_pattern("ls")
    assert not security.command_ok_by_pattern("ls; rm -rf /")
    assert not security.command_ok_by_pattern("cat /etc/passwd")
    security._save_allowed_patterns([])


def test_run_bash_allowlist_and_output_cap():
    env = os.environ.copy()
    assert security.run_bash("echo hello", env) == "hello"
    assert "not in the allowed list" in security.run_bash("cat /etc/passwd", env)
    assert "not in the allowed list" in security.run_bash("python3 -c 1", env)
    assert "empty" in security.run_bash("", env).lower()
    # Shell metacharacters are literal argv, not a pipeline
    out = security.run_bash("echo a | tr a b", env)
    assert out == "a | tr a b"
    # A runaway producer is cut off instead of filling memory
    out = security.run_bash("od -v /dev/zero", env)
    assert "truncated" in out and len(out) < security.RUN_BASH_MAX_OUTPUT + 200


def test_run_bash_blocks_credential_paths():
    env = os.environ.copy()
    key = os.path.join(SANDBOX, ".ssh/id_ed25519")
    with open(key, "w") as f:
        f.write("PRIVATE")
    for cmd in ("base64 ~/.ssh/id_ed25519", f"od {key}", "wc -c ~/.local/share/prism/daemon.token",
                "nl --number-format=ln ~/.ssh/id_ed25519", "base64 .ssh/id_ed25519"):
        out = security.run_bash(cmd, env)
        assert "blocked" in out and "PRIVATE" not in out, (cmd, out)
    # Ordinary files still work
    doc = os.path.join(SANDBOX, "docs/readme.md")
    with open(doc, "w") as f:
        f.write("hello\n")
    assert security.run_bash(f"wc -l {doc}", env).startswith("1")


def test_read_path_policy():
    assert security.allowed_read_path("/etc/passwd") is None
    assert security.allowed_read_path(os.path.join(SANDBOX, ".ssh/id_ed25519")) is None
    assert security.allowed_read_path(os.path.join(SANDBOX, ".local/share/prism/daemon.token")) is None
    assert security.allowed_read_path(os.path.join(SANDBOX, "docs/.env")) is None
    assert security.allowed_read_path(os.path.join(SANDBOX, "docs/server.pem")) is None
    ok = os.path.join(SANDBOX, "docs/readme.md")
    assert security.allowed_read_path(ok) == os.path.realpath(ok)
    # Symlink escape
    link = os.path.join(SANDBOX, "docs/passwd")
    if not os.path.lexists(link):
        os.symlink("/etc/passwd", link)
    assert security.allowed_read_path(link) is None


def test_redaction():
    rt.keys["gemini"] = "AIzaSECRETKEY123"
    msg = security.redact("ConnectionError(url=https://w.example/v1beta/models/x:generateContent?key=AIzaSECRETKEY123&alt=json) AIzaSECRETKEY123")
    assert "AIzaSECRETKEY123" not in msg and "[REDACTED" in msg
    assert TOKEN not in security.redact(f"token {TOKEN} leaked")
    rt.keys["gemini"] = ""


def test_authorization():
    assert client.get("/providers").status_code == 401
    assert client.get("/providers", headers={"X-Prism-Token": "wrong"}).status_code == 401
    assert client.get("/providers", headers={"X-Prism-Token": "wrong-token"}).status_code == 401
    assert client.get("/health").status_code == 200
    assert client.options("/chat").status_code == 403


# ── OpenAI wire format ──────────────────────────────────────────────────
def test_openai_messages_and_repair():
    hist = [
        {"role": "user", "parts": [{"type": "image", "mime": "image/png", "data": "AAAA"}, {"type": "text", "text": "что на картинке?"}]},
        {"role": "assistant", "parts": [{"type": "text", "text": "Проверю."}, {"type": "tool_use", "id": "call_1", "name": "run_bash", "input": {"command": "ls"}}]},
        {"role": "user", "parts": [{"type": "tool_result", "tool_use_id": "call_1", "name": "run_bash", "content": "a b c"}]},
        {"role": "assistant", "parts": [{"type": "text", "text": "Файлы: a b c"}]},
        {"role": "user", "parts": [{"type": "text", "text": "спасибо"}]},
    ]
    m = oa.build_messages(hist)
    assert [x["role"] for x in m] == ["system", "user", "assistant", "tool", "assistant", "user"]
    assert m[1]["content"][0]["image_url"]["url"].startswith("data:image/png;base64,AAAA")
    assert m[2]["tool_calls"][0]["function"]["arguments"] == '{"command": "ls"}'
    assert m[3] == {"role": "tool", "tool_call_id": "call_1", "content": "a b c"}

    broken = [
        {"role": "user", "parts": [{"type": "tool_result", "tool_use_id": "gone", "name": "run_bash", "content": "x"}]},
        {"role": "assistant", "parts": [{"type": "tool_use", "id": "c9", "name": "run_bash", "input": {"command": "date"}}]},
        {"role": "user", "parts": [{"type": "text", "text": "never mind"}]},
    ]
    m = oa.build_messages(broken)
    assert [x["role"] for x in m] == ["system", "assistant", "tool", "user"]
    assert m[2]["tool_call_id"] == "c9" and m[2]["content"] == oa.UNANSWERED

    # Legacy Gemini wire parts in the same session
    legacy = [
        {"role": "user", "parts": [{"text": "дата"}]},
        {"role": "assistant", "parts": [{"functionCall": {"name": "run_bash", "args": {"command": "date"}, "id": "g1"}}]},
        {"role": "user", "parts": [{"functionResponse": {"name": "run_bash", "response": {"result": "Mon"}}}]},
    ]
    m = oa.build_messages(legacy)
    assert [x["role"] for x in m] == ["system", "user", "assistant", "tool"]


def test_openai_model_filters():
    for m in ("gpt-5", "gpt-5-mini", "gpt-4.1", "o3", "chatgpt-4o-latest"):
        assert oa.is_chat_model(m), m
    for m in ("whisper-1", "text-embedding-3-small", "gpt-4o-realtime-preview", "dall-e-3", "gpt-image-1"):
        assert not oa.is_chat_model(m), m
    assert oa.is_reasoning_model("gpt-5-mini") and oa.is_reasoning_model("o4-mini")
    assert not oa.is_reasoning_model("gpt-4.1") and not oa.is_reasoning_model("gpt-5-chat-latest")


def test_canonical_helpers():
    parts = [{"functionCall": {"name": "run_bash", "args": {"command": "date"}}}]
    args, tid, name = first_tool_call(parts)
    assert args == {"command": "date"} and tid and name == "run_bash"
    assert parts[0]["functionCall"]["id"] == tid  # assigned in place
    assert result_part("gemini", "x", "out")["functionResponse"]["response"]["result"] == "out"
    assert result_part("openai", "x", "out")["tool_use_id"] == "x"
    assert canonical_blocks([{"inline_data": {"mime_type": "image/png", "data": "Q"}}])[0]["type"] == "image"


# ── Endpoints ───────────────────────────────────────────────────────────
def test_providers_and_models():
    r = client.get("/providers", headers=H)
    assert r.status_code == 200
    pv = r.json()
    assert pv["current"] == "openai"
    op = next(p for p in pv["providers"] if p["id"] == "openai")
    assert op["name"] == "ChatGPT" and op["style"] == "chatgpt" and op["logo"] == "openai" and op["has_key"] is True
    assert "env" not in op
    r = client.get("/models", headers=H)
    assert [m["id"] for m in r.json()["models"]] == ["gpt-4.1", "gpt-5-mini", "o3"]
    assert client.post("/provider", headers=H, json={"provider": "chatgpt"}).status_code == 400
    assert client.post("/provider", headers=H, content=b"not json").status_code == 400
    assert client.post("/provider", headers=H, json=["openai"]).status_code == 400
    r = client.post("/provider", headers=H, json={"provider": "gemini"})
    assert r.json()["provider"] == "gemini"
    r = client.post("/provider", headers=H, json={"provider": "openai"})
    assert r.json()["provider"] == "openai" and r.json()["model"] == "gpt-5-mini"


def test_settings_validation():
    st = client.get("/settings", headers=H).json()
    assert st["openai_url"] == rt.openai_url
    r = client.put("/settings", headers=H, json={"worker_url": st["worker_url"], "openai_url": st["openai_url"], "system_instruction": "SYS2"})
    assert r.status_code == 200 and rt.system_instruction == "SYS2"
    assert client.put("/settings", headers=H, json={"worker_url": "https://evil.example"}).status_code == 400
    assert client.put("/settings", headers=H, json={"openai_url": "https://evil.example/v1"}).status_code == 400
    assert client.put("/settings", headers=H, json={"openai_url": "http://api.openai.com"}).status_code == 400
    assert client.put("/settings", headers=H, json={"anthropic_url": "https://evil.example"}).status_code == 400
    assert client.put("/settings", headers=H, json={"system_instruction": "x" * 30000}).status_code == 400
    assert client.put("/settings", headers=H, json={"system_instruction": ["list"]}).status_code == 400
    assert client.put("/settings", headers=H, json={"glow": {"ring_count": "96"}}).status_code == 400
    assert client.put("/settings", headers=H, json={"glow": {"gradient": ["red", "blue"]}}).status_code == 400
    assert client.put("/settings", headers=H, json={"glow": {"ring_count": 64, "alpha": 0.5, "gradient": ["#10A37F", "#74AA9C"]}}).status_code == 200
    assert client.get("/settings", headers=H).json()["glow"]["ring_count"] == 64
    assert client.put("/settings", headers=H, content=b"[").status_code == 400
    saved = rt.openai_url
    assert client.put("/settings", headers=H, json={"openai_url": "https://api.openai.com"}).status_code == 200
    rt.openai_url = saved
    rt.config["openai_url"] = saved
    r = client.post("/settings/validate", headers=H, json={"api_key": "sk-good"})
    assert r.json() == {"valid": True, "models": 3}
    assert client.post("/settings/validate", headers=H, json={"api_key": "sk-bad"}).json()["valid"] is False
    assert "format" in client.post("/settings/validate", headers=H, json={"api_key": "AIza"}).json()["error"]
    assert client.post("/settings/validate", headers=H, json={"api_key": 5}).json()["valid"] is False


def test_permissions_endpoints():
    assert security.grant_pattern("uname -a")
    j = client.get("/permissions", headers=H).json()
    assert "uname *" in j["patterns"]
    assert [r["action"] for r in j["rules"] if r["pattern"] == "uname *"] == ["allow"]
    assert client.request("DELETE", "/permissions", headers=H, json={"pattern": "uname *"}).status_code == 200
    assert "uname *" not in security.allowed_patterns()
    assert client.request("DELETE", "/permissions", headers=H, json={"pattern": "uname *"}).status_code == 404
    assert client.request("DELETE", "/permissions", headers=H, json={"pattern": ""}).status_code == 400
    assert client.request("DELETE", "/permissions", headers=H, content=b"{").status_code == 400
    assert client.get("/permissions").status_code == 401
    # hand-written rules: deny anything, allow only allowlisted non-network binaries
    assert client.post("/permissions", headers=H, json={"pattern": "ping *", "action": "deny"}).status_code == 200
    assert client.post("/permissions", headers=H, json={"pattern": "ping *", "action": "allow"}).status_code == 400
    assert client.post("/permissions", headers=H, json={"pattern": "rm *", "action": "allow"}).status_code == 400
    assert client.post("/permissions", headers=H, json={"pattern": "*", "action": "allow"}).status_code == 400
    assert client.post("/permissions", headers=H, json={"pattern": "wc *", "action": "allow"}).status_code == 200
    assert client.post("/permissions", headers=H, json={"pattern": "wc *", "action": "sometimes"}).status_code == 400
    rules = {r["pattern"]: r["action"] for r in client.get("/permissions", headers=H).json()["rules"]}
    assert rules["ping *"] == "deny" and rules["wc *"] == "allow"
    security.save_rules([])


def test_evaluate_and_candidates():
    assert security.pattern_candidates("ls -la /tmp") == ["ls *", "ls -la /tmp"]
    assert security.pattern_candidates("date") == ["date *"]
    assert security.pattern_candidates("ls; rm x") == ["ls; rm x"]
    assert security.evaluate("cat /etc/passwd")["action"] == "deny"
    assert security.evaluate("ls ~/.ssh")["action"] == "deny"
    assert security.evaluate("ls -la")["action"] == "ask"
    assert security.evaluate("dig example.com")["patterns"] == []
    security.add_rule("date *", "allow")
    security.add_rule("ls /tmp*", "deny")
    assert security.evaluate("date")["action"] == "allow"
    assert security.evaluate("ls /tmp/x") == security.evaluate("ls /tmp/x")
    assert security.evaluate("ls /tmp/x")["action"] == "deny" and security.evaluate("ls /tmp/x")["rule"] == "ls /tmp*"
    assert security.evaluate("ls /home")["action"] == "ask"
    # the exact-command candidate can be stored instead of the wildcard
    assert security.grant_pattern("wc -l README.md", "wc -l README.md")
    assert security.grant_pattern("wc -l README.md", "wc -l *") is False
    assert security.evaluate("wc -l README.md")["action"] == "allow"
    assert security.evaluate("wc -l other.md")["action"] == "ask"
    security.save_rules([])


def test_sessions_endpoints():
    assert client.post("/session/select", headers=H, json={"id": 123}).status_code == 400
    assert client.post("/session/select", headers=H, json={"id": "nope"}).status_code == 404
    assert client.post("/session/rename", headers=H, content=b"x").status_code == 400
    r = client.post("/session/new", headers=H)
    sid = r.json()["active_id"]
    assert client.post("/session/rename", headers=H, json={"id": sid, "title": "T" * 100}).status_code == 200
    assert any(s["title"] == "T" * 48 for s in client.get("/sessions", headers=H).json()["sessions"])
    assert client.post("/session/delete", headers=H, json={"id": sid}).status_code == 200
    assert all(s["id"] != sid for s in client.get("/sessions", headers=H).json()["sessions"])


def test_files_endpoints():
    doc = os.path.join(SANDBOX, "docs/readme.md")
    with open(doc, "w", encoding="utf-8") as f:
        f.write("hello\n")
    r = client.post("/read_file", headers=H, json={"path": doc})
    assert r.status_code == 200 and r.json()["mime"] == "text/plain" and r.json()["name"] == "readme.md"
    assert client.post("/read_file", headers=H, json={"path": "/etc/passwd"}).status_code == 403
    assert client.post("/read_file", headers=H, json={"path": os.path.join(SANDBOX, ".ssh/id_ed25519")}).status_code == 403
    assert client.post("/read_file", headers=H, json={"path": os.path.join(SANDBOX, "docs/missing.md")}).status_code == 404
    assert client.post("/read_file", headers=H, content=b"{").status_code == 400
    big = os.path.join(SANDBOX, "docs/big.bin")
    with open(big, "wb") as f:
        f.truncate(security.READ_FILE_MAX_BYTES + 1)
    assert client.post("/read_file", headers=H, json={"path": big}).status_code == 413
    os.remove(big)


def test_chat_tool_flow_and_persistability():
    sessions.new_session()
    FakeOpenAI.mode = "tool"
    r = client.post("/chat", headers=H, json={"message": "какая дата?"})
    j = r.json()
    assert j["pending"] is True and j["command"] == "date" and j["persistable"] is True and j["dangerous"] is False
    FakeOpenAI.mode = "text"
    r = client.post("/tool/confirm", headers=H, json={"tool_call_id": j["tool_call_id"], "decision": "allow"})
    assert r.json() == {"response": "Четыре"}
    roles = [m["role"] for m in _last_request()["messages"]]
    assert roles == ["system", "user", "assistant", "tool"], roles
    assert client.post("/tool/confirm", headers=H, json={"tool_call_id": j["tool_call_id"], "decision": "allow"}).status_code == 409
    assert client.post("/tool/confirm", headers=H, json={"tool_call_id": "nope", "decision": "allow"}).status_code == 404
    assert client.post("/tool/confirm", headers=H, json={"tool_call_id": "x", "decision": "maybe"}).status_code == 400

    # Network command: runs once, but "Allow always" must not persist it
    sessions.new_session()
    FakeOpenAI.mode = "tool-dig"
    j = client.post("/chat", headers=H, json={"message": "проверь dns"}).json()
    assert j["pending"] and j["persistable"] is False and j["dangerous"] is False
    FakeOpenAI.mode = "text"
    r = client.post("/tool/confirm", headers=H, json={"tool_call_id": j["tool_call_id"], "decision": "never"})
    assert r.status_code == 200
    assert "dig *" not in security.allowed_patterns()

    # Credential path in a tool argument is refused before anyone is asked
    sessions.new_session()
    FakeOpenAI.mode, FakeOpenAI.next_mode = "tool-ssh", "text"
    j = client.post("/chat", headers=H, json={"message": "покажи ключ"}).json()
    assert "response" in j, j
    tool_msg = _last_request()["messages"][-1]
    assert tool_msg["role"] == "tool" and "blocked" in tool_msg["content"] and "PRIVATE" not in tool_msg["content"]


def test_chat_errors_roll_back_and_flag_quota():
    sessions.new_session()
    sess = sessions.active_session()
    FakeOpenAI.mode = "quota"
    r = client.post("/chat", headers=H, json={"message": "hi"})
    assert r.status_code == 200 and "quota" in r.json()["error"].lower()
    assert sess["messages"] == []  # user turn rolled back
    assert sessions.usage["quota_exceeded"] is True
    FakeOpenAI.mode = "text"
    assert client.post("/chat", headers=H, json={"message": ""}).status_code == 400
    assert client.post("/chat", headers=H, json={"message": {"x": 1}}).status_code == 400
    assert client.post("/chat", headers=H, content=b"nope").status_code == 400
    r = client.post("/chat", headers=H, json={"message": "2+2", "attachments": [{"data": "QUJD", "mime": "image/png"}, "junk"]})
    assert r.json() == {"response": "Четыре"}
    assert sessions.usage["quota_exceeded"] is False


def test_health_reports_start_time():
    j = client.get("/health").json()
    assert j["status"] == "ok" and abs(j["started"] - rt.started) < 1e-6


def test_screen_trigger_is_narrow():
    from prism.screen import wants_screen
    assert wants_screen("посмотри на мой экран")
    assert wants_screen("Look at my screen and tell me what is going on")
    assert wants_screen("что у меня на экране?")
    assert not wants_screen("посмотри этот код")
    assert not wants_screen("screenshot of the docs")
    assert not wants_screen("watch out for the bug")


def _run_all():
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"PASSED: {name}")
        except AssertionError as e:
            failed += 1
            print(f"FAILED: {name} -> {e!r}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"ERROR:  {name} -> {e!r}")
    shutil.rmtree(SANDBOX, ignore_errors=True)
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    return failed


if __name__ == "__main__":
    sys.exit(1 if _run_all() else 0)
