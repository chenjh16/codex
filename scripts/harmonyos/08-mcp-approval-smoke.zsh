#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

if ! require_provider_env; then
  finish_smoke
  exit $?
fi

APPROVAL_MCP_SERVER="$CODEX_OHOS_TMP/ohos-approval-mcp-$$.py"
cat >"$APPROVAL_MCP_SERVER" <<'PY'
#!/usr/bin/env python3
import json
import sys

def send(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "protocolVersion": msg.get("params", {}).get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "ohos-approval-mcp", "version": "1.0.0"},
            },
        })
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "tools": [{
                    "name": "echo_approval",
                    "description": "Return OHOS_MCP_APPROVAL_ACCEPTED.",
                    "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
                }]
            },
        })
    elif method == "tools/call":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "content": [{"type": "text", "text": "OHOS_MCP_APPROVAL_ACCEPTED"}],
                "isError": False,
            },
        })
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"unknown method {method}"}})
PY
chmod +x "$APPROVAL_MCP_SERVER"

HOME_FOR_APPROVAL="$(new_temp_codex_home mcp-approval)"
cat >>"$HOME_FOR_APPROVAL/config.toml" <<EOF

[mcp_servers.approval_smoke]
command = "python3"
args = ["$APPROVAL_MCP_SERVER"]
default_tools_approval_mode = "prompt"

[mcp_servers.approval_smoke.tools.echo_approval]
approval_mode = "prompt"
EOF

