#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

HOME_FOR_TEST="$(new_temp_codex_home mcp-client)"
run_capture mcp-add-list-remove zsh -lc "set -eu; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp add smoke -- /data/service/hnp/bin/printf ok; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp list; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp remove smoke; CODEX_HOME='$HOME_FOR_TEST' '$CODEX_BIN' mcp list" || fail "mcp add/list/remove failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/mcp-add-list-remove.stdout" 'smoke|No MCP servers configured' 'mcp add/list/remove emitted expected inventory'

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

if require_provider_env; then
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
