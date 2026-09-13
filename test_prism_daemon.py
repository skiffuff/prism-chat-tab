import os
import sys
import json
import base64
import time
import shutil

# --- Setup test environment ---
TEST_ENV = "/tmp/prism_test_env"
os.makedirs(TEST_ENV, exist_ok=True)
os.makedirs(f"{TEST_ENV}/.config/prism", exist_ok=True)
os.makedirs(f"{TEST_ENV}/.local/share/prism", exist_ok=True)
os.makedirs(f"{TEST_ENV}/run", exist_ok=True)

# Set env vars to isolate the daemon
os.environ["HOME"] = TEST_ENV
os.environ["PRISM_CONFIG"] = f"{TEST_ENV}/.config/prism/config.json"
os.environ["PRISM_TOKEN_FILE"] = f"{TEST_ENV}/.local/share/prism/daemon.token"
os.environ["XDG_RUNTIME_DIR"] = f"{TEST_ENV}/run"
os.environ["DBUS_SESSION_BUS_ADDRESS"] = ""

# Copy the daemon to test env
shutil.copy("/home/skiffu/prism-chat-tab/backend/prism_daemon.py", f"{TEST_ENV}/.local/share/prism/prism_daemon.py")

# Add the test environment to the path
sys.path.insert(0, f"{TEST_ENV}/.local/share/prism")

# --- Import and Test ---
# Must import after setting up env
import prism_daemon
# Re-load config to make it use the mocked env
prism_daemon.CONFIG_FILE = os.environ["PRISM_CONFIG"]
prism_daemon.TOKEN_FILE = os.environ["PRISM_TOKEN_FILE"]
prism_daemon._load_config()
prism_daemon._ensure_token_file()

# Helper to run tests
def test_daemon():
    print("Running tests...")

    # Test 1: Dangerous pattern detection
    if prism_daemon._is_dangerous("rm -rf /") != True:
        print("FAILED: _is_dangerous('rm -rf /')")
    else:
        print("PASSED: _is_dangerous('rm -rf /')")

    if prism_daemon._is_dangerous("ls") != False:
        print("FAILED: _is_dangerous('ls')")
    else:
        print("PASSED: _is_dangerous('ls')")

    # Test 2: Allowed pattern check
    # Need to register a pattern first
    prism_daemon._grant_pattern("ls")

    # We need to verify if the pattern was actually saved/loaded in the environment.
    # The `test_prism_daemon.py` seems to have imported `prism_daemon` *after* setting
    # `TOKEN_FILE` etc, but `ALLOWED_PATTERNS` might be static.
    # Let's check `prism_daemon.ALLOWED_PATTERNS` directly.
    print(f"DEBUG: ALLOWED_PATTERNS = {prism_daemon.ALLOWED_PATTERNS}")

    if prism_daemon._command_ok_by_pattern("ls") != True:
        print("FAILED: _command_ok_by_pattern('ls')")
    else:
        print("PASSED: _command_ok_by_pattern('ls')")

    # Test 3: Path traversal check
    # Try /etc/passwd
    if prism_daemon._allowed_read_path("/etc/passwd") != None:
        print("FAILED: _allowed_read_path('/etc/passwd') should be None")
    else:
        print("PASSED: _allowed_read_path('/etc/passwd')")

    # Try valid path
    valid_file = f"{TEST_ENV}/test.txt"
    with open(valid_file, "w") as f:
        f.write("hello")
    if prism_daemon._allowed_read_path(valid_file) != os.path.abspath(valid_file):
        print(f"FAILED: _allowed_read_path({valid_file})")
    else:
        print("PASSED: _allowed_read_path()")

if __name__ == "__main__":
    test_daemon()