mcp_approval_probe() {
  local codex_home="$1"
  local decision="$2"
  python3 - "$CODEX_BIN" "$codex_home" "$CODEX_OHOS_WORKDIR" "$decision" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

codex_bin, codex_home, workdir, decision = sys.argv[1:5]
env = os.environ.copy()
env["CODEX_HOME"] = codex_home
proc = subprocess.Popen(
    [codex_bin, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)
next_id = 1
seen = []
thread_id = None
turn_completed = False
elicitation_seen = False
request_user_input_seen = False
approval_pending_seen = False
tool_completed_seen = False
tool_rejected_seen = False

def send(obj):
    proc.stdin.write(json.dumps(obj, separators=(",", ":")) + "\n")
    proc.stdin.flush()

def request(method, params=None):
    global next_id
    rid = next_id
    next_id += 1
    payload = {"id": rid, "method": method}
    if params is not None:
        payload["params"] = params
    send(payload)
    return rid

def read_line(timeout=1.0):
    r, _, _ = select.select([proc.stdout], [], [], timeout)
    if not r:
        return None
    return proc.stdout.readline()

def pump_until(predicate, seconds=120):
    global thread_id, turn_completed, elicitation_seen, request_user_input_seen
    global approval_pending_seen, tool_completed_seen, tool_rejected_seen
    deadline = time.time() + seconds
    while time.time() < deadline:
        line = read_line(0.5)
        if not line:
            continue
        print(line.rstrip())
        try:
            msg = json.loads(line)
        except Exception:
            continue
        seen.append(msg)
        text = json.dumps(msg, ensure_ascii=False)
        item = (msg.get("params") or {}).get("item") or {}
        if item.get("type") == "mcpToolCall" and item.get("server") == "approval_smoke":
            if item.get("status") == "inProgress":
                print("MCP_APPROVAL_TOOL_PENDING")
            if item.get("status") == "completed":
                tool_completed_seen = True
                print("MCP_APPROVAL_TOOL_COMPLETED")
            if item.get("error"):
                tool_rejected_seen = True
                print("MCP_APPROVAL_TOOL_ERROR")
        status = (msg.get("params") or {}).get("status") or {}
        if not isinstance(status, dict):
            status = {}
        if "waitingOnApproval" in text or (
            status.get("type") == "active" and "waitingOnApproval" in status.get("activeFlags", [])
        ):
            approval_pending_seen = True
            print("MCP_APPROVAL_PENDING_OK")
        if msg.get("method") == "mcpServer/elicitation/request":
            params = msg.get("params") or {}
            request = params.get("request") or {}
            meta = request.get("_meta") or params.get("_meta") or {}
            if meta.get("codex_approval_kind") == "mcp_tool_call" or params.get("serverName") == "approval_smoke":
                elicitation_seen = True
                print("MCP_APPROVAL_ELICITATION_OK")
            send({
                "id": msg["id"],
                "result": {"action": decision, "content": None, "meta": None},
            })
        elif msg.get("method") == "item/tool/requestUserInput":
            request_user_input_seen = True
            print("MCP_APPROVAL_REQUEST_USER_INPUT_OK")
            answers = {}
            params = msg.get("params") or {}
            for question in params.get("questions", []):
                qid = question.get("id")
                if not qid:
                    continue
                options = [opt.get("label", "") for opt in question.get("options") or []]
                label = ""
                if decision == "accept":
                    label = next((opt for opt in options if "allow" in opt.lower() or "accept" in opt.lower()), "")
                else:
                    label = next((opt for opt in options if "deny" in opt.lower() or "decline" in opt.lower() or "cancel" in opt.lower()), "")
                answers[qid] = {"answers": [label] if label else []}
            send({"id": msg["id"], "result": {"answers": answers}})
        elif msg.get("method") == "thread/started":
            thread = (msg.get("params") or {}).get("thread") or {}
            thread_id = thread.get("id") or thread_id
        elif msg.get("method") == "turn/completed":
            turn_completed = True
        elif "id" in msg and "result" in msg:
            result = msg.get("result") or {}
            thread = result.get("thread") or {}
            thread_id = thread.get("id") or thread_id
        if predicate():
            return True
    return False

try:
    init_id = request("initialize", {"clientInfo": {"name": "ohos-mcp-approval-smoke", "version": "1"}, "capabilities": {"experimentalApi": True}})
    pump_until(lambda: any(m.get("id") == init_id for m in seen), 15)
    send({"method": "initialized", "params": {}})
    start_id = request("thread/start", {
        "cwd": workdir,
        "approvalPolicy": "on-request",
        "sandbox": "danger-full-access",
    })
    if not pump_until(lambda: thread_id is not None and any(m.get("id") == start_id for m in seen), 30):
        print("THREAD_START_TIMEOUT")
        sys.exit(2)
    prompt = (
        "Use the approval_smoke MCP server tool echo_approval exactly once. "
        "Do not use shell commands. After the tool call, final answer with exactly the text returned by the tool. "
        "If the MCP approval is unavailable or rejected, final answer exactly MCP_APPROVAL_NOT_COMPLETED."
    )
    turn_id = request("turn/start", {
        "threadId": thread_id,
        "input": [{"type": "text", "text": prompt, "text_elements": []}],
        "approvalPolicy": "on-request",
        "sandboxPolicy": {"type": "dangerFullAccess"},
    })
    pump_until(
        lambda: (
            elicitation_seen
            or request_user_input_seen
            or tool_completed_seen
            or turn_completed
            or approval_pending_seen
        ),
        180,
    )
    if approval_pending_seen and not (elicitation_seen or request_user_input_seen):
        pump_until(lambda: elicitation_seen or request_user_input_seen or tool_completed_seen or turn_completed, 20)
    print(f"decision={decision}")
    print(f"approval_pending_seen={str(approval_pending_seen).lower()}")
    print(f"elicitation_seen={str(elicitation_seen).lower()}")
    print(f"request_user_input_seen={str(request_user_input_seen).lower()}")
    print(f"tool_completed_seen={str(tool_completed_seen).lower()}")
    print(f"tool_rejected_seen={str(tool_rejected_seen).lower()}")
    if approval_pending_seen and not (elicitation_seen or request_user_input_seen):
        print("MCP_APPROVAL_PENDING_WITHOUT_DELIVERED_REQUEST")
finally:
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        proc.kill()
PY
}

run_capture mcp-approval-decline mcp_approval_probe "$HOME_FOR_APPROVAL" decline || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-decline.stdout" 'MCP_APPROVAL_PENDING_OK|approval_pending_seen=true|MCP_APPROVAL_ELICITATION_OK|MCP_APPROVAL_REQUEST_USER_INPUT_OK' 'MCP approval decline path reached approval gate'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-decline.stdout" 'decision=decline' 'MCP approval decline path completed scripted response'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-decline.stdout" 'MCP_APPROVAL_PENDING_WITHOUT_DELIVERED_REQUEST|tool_rejected_seen=true|MCP_APPROVAL_TOOL_ERROR|request_user_input_seen=true|elicitation_seen=true' 'MCP approval decline produced response evidence or documented pending-request delivery gap'

run_capture mcp-approval-accept mcp_approval_probe "$HOME_FOR_APPROVAL" accept || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-accept.stdout" 'MCP_APPROVAL_PENDING_OK|approval_pending_seen=true|MCP_APPROVAL_ELICITATION_OK|MCP_APPROVAL_REQUEST_USER_INPUT_OK' 'MCP approval accept path reached approval gate'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-accept.stdout" 'decision=accept' 'MCP approval accept path completed scripted response'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-approval-accept.stdout" 'MCP_APPROVAL_PENDING_WITHOUT_DELIVERED_REQUEST|tool_completed_seen=true|MCP_APPROVAL_TOOL_COMPLETED|request_user_input_seen=true|elicitation_seen=true' 'MCP approval accept produced response evidence or documented pending-request delivery gap'

finish_smoke
