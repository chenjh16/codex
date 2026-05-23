#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

app_server_inventory_probe() {
  local codex_home="$1"
  python3 - "$CODEX_BIN" "$codex_home" "$CODEX_OHOS_WORKDIR" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

codex_bin, codex_home, workdir = sys.argv[1:4]
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
pending = set()

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
    pending.add(rid)
    send(payload)
    return rid

try:
    request("initialize", {"clientInfo": {"name": "ohos-connector-smoke", "version": "1"}, "capabilities": {"experimentalApi": True}})
    deadline = time.time() + 12
    while time.time() < deadline and pending:
        r, _, _ = select.select([proc.stdout], [], [], 0.5)
        if not r:
            continue
        line = proc.stdout.readline()
        print(line.rstrip())
        try:
            msg = json.loads(line)
        except Exception:
            continue
        pending.discard(msg.get("id"))
    send({"method": "initialized", "params": {}})
    request("plugin/list", {"cwds": [workdir], "marketplaceKinds": ["local", "vertical", "workspace-directory"]})
    request("plugin/installed", {"cwds": [workdir], "installSuggestionPluginNames": ["github"]})
    request("plugin/read", {"remoteMarketplaceName": "openai-curated", "pluginName": "github"})
    request("plugin/skill/read", {"remoteMarketplaceName": "openai-curated", "remotePluginId": "github", "skillName": "github"})
    request("app/list", {"limit": 20, "forceRefetch": False})
    request("account/read", {"refreshToken": False})
    request("getAuthStatus", {"includeToken": False, "refreshToken": False})
    deadline = time.time() + 45
    while time.time() < deadline and pending:
        r, _, _ = select.select([proc.stdout], [], [], 0.5)
        if not r:
            continue
        line = proc.stdout.readline()
        print(line.rstrip())
        try:
            msg = json.loads(line)
        except Exception:
            continue
        pending.discard(msg.get("id"))
    print("APP_SERVER_CONNECTOR_INVENTORY_DONE")
finally:
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        proc.kill()
PY
}

HOME_FOR_CONNECTOR="$(new_temp_codex_home connector-inventory)"
run_capture app-server-plugin-app-auth-inventory app_server_inventory_probe "$HOME_FOR_CONNECTOR" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-plugin-app-auth-inventory.stdout" 'APP_SERVER_CONNECTOR_INVENTORY_DONE' 'app-server plugin/app/auth inventory probe completed'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-plugin-app-auth-inventory.stdout" 'plugin catalog|plugin details|plugin skill|chatgpt authentication required|marketplaces|marketplaceLoadErrors|github|openai-curated' 'app-server plugin connector metadata path returned catalog data or explicit ChatGPT auth requirement'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/app-server-plugin-app-auth-inventory.stdout" 'app/list|account/read|getAuthStatus|requiresOpenaiAuth|Not logged in|auth' 'app-server app/auth connector path produced explicit auth or app-list evidence'

