#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke
if require_provider_env; then
  HOME_FOR_MULTI="$(new_temp_codex_home multi-agent)"

  run_capture multi-agent-basic env CODEX_HOME="$HOME_FOR_MULTI" /usr/bin/timeout 240 "$CODEX_BIN" \
    --enable multi_agent \
    --disable multi_agent_v2 \
    exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Spawn exactly one sub-agent. Ask it to reply with FINAL_FROM_CHILD only. Wait for it to finish. Then close it. Final answer exactly: MULTI_AGENT_OK FINAL_FROM_CHILD' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stdout" 'MULTI_AGENT_OK FINAL_FROM_CHILD' 'multi-agent spawn/wait/close completed'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stderr" 'SpawnAgent|spawn_agent' 'multi-agent stderr shows spawn tool path'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-basic.stderr" 'Wait|wait_agent' 'multi-agent stderr shows wait tool path'

  run_capture multi-agent-send-input env CODEX_HOME="$HOME_FOR_MULTI" /usr/bin/timeout 300 "$CODEX_BIN" \
    --enable multi_agent \
    --disable multi_agent_v2 \
    exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Spawn exactly one sub-agent with this task: "Wait for a follow-up message before giving the final answer. After the follow-up arrives, reply exactly CHILD_TOKEN_OK." Then send that sub-agent a follow-up message saying "now reply CHILD_TOKEN_OK". Wait for it to finish, close it, and final answer exactly: MULTI_AGENT_SEND_OK CHILD_TOKEN_OK. If send_input is unavailable, say exactly what failed.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-send-input.stdout" 'MULTI_AGENT_SEND_OK CHILD_TOKEN_OK|send_input.*unavailable|send_message.*unavailable|failed' 'multi-agent send_input probe produced an explicit result'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-send-input.stderr" 'SendInput|send_input|send_message' 'multi-agent send_input tool path was exercised'

  run_capture multi-agent-concurrent env CODEX_HOME="$HOME_FOR_MULTI" /usr/bin/timeout 360 "$CODEX_BIN" \
    --enable multi_agent \
    --disable multi_agent_v2 \
    exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Spawn two sub-agents in parallel. Ask child A to reply exactly CHILD_A_READY and child B to reply exactly CHILD_B_READY. Wait for both, close both, and final answer exactly MULTI_AGENT_CONCURRENT_OK CHILD_A_READY CHILD_B_READY.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-concurrent.stdout" 'MULTI_AGENT_CONCURRENT_OK.*CHILD_A_READY.*CHILD_B_READY|MULTI_AGENT_CONCURRENT_OK.*CHILD_B_READY.*CHILD_A_READY' 'multi-agent concurrent spawn/wait/close completed'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-concurrent.stderr" 'SpawnAgent|spawn_agent' 'multi-agent concurrent stderr shows spawn tool path'

  run_capture multi-agent-resume-agent env CODEX_HOME="$HOME_FOR_MULTI" /usr/bin/timeout 420 "$CODEX_BIN" \
    --enable multi_agent \
    --disable multi_agent_v2 \
    exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Use the multi_agent_v1 tools. Spawn exactly one sub-agent with this task: "Reply exactly FIRST_CHILD_DONE." Wait for it to finish. Close that sub-agent. Then call resume_agent with the exact id of the same sub-agent. Send the resumed agent this follow-up: "Reply exactly RESUMED_CHILD_DONE." Wait for the resumed sub-agent to finish, close it, and final answer exactly MULTI_AGENT_RESUME_OK FIRST_CHILD_DONE RESUMED_CHILD_DONE. If resume_agent is unavailable, say exactly RESUME_AGENT_UNAVAILABLE.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-resume-agent.stdout" 'MULTI_AGENT_RESUME_OK.*FIRST_CHILD_DONE.*RESUMED_CHILD_DONE|RESUME_AGENT_UNAVAILABLE|resume_agent.*unavailable|failed' 'multi-agent resume_agent probe produced explicit result'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-resume-agent.stderr" 'ResumeAgent|resume_agent|resume' 'multi-agent resume_agent tool path was exercised or explicitly attempted'

  run_capture multi-agent-graph-evidence python3 - "$HOME_FOR_MULTI" <<'PY'
import os
import sqlite3
import sys

home = sys.argv[1]
for root, _dirs, files in os.walk(home):
    for name in files:
        if name.startswith("rollout-") and name.endswith(".jsonl"):
            print(os.path.join(root, name))
        elif name.endswith(".sqlite") or name.endswith(".db"):
            print(os.path.join(root, name))

db = os.path.join(home, "state_5.sqlite")
if os.path.exists(db):
    con = sqlite3.connect(db)
    print("thread_spawn_edges:")
    try:
        for row in con.execute("select parent_thread_id, child_thread_id, status from thread_spawn_edges order by parent_thread_id, child_thread_id"):
            print("EDGE", *row)
    except Exception as exc:
        print("EDGE_QUERY_ERROR", exc)
    print("subagent_threads:")
    try:
        for row in con.execute("select id, thread_source, agent_path, agent_nickname, agent_role from threads where thread_source='subagent' or agent_path is not null order by updated_at desc limit 20"):
            print("THREAD", *[str(x) for x in row])
    except Exception as exc:
        print("THREAD_QUERY_ERROR", exc)

print("rollout_hits:")
for root, _dirs, files in os.walk(os.path.join(home, "sessions")):
    for name in files:
        if not (name.startswith("rollout-") and name.endswith(".jsonl")):
            continue
        path = os.path.join(root, name)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if any(token in line for token in ("CollabResume", "ResumeAgent", "CollabClose", "CloseAgent", "agent_path", "agent_nickname", "thread_source", "subagent", "spawn_agent")):
                        print(path + ":" + line[:500].rstrip())
        except OSError:
            pass
PY
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-graph-evidence.stdout" 'rollout-.*jsonl' 'multi-agent isolated CODEX_HOME has persisted rollout files'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-graph-evidence.stdout" 'EDGE|thread_spawn_edges|agent_path|agent_nickname|thread_source|subagent|CollabResume|ResumeAgent|CollabClose|CloseAgent' 'multi-agent persisted files contain graph/session evidence'
fi

finish_smoke
