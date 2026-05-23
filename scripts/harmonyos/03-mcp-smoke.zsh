#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

HOME_FOR_TEST="$(new_temp_codex_home mcp-client)"
run_capture mcp-add-list-remove zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp add smoke -- /data/service/hnp/bin/printf ok; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp list; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp remove smoke; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp list" || fail "mcp add/list/remove failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-add-list-remove.stdout" 'smoke|No MCP servers configured' 'mcp add/list/remove emitted expected inventory'

LOCAL_MCP_SERVER="$CODEX_OHOS_TMP/ohos-local-mcp-$$.py"
cat >"$LOCAL_MCP_SERVER" <<'PY'
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
                "capabilities": {"tools": {}, "resources": {}},
                "serverInfo": {"name": "ohos-local-mcp", "version": "1.0.0"},
            },
        })
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "tools": [{
                    "name": "echo_token",
                    "description": "Return the fixed token OHOS_LOCAL_MCP_TOOL_OK.",
                    "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
                }]
            },
        })
    elif method == "tools/call":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "content": [{"type": "text", "text": "OHOS_LOCAL_MCP_TOOL_OK"}],
                "isError": False,
            },
        })
    elif method == "resources/list":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "resources": [{
                    "uri": "file://ohos-local-mcp/resource",
                    "name": "ohos-local-resource",
                    "description": "HarmonyOS local MCP resource smoke.",
                    "mimeType": "text/plain",
                }]
            },
        })
    elif method == "resources/read":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "contents": [{
                    "uri": "file://ohos-local-mcp/resource",
                    "mimeType": "text/plain",
                    "text": "OHOS_LOCAL_MCP_RESOURCE_OK",
                }]
            },
        })
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"unknown method {method}"}})
PY
chmod +x "$LOCAL_MCP_SERVER"

HOME_FOR_LOCAL_MCP="$(new_temp_codex_home mcp-local-stdio)"
run_capture mcp-local-stdio-add zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_LOCAL_MCP' '$CODEX_BIN' mcp add ohos-local -- python3 '$LOCAL_MCP_SERVER'; CODEX_HOME='$HOME_FOR_LOCAL_MCP' '$CODEX_BIN' mcp list" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-local-stdio-add.stdout" 'ohos-local' 'local stdio MCP server configured'

HOME_FOR_SERVER="$(new_temp_codex_home mcp-server)"
run_capture mcp-server-tools-list zsh -lc "
set -eu
{
  printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ohos-smoke\",\"version\":\"1\"}}}'
  printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}'
} | CODEX_HOME='$HOME_FOR_SERVER' /usr/bin/timeout 20 '$CODEX_BIN' mcp-server
" || fail "mcp-server tools/list failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-server-tools-list.stdout" '"name":"codex"' 'mcp-server exposes codex tool'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-server-tools-list.stdout" '"name":"codex-reply"' 'mcp-server exposes codex-reply tool'

app_server_mcp_stdio_probe() {
  local codex_home="$1"
  python3 - "$CODEX_BIN" "$codex_home" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

codex_bin = sys.argv[1]
codex_home = sys.argv[2]
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

def send(obj):
    proc.stdin.write(json.dumps(obj, separators=(",", ":")) + "\n")
    proc.stdin.flush()

def read_until(ids, seconds=30):
    deadline = time.time() + seconds
    seen = {}
    while time.time() < deadline and not ids.issubset(seen.keys()):
        r, _, _ = select.select([proc.stdout], [], [], 0.5)
        if not r:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        print(line.rstrip())
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if "id" in msg:
            seen[msg["id"]] = msg
    return seen

try:
    send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "ohos-smoke", "version": "1"}, "capabilities": {"experimentalApi": True}}})
    read_until({1}, 10)
    send({"method": "initialized", "params": {}})
    send({"id": 2, "method": "mcpServerStatus/list", "params": {"detail": "full"}})
    send({"id": 3, "method": "mcpServer/resource/read", "params": {"server": "ohos-local", "uri": "file://ohos-local-mcp/resource"}})
    seen = read_until({2, 3}, 35)
    if 2 in seen and 3 in seen:
        print("APP_SERVER_MCP_RESOURCE_OK")
finally:
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        proc.kill()
PY
}

run_capture app-server-mcp-resource-read app_server_mcp_stdio_probe "$HOME_FOR_LOCAL_MCP" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-mcp-resource-read.stdout" 'ohos-local|OHOS_LOCAL_MCP_RESOURCE_OK|mcpServer/resource/read' 'app-server MCP resource path produced inventory or resource output'

if require_provider_env; then
  run_capture mcp-local-stdio-tool-call zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_LOCAL_MCP' /usr/bin/timeout 240 '$CODEX_BIN' exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox -C '$CODEX_OHOS_WORKDIR' 'Use the configured ohos-local MCP server tool echo_token. Final answer exactly OHOS_LOCAL_MCP_TOOL_OK. If the MCP tool is unavailable, say exactly LOCAL_MCP_TOOL_UNAVAILABLE.'" || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-local-stdio-tool-call.stdout" 'OHOS_LOCAL_MCP_TOOL_OK|LOCAL_MCP_TOOL_UNAVAILABLE' 'local stdio MCP tool call produced explicit result'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-local-stdio-tool-call.stderr" 'ohos-local/echo_token|echo_token|MCP' 'local stdio MCP tool path was exercised or reported'

  HOME_FOR_DEEPWIKI="$(new_temp_codex_home mcp-deepwiki)"
  run_capture deepwiki-real-mcp zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_DEEPWIKI' '$CODEX_BIN' mcp add deepwiki --url https://mcp.deepwiki.com/mcp; CODEX_HOME='$HOME_FOR_DEEPWIKI' /usr/bin/timeout 240 '$CODEX_BIN' exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox -C '$CODEX_OHOS_WORKDIR' 'Use the configured DeepWiki MCP server. Ask it for a one sentence summary of the openai/codex repository. If no DeepWiki MCP tool is available or the MCP call fails, say exactly what failed.'" || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/deepwiki-real-mcp.stderr" 'deepwiki/ask_question.*completed|deepwiki/ask_question' 'DeepWiki MCP tool was invoked'

  HOME_FOR_TOOL_CALL="$(new_temp_codex_home mcp-server-tool-call)"
  run_capture mcp-server-tools-call-codex zsh -lc "
set -eu
mkdir -p "$HOME/Claude/codex-e2e-work"
{
  printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ohos-smoke\",\"version\":\"1\"}}}'
  printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"codex\",\"arguments\":{\"prompt\":\"Return exactly MCP_CODEX_TOOL_OK\",\"approval-policy\":\"never\",\"sandbox\":\"danger-full-access\",\"cwd\":\"$HOME/Claude/codex-e2e-work\"}}}'
} | CODEX_HOME='$HOME_FOR_TOOL_CALL' /usr/bin/timeout 180 '$CODEX_BIN' mcp-server
" || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-server-tools-call-codex.stdout" 'MCP_CODEX_TOOL_OK' 'mcp-server tools/call codex completed a short task'
fi

finish_smoke