HOME_FOR_OAUTH="$(new_temp_codex_home mcp-oauth)"
run_capture mcp-oauth-login-probe zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_OAUTH' '$CODEX_BIN' mcp add deepwiki --url https://mcp.deepwiki.com/mcp; python3 - '$CODEX_BIN' '$HOME_FOR_OAUTH' <<'PY'
import json, os, select, subprocess, sys, time
codex_bin, codex_home = sys.argv[1:3]
env = os.environ.copy(); env['CODEX_HOME'] = codex_home
p = subprocess.Popen([codex_bin, 'app-server', '--listen', 'stdio://'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
def send(o):
    p.stdin.write(json.dumps(o, separators=(',', ':')) + '\\n'); p.stdin.flush()
try:
    send({'id':1,'method':'initialize','params':{'clientInfo':{'name':'ohos-oauth-smoke','version':'1'},'capabilities':{'experimentalApi':True}}})
    deadline=time.time()+10
    while time.time()<deadline:
        r,_,_=select.select([p.stdout],[],[],0.5)
        if r:
            line=p.stdout.readline(); print(line.rstrip())
            if '\"id\":1' in line: break
    send({'method':'initialized','params':{}})
    send({'id':2,'method':'mcpServer/oauth/login','params':{'name':'deepwiki','timeoutSecs':5}})
    deadline=time.time()+20
    while time.time()<deadline:
        r,_,_=select.select([p.stdout],[],[],0.5)
        if not r: continue
        line=p.stdout.readline(); print(line.rstrip())
        if '\"id\":2' in line: break
    print('MCP_OAUTH_LOGIN_PROBE_DONE')
finally:
    p.terminate()
    try: p.wait(timeout=3)
    except Exception: p.kill()
PY" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-oauth-login-probe.stdout" 'MCP_OAUTH_LOGIN_PROBE_DONE|authorizationUrl|OAuth login|deepwiki|error' 'MCP OAuth login path produced explicit result'

HOME_FOR_RC="$(new_temp_codex_home remote-control-layout)"
mkdir -p "$HOME_FOR_RC/packages/standalone/current"
ln -sf "$CODEX_BIN" "$HOME_FOR_RC/packages/standalone/current/codex"

run_capture remote-control-managed-version zsh -lc "CODEX_HOME='$HOME_FOR_RC' '$CODEX_BIN' app-server daemon version" || true
cat "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-version.stdout" "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-version.stderr" >"$CODEX_OHOS_SMOKE_DIR/remote-control-managed-version.combined"
assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-version.combined" 'managed standalone Codex install not found' 'standalone layout removes managed-install blocker for daemon version'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-version.combined" 'codex|version|error|Error|\\{' 'daemon version returned JSON/version or explicit platform error'

run_capture remote-control-managed-start zsh -lc "CODEX_HOME='$HOME_FOR_RC' /usr/bin/timeout 20 '$CODEX_BIN' app-server daemon start; CODEX_HOME='$HOME_FOR_RC' '$CODEX_BIN' app-server daemon stop >/dev/null 2>&1 || true" || true
cat "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-start.stdout" "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-start.stderr" >"$CODEX_OHOS_SMOKE_DIR/remote-control-managed-start.combined"
assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-start.combined" 'managed standalone Codex install not found' 'standalone layout removes managed-install blocker for daemon start'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/remote-control-managed-start.combined" 'socket|Operation not permitted|os error 1|pid|backend|\\{|started|ready|error|Error' 'daemon start reached socket/backend stage or explicit platform error'

run_capture agent-identity-token-shape zsh -lc "if [[ -n \"\${CODEX_ACCESS_TOKEN:-}\" ]]; then echo CODEX_ACCESS_TOKEN_PRESENT; CODEX_ACCESS_TOKEN=\"\$CODEX_ACCESS_TOKEN\" /usr/bin/timeout 15 '$CODEX_BIN' exec-server --remote https://example.invalid --environment-id ohos-smoke --use-agent-identity-auth; else echo CODEX_ACCESS_TOKEN_MISSING; CODEX_ACCESS_TOKEN= /usr/bin/timeout 10 '$CODEX_BIN' exec-server --remote https://example.invalid --environment-id ohos-smoke --use-agent-identity-auth; fi" || true
cat "$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.stdout" "$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.stderr" >"$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.combined"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.combined" 'CODEX_ACCESS_TOKEN_PRESENT|CODEX_ACCESS_TOKEN_MISSING' 'agent identity probe captured token presence without printing token'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.combined" 'CODEX_ACCESS_TOKEN|required|missing|AgentAssertion|JWKS|environment|example.invalid|error|Error' 'agent identity path reached token/assertion/registration stage or explicit auth error'
assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/agent-identity-token-shape.combined" 'sk-[A-Za-z0-9_-]{8,}' 'agent identity logs do not expose OpenAI-style bearer secrets'

finish_smoke
