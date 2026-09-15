"""Screen watching: record the desktop with wf-recorder/ffmpeg, then have the
active provider describe what happened. Also the helpers that talk to the
user's session (env for subprocesses, clipboard, file picker)."""

import base64
import os
import re
import shutil
import signal
import subprocess
import threading

from . import providers
from .config import CACHE_DIR, GLOW_FLAG, RECORD_FILE, SCREEN_TRIGGER_PHRASES, rt
from .security import redact
from .sessions import active_session, now_ts, save_sessions, store_lock

SCREEN_TRIGGER_RE = re.compile("|".join(SCREEN_TRIGGER_PHRASES), re.IGNORECASE)

ZENITY = shutil.which("zenity") or "zenity"

record_state = {"active": False, "process": None, "prompt": "Analyze the screen recording and help."}
_watch_lock = threading.Lock()


def user_env() -> dict:
    """Environment for helpers that must reach the user's Wayland session."""
    uid = os.getuid()
    env = os.environ.copy()
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    env.setdefault("WAYLAND_DISPLAY", "wayland-1")
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{uid}/bus")
    env.setdefault("DISPLAY", ":0")
    env["QT_QPA_PLATFORM"] = "wayland"
    return env


def clean_response_text(txt) -> str:
    if not txt:
        return ""
    txt = re.sub(r"\s*thinking\s*.*?\s*response\s*", " ", txt, flags=re.DOTALL | re.I)
    txt = txt.replace("**", "")
    txt = re.sub(r"^\s*[-—]{1,2}\s+", "", txt, flags=re.M)
    txt = txt.replace(" -- ", " ")
    return txt.strip()


def wants_screen(text: str) -> bool:
    return bool(SCREEN_TRIGGER_RE.search(text or ""))


def set_glow(on: bool) -> None:
    try:
        if on:
            open(GLOW_FLAG, "w").close()
        elif os.path.exists(GLOW_FLAG):
            os.remove(GLOW_FLAG)
    except OSError:
        pass


def _recorder_command():
    """wf-recorder, or ffmpeg's pipewire input as a fallback."""
    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
    if shutil.which("wf-recorder"):
        return ["wf-recorder", "-f", RECORD_FILE, "-y"]
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        return [ffmpeg, "-f", "pipewire", "-i", "default", "-y", RECORD_FILE]
    return None


def start_recording(prompt: str = "") -> None:
    with _watch_lock:
        if record_state["active"]:
            return
        cmd = _recorder_command()
        if not cmd:
            return
        try:
            record_state["process"] = subprocess.Popen(cmd, env=user_env(),
                                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            return
        record_state["active"] = True
        record_state["prompt"] = prompt or "Analyze the screen recording and help."
    set_glow(True)


def is_recording() -> bool:
    return record_state["active"]


def _extract_frame(path: str):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    try:
        r = subprocess.run([ffmpeg, "-ss", "0.5", "-i", path, "-frames:v", "1",
                            "-f", "image2pipe", "-vcodec", "png", "-"],
                           capture_output=True, timeout=30)
        if r.returncode == 0 and r.stdout:
            return base64.b64encode(r.stdout).decode()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def stop_recording_and_analyze() -> str:
    with _watch_lock:
        if not record_state["active"]:
            set_glow(False)
            return "Screen watching was not active."
        record_state["active"] = False
        proc = record_state.get("process")
        prompt = record_state.get("prompt") or "Analyze the screen recording and help."
    set_glow(False)

    if proc:
        try:
            proc.send_signal(signal.SIGINT)
            proc.wait(timeout=6)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    if not os.path.exists(RECORD_FILE) or os.path.getsize(RECORD_FILE) < 1000:
        return "Failed to record screen video."

    try:
        if rt.provider == "gemini":
            with open(RECORD_FILE, "rb") as f:
                video = base64.b64encode(f.read()).decode()
            answer = providers.gemini.describe_video(video, prompt)
        else:
            frame = _extract_frame(RECORD_FILE)
            answer = providers.backend().describe_frame(frame, prompt)
        answer = clean_response_text(answer) or "Analysis finished, but the model returned no text."
    except Exception as e:
        answer = f"Video analysis error: {redact(e)}"
    finally:
        try:
            os.remove(RECORD_FILE)
        except OSError:
            pass

    with store_lock:
        sess = active_session()
        sess["messages"].append({"role": "user", "parts": [{"text": "[Видеозапись экрана]"}]})
        sess["messages"].append({"role": "assistant", "parts": [{"text": answer}]})
        sess["updated"] = now_ts()
        save_sessions()
    return answer


def clipboard_image():
    """PNG bytes from the Wayland clipboard, or None."""
    try:
        r = subprocess.run([shutil.which("wl-paste") or "wl-paste", "--type", "image/png"],
                           capture_output=True, timeout=5, env=user_env())
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0 or not r.stdout:
        return None
    return r.stdout


def pick_file_dialog():
    """Path chosen in a zenity file dialog, '' if cancelled, None on timeout."""
    try:
        r = subprocess.run([ZENITY, "--file-selection"], capture_output=True, timeout=60, env=user_env())
    except subprocess.TimeoutExpired:
        return None
    except OSError:
        return ""
    path = r.stdout.decode("utf-8", errors="replace").strip()
    return path if r.returncode == 0 else ""
