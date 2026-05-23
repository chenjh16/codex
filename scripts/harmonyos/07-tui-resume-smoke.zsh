#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

pty_probe() {
  local mode="$1"
  shift
  python3 - "$mode" "$CODEX_OHOS_SMOKE_DIR" "$@" <<'PY'
import os
import pty
import re
import select
import signal
import sys
import time
import fcntl
import struct
import termios

mode = sys.argv[1]
log_dir = sys.argv[2]
cmd = sys.argv[3:]

ansi_re = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)|\x1b[()][A-Za-z0-9]|[\x00-\x08\x0b\x0c\x0e-\x1f]")

def clean(data: bytes) -> str:
    data = re.sub(rb"sk-[A-Za-z0-9_-]{8,}", b"sk-REDACTED", data)
    return ansi_re.sub(b"", data).decode("utf-8", "replace")

pid, fd = pty.fork()
if pid == 0:
    os.environ.setdefault("TERM", "xterm-256color")
    os.environ.setdefault("COLUMNS", "100")
    os.environ.setdefault("LINES", "30")
    os.execvp(cmd[0], cmd)

try:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
except OSError:
    pass

buf = b""

def respond_to_terminal_queries(chunk: bytes):
    # Ratatui/crossterm can query terminal state during startup. A bare PTY is
    # not a terminal emulator, so answer the common xterm queries that otherwise
    # leave the UI half-initialized in automation.
    responses = []
    if b"\x1b[6n" in chunk:
        responses.append(b"\x1b[24;80R")
    if b"\x1b[c" in chunk:
        responses.append(b"\x1b[?1;2c")
    if b"\x1b[>c" in chunk:
        responses.append(b"\x1b[>0;0;0c")
    if b"\x1b]10;?\x07" in chunk or b"\x1b]10;?\x1b\\" in chunk:
        responses.append(b"\x1b]10;rgb:ffff/ffff/ffff\x07")
    if b"\x1b]11;?\x07" in chunk or b"\x1b]11;?\x1b\\" in chunk:
        responses.append(b"\x1b]11;rgb:0000/0000/0000\x07")
    for response in responses:
        try:
            os.write(fd, response)
        except OSError:
            pass

def read_for(seconds, stop_text=None):
    global buf
    deadline = time.time() + seconds
    stop_bytes = stop_text.encode() if stop_text else None
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            chunk = os.read(fd, 8192)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        respond_to_terminal_queries(chunk)
        if stop_bytes and stop_bytes in clean(buf).encode():
            break

def write_text(text):
    os.write(fd, text.encode())

ok = False
try:
    if mode == "agent-picker":
        read_for(30, "›")
        write_text("/agent\r")
        read_for(15)
        text = clean(buf)
        ok = bool(re.search(r"(?i)(agent|sub-agent|picker|no agents|No agents available|select)", text))
        write_text("\x1b")
        write_text("/quit\r")
        read_for(4)
        print("agent_picker_seen=" + ("yes" if ok else "no"))
    elif mode == "resume-last":
        read_for(30, "›")
        write_text("Reply with the lowercase reverse of ZxCv only.\r\r")
        read_for(120, "vcxz")
        text = clean(buf)
        ok = "vcxz" in text
        write_text("/quit\r")
        read_for(4)
        print("resume_last_marker_seen=" + ("yes" if ok else "no"))
    else:
        print(f"unknown_mode={mode}")
finally:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass
    with open(os.path.join(log_dir, f"pty-{mode}.log"), "w", encoding="utf-8") as f:
        f.write(clean(buf))

sys.exit(0 if ok else 1)
PY
}

if require_provider_env; then
  HOME_FOR_RESUME="$(new_temp_codex_home resume-last)"
  OLD_CODEX_HOME="${CODEX_HOME:-}"
  export CODEX_HOME="$HOME_FOR_RESUME"

  run_capture resume-seed /usr/bin/timeout 180 "$CODEX_BIN" exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Return exactly RESUME_SEED_READY' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/resume-seed.stdout" 'RESUME_SEED_READY' 'non-interactive seed session completed'

  run_capture resume-last-pty pty_probe resume-last "$CODEX_BIN" resume \
    --last \
    --include-non-interactive \
    --no-alt-screen \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/resume-last-pty.stdout" 'resume_last_marker_seen=yes' 'resume --last --include-non-interactive completed prompt in PTY'

  if [[ -n "$OLD_CODEX_HOME" ]]; then
    export CODEX_HOME="$OLD_CODEX_HOME"
  else
    unset CODEX_HOME
  fi
fi

run_capture tui-agent-picker pty_probe agent-picker codex \
  --no-alt-screen \
  --dangerously-bypass-approvals-and-sandbox \
  -C "$CODEX_OHOS_WORKDIR" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/tui-agent-picker.stdout" 'agent_picker_seen=yes' 'TUI /agent picker produced agent-related UI output'

finish_smoke
