#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

run_capture login-status codex login status || true
cat "$CODEX_OHOS_SMOKE_DIR/login-status.stdout" "$CODEX_OHOS_SMOKE_DIR/login-status.stderr" >"$CODEX_OHOS_SMOKE_DIR/login-status.combined"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/login-status.combined" 'Not logged in|Logged in|ChatGPT' 'login status produced explicit auth state'

run_capture cloud-list /usr/bin/timeout 30 codex cloud list || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/cloud-list.stderr" 'codex login|Not logged in|CODEX_ACCESS_TOKEN|error|Error|login' 'cloud list produced explicit auth result'

run_capture agent-identity-auth zsh -lc "CODEX_ACCESS_TOKEN= /usr/bin/timeout 10 codex exec-server --remote https://example.invalid --environment-id ohos-smoke --use-agent-identity-auth" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/agent-identity-auth.stderr" 'CODEX_ACCESS_TOKEN|required|missing|error|Error' 'agent identity path reports missing token'

run_capture gui-command-probe zsh -lc 'for c in open xdg-open google-chrome chromium firefox; do if command -v "$c" >/dev/null 2>&1; then echo "$c=$(command -v "$c")"; else echo "$c=missing"; fi; done'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/gui-command-probe.stdout" 'open=missing' 'open command absent or explicitly reported'

run_capture prompt-input-gui-probe zsh -lc "codex debug prompt-input 'List GUI/browser tools only.' | grep -E 'Browser Use|Computer Use|browser-use|computer_use|in_app_browser|mcp__computer' || true"
assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/prompt-input-gui-probe.stdout" 'Browser Use|Computer Use|browser-use|computer_use|mcp__computer' 'GUI/browser tools not exposed in SSH prompt input'

finish_smoke
