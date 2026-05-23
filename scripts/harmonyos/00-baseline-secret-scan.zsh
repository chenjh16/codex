#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

run_capture codex-version codex --version || fail "codex --version failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/codex-version.stdout" 'codex-cli ' 'codex --version prints version'

run_capture codex-help zsh -lc 'codex --help >/dev/null && echo help-ok' || fail "codex --help failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/codex-help.stdout" '^help-ok$' 'codex --help works'

run_capture bundled-models codex debug models --bundled || fail "bundled models failed"

run_capture feature-list codex features list || fail "features list failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/feature-list.stdout" 'multi_agent' 'feature list includes multi_agent'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/feature-list.stdout" 'plugins' 'feature list includes plugins'

CONFIG="$HOME/.codex/config.toml"
if [[ -f "$CONFIG" ]]; then
  run_capture config-secret-scan zsh -lc "grep -nE 'sk-[A-Za-z0-9_-]{12,}|experimental_bearer_token *= *\"sk-' '$CONFIG' || true"
  assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/config-secret-scan.stdout" 'sk-[A-Za-z0-9_-]{12,}|experimental_bearer_token' 'real config has no obvious bearer secret'
  run_capture mcp-config-pollution zsh -lc "grep -nE 'mcp_servers|deepwiki|openai_docs|developers\\.openai\\.com/mcp|mcp\\.deepwiki' '$CONFIG' || true"
  assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/mcp-config-pollution.stdout" 'mcp_servers|deepwiki|openai_docs|developers\.openai\.com/mcp|mcp\.deepwiki' 'real config has no temporary MCP smoke servers'
else
  fail "missing $CONFIG"
fi

run_capture codex-mcp-list codex mcp list || fail "codex mcp list failed"

finish_smoke
