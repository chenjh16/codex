#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

if ! require_provider_env; then
  finish_smoke
  exit $?
fi

HOME_FOR_CROSS="$(new_temp_codex_home multi-agent-cross-process)"

run_capture multi-agent-cross-seed env CODEX_HOME="$HOME_FOR_CROSS" /usr/bin/timeout 420 "$CODEX_BIN" \
  --enable multi_agent \
  --disable multi_agent_v2 \
  exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  -C "$CODEX_OHOS_WORKDIR" \
  'Use multi_agent_v1. Spawn exactly one sub-agent with this task: "Reply exactly CROSS_PROCESS_CHILD_SEEDED." Wait for it to finish. Close it. Final answer exactly CROSS_PROCESS_PARENT_SEEDED CROSS_PROCESS_CHILD_SEEDED.' || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-seed.stdout" 'CROSS_PROCESS_PARENT_SEEDED.*CROSS_PROCESS_CHILD_SEEDED|CROSS_PROCESS_CHILD_SEEDED.*CROSS_PROCESS_PARENT_SEEDED' 'cross-process seed created and closed a child agent'
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-seed.stderr" 'SpawnAgent|spawn_agent|CloseAgent|close_agent' 'cross-process seed exercised spawn/close tools'

run_capture multi-agent-cross-ids python3 - "$HOME_FOR_CROSS" <<'PY'
import os
import sqlite3
import sys

home = sys.argv[1]
db = os.path.join(home, "state_5.sqlite")
if not os.path.exists(db):
    print("STATE_DB_MISSING")
    sys.exit(0)
con = sqlite3.connect(db)
rows = list(con.execute("select parent_thread_id, child_thread_id, status from thread_spawn_edges order by rowid desc limit 10"))
for row in rows:
    print("EDGE", *row)
if rows:
    parent, child, status = rows[0]
    print(f"PARENT_ID={parent}")
    print(f"CHILD_ID={child}")
    print(f"CHILD_STATUS={status}")
try:
    for row in con.execute("select id, thread_source, agent_path, agent_nickname, agent_role from threads order by updated_at desc limit 20"):
        print("THREAD", *[str(x) for x in row])
except Exception as exc:
    print("THREAD_QUERY_ERROR", exc)
PY
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-ids.stdout" 'EDGE .*closed|EDGE .*running|CHILD_ID=' 'cross-process seed persisted thread_spawn_edges'

CHILD_ID="$(awk -F= '/^CHILD_ID=/{print $2; exit}' "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-ids.stdout")"
PARENT_ID="$(awk -F= '/^PARENT_ID=/{print $2; exit}' "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-ids.stdout")"

if [[ -z "$CHILD_ID" || -z "$PARENT_ID" ]]; then
  fail "could not extract parent/child id for cross-process resume"
else
  run_capture multi-agent-cross-resume env CODEX_HOME="$HOME_FOR_CROSS" /usr/bin/timeout 480 "$CODEX_BIN" \
    --enable multi_agent \
    --disable multi_agent_v2 \
    exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    resume "$PARENT_ID" \
    "Use multi_agent_v1.resume_agent with id $CHILD_ID. Send that resumed child a follow-up asking it to reply exactly CROSS_PROCESS_CHILD_RESUMED. Wait for it to finish, close it, and final answer exactly CROSS_PROCESS_RESUME_OK CROSS_PROCESS_CHILD_RESUMED. If resume_agent fails, final answer exactly CROSS_PROCESS_RESUME_FAILED with the exact reason." || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-resume.stdout" 'CROSS_PROCESS_RESUME_OK.*CROSS_PROCESS_CHILD_RESUMED|CROSS_PROCESS_RESUME_FAILED' 'cross-process parent resume produced explicit result'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-resume.stderr" 'ResumeAgent|resume_agent|CollabResume|CROSS_PROCESS_RESUME_FAILED' 'cross-process run exercised resume_agent after process restart or reported failure'
fi

run_capture multi-agent-cross-final-graph python3 - "$HOME_FOR_CROSS" <<'PY'
import os
import sqlite3
import sys

home = sys.argv[1]
db = os.path.join(home, "state_5.sqlite")
print("home", home)
if os.path.exists(db):
    con = sqlite3.connect(db)
    print("thread_spawn_edges:")
    for row in con.execute("select parent_thread_id, child_thread_id, status from thread_spawn_edges order by parent_thread_id, child_thread_id"):
        print("EDGE", *row)
print("rollout_resume_hits:")
for root, _dirs, files in os.walk(os.path.join(home, "sessions")):
    for name in files:
        if not (name.startswith("rollout-") and name.endswith(".jsonl")):
            continue
        path = os.path.join(root, name)
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if any(token in line for token in ("CollabResume", "ResumeAgent", "CROSS_PROCESS_CHILD_RESUMED", "CROSS_PROCESS_RESUME")):
                    print(path + ":" + line[:500].rstrip())
PY
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/multi-agent-cross-final-graph.stdout" 'EDGE|CollabResume|ResumeAgent|CROSS_PROCESS' 'cross-process final graph contains resume evidence'

finish_smoke
