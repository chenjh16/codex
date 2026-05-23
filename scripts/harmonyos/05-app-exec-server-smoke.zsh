#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

UNIX_PROBE="$CODEX_OHOS_TMP/ohos-python-unix-$$.sock"
run_capture python-unix-socket-bind python3 - "$UNIX_PROBE" <<'PY'
import os
import socket
import sys
path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.bind(path)
    print("python_unix_bind=ok")
finally:
    s.close()
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
PY
if [[ "$?" -eq 0 ]]; then
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/python-unix-socket-bind.stdout" 'python_unix_bind=ok' 'plain Python AF_UNIX bind works'
else
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/python-unix-socket-bind.stderr" 'Operation not permitted|PermissionError|Errno 1|Permission denied' 'plain Python AF_UNIX bind produced explicit OHOS platform/permission result'
fi

APP_UNIX="$CODEX_OHOS_TMP/codex-app-server-$$.sock"
run_capture app-server-unix /usr/bin/timeout 5 codex app-server --listen "unix://$APP_UNIX" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-unix.stderr" 'Operation not permitted|os error 1|Address already in use|Permission denied' 'app-server unix socket produced explicit platform/path result'

ws_probe() {
  local port="$1"
  python3 - "$port" <<'PY'
import base64
import os
import socket
import sys
import time
port = int(sys.argv[1])
deadline = time.time() + 8
last = None
while time.time() < deadline:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=1)
        break
    except OSError as exc:
        last = exc
        time.sleep(0.2)
else:
    print(f"connect_failed={last}")
    sys.exit(2)
key = base64.b64encode(os.urandom(16)).decode()
req = (
    "GET / HTTP/1.1\r\n"
    f"Host: 127.0.0.1:{port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    "\r\n"
)
s.sendall(req.encode())
resp = s.recv(4096).decode("latin1", "replace")
print(resp.split("\r\n\r\n", 1)[0])
s.close()
PY
}

kill_matching_processes() {
  local pat="$1"
  local pid
  for pid in $(ps -ef | awk -v pat="$pat" 'index($0, pat) && $0 !~ /awk/ {print $2}'); do
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
  for pid in $(ps -ef | awk -v pat="$pat" 'index($0, pat) && $0 !~ /awk/ {print $2}'); do
    kill -9 "$pid" >/dev/null 2>&1 || true
  done
}

APP_PORT=$((45680 + ($$ % 1000)))
APP_OUT="$CODEX_OHOS_SMOKE_DIR/app-server-ws-process.stdout"
APP_ERR="$CODEX_OHOS_SMOKE_DIR/app-server-ws-process.stderr"
/usr/bin/timeout 20 codex app-server --listen "ws://127.0.0.1:$APP_PORT" >"$APP_OUT.raw" 2>"$APP_ERR.raw" &
APP_PID=$!
run_capture app-server-ws-handshake ws_probe "$APP_PORT" || true
kill "$APP_PID" >/dev/null 2>&1 || true
wait "$APP_PID" >/dev/null 2>&1 || true
kill_matching_processes "codex app-server --listen ws://127.0.0.1:$APP_PORT"
redact_file "$APP_OUT.raw" >"$APP_OUT"; redact_file "$APP_ERR.raw" >"$APP_ERR"; rm -f "$APP_OUT.raw" "$APP_ERR.raw"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-ws-handshake.stdout" '101 Switching Protocols|HTTP/1.1 101|HTTP/1.1 401|HTTP/1.1 403' 'app-server ws accepted a protocol-level handshake or explicit auth rejection'

EXEC_PORT=$((46680 + ($$ % 1000)))
EXEC_OUT="$CODEX_OHOS_SMOKE_DIR/exec-server-ws-process.stdout"
EXEC_ERR="$CODEX_OHOS_SMOKE_DIR/exec-server-ws-process.stderr"
/usr/bin/timeout 20 codex exec-server --listen "ws://127.0.0.1:$EXEC_PORT" >"$EXEC_OUT.raw" 2>"$EXEC_ERR.raw" &
EXEC_PID=$!
run_capture exec-server-ws-handshake ws_probe "$EXEC_PORT" || true
kill "$EXEC_PID" >/dev/null 2>&1 || true
wait "$EXEC_PID" >/dev/null 2>&1 || true
kill_matching_processes "codex exec-server --listen ws://127.0.0.1:$EXEC_PORT"
redact_file "$EXEC_OUT.raw" >"$EXEC_OUT"; redact_file "$EXEC_ERR.raw" >"$EXEC_ERR"; rm -f "$EXEC_OUT.raw" "$EXEC_ERR.raw"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/exec-server-ws-handshake.stdout" '101 Switching Protocols|HTTP/1.1 101|HTTP/1.1 401|HTTP/1.1 403' 'exec-server ws accepted a protocol-level handshake or explicit auth rejection'

run_capture exec-server-stdio /usr/bin/timeout 5 codex exec-server --listen stdio:// || true

finish_smoke
