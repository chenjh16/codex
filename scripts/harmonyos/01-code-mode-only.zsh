#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke
if require_provider_env; then
  HOME_FOR_TEST="$(new_temp_codex_home code-mode-only)"
  run_capture code-mode-only env CODEX_HOME="$HOME_FOR_TEST" /usr/bin/timeout 180 "$CODEX_BIN" exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    --enable code_mode \
    --enable code_mode_only \
    -C "$CODEX_OHOS_WORKDIR" \
    'Use Code Mode to compute 6 * 7. If Code Mode is unavailable, return the exact unavailable message.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/code-mode-only.stdout" 'Code Mode is unavailable|rusty_v8|aarch64-unknown-linux-ohos' 'Code Mode explicitly reports OHOS stub'
  assert_file_not_contains "$CODEX_OHOS_SMOKE_DIR/code-mode-only.stdout" '^42$' 'Code Mode smoke did not silently pass through shell exec as success'
fi

finish_smoke
