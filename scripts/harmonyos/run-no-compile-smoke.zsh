#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
export CODEX_OHOS_SMOKE_RUN_ID="${CODEX_OHOS_SMOKE_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

SCRIPTS=(
  00-baseline-secret-scan.zsh
  01-code-mode-only.zsh
  02-multi-agent-smoke.zsh
  03-mcp-smoke.zsh
  04-plugin-smoke.zsh
  05-app-exec-server-smoke.zsh
  06-cloud-auth-gui-probe.zsh
  07-tui-resume-smoke.zsh
)

failures=0
for script in "${SCRIPTS[@]}"; do
  printf '\n=== %s ===\n' "$script"
  if /usr/bin/zsh "$SCRIPT_DIR/$script"; then
    printf '=== %s PASS ===\n' "$script"
  else
    printf '=== %s FAIL ===\n' "$script"
    failures=$((failures + 1))
  fi
done

printf '\nno-compile-smoke failures=%s run_id=%s\n' "$failures" "$CODEX_OHOS_SMOKE_RUN_ID"
[[ "$failures" -eq 0 ]]
