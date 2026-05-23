#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke
if require_provider_env; then
  run_capture multi-agent-basic /usr/bin/timeout 240 codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Spawn exactly one sub-agent. Ask it to reply with FINAL_FROM_CHILD only. Wait for it to finish. Then close it. Final answer exactly: MULTI_AGENT_OK FINAL_FROM_CHILD' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stdout" 'MULTI_AGENT_OK FINAL_FROM_CHILD' 'multi-agent spawn/wait/close completed'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stderr" 'SpawnAgent|spawn_agent' 'multi-agent stderr shows spawn tool path'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stderr" 'Wait|wait_agent' 'multi-agent stderr shows wait tool path'

  run_capture multi-agent-send-input /usr/bin/timeout 300 codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Spawn exactly one sub-agent with this task: "Wait for a follow-up message before giving the final answer. After the follow-up arrives, reply exactly CHILD_TOKEN_OK." Then send that sub-agent a follow-up message saying "now reply CHILD_TOKEN_OK". Wait for it to finish, close it, and final answer exactly: MULTI_AGENT_SEND_OK CHILD_TOKEN_OK. If send_input is unavailable, say exactly what failed.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-send-input.stdout" 'MULTI_AGENT_SEND_OK CHILD_TOKEN_OK|send_input.*unavailable|send_message.*unavailable|failed' 'multi-agent send_input probe produced an explicit result'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-send-input.stderr" 'SendInput|send_input|send_message' 'multi-agent send_input tool path was exercised'
fi

finish_smoke
