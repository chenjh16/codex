#!/usr/bin/env zsh

set -uo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/smoke-common.zsh"

require_codex || finish_smoke

run_capture plugin-list codex plugin list || fail "plugin list failed"
run_capture plugin-marketplace-list codex plugin marketplace list || fail "plugin marketplace list failed"
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/plugin-marketplace-list.stdout" 'openai-curated' 'plugin marketplace includes openai-curated'

if grep -E 'github@openai-curated.*installed, enabled' "$CODEX_OHOS_SMOKE_DIR/plugin-list.stdout" >/dev/null 2>&1; then
  pass "github plugin already installed"
else
  run_capture plugin-add-github /usr/bin/timeout 120 codex plugin add github@openai-curated || fail "github plugin install failed"
  run_capture plugin-list-after-add codex plugin list || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/plugin-list-after-add.stdout" 'github@openai-curated.*installed, enabled' 'github plugin installed and enabled'
fi

run_capture plugin-prompt-input zsh -lc "codex debug prompt-input 'List plugin skills only.' | grep -E 'github:|GitHub|gh-' | head -n 120 || true" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/plugin-prompt-input.stdout" 'github:' 'GitHub plugin skills are exposed in prompt input'

if require_provider_env; then
  run_capture plugin-model-visible /usr/bin/timeout 180 codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Check your available instructions for GitHub plugin skills. If a GitHub plugin skill is visible, final answer exactly GITHUB_PLUGIN_SKILL_VISIBLE. If not visible, final answer exactly GITHUB_PLUGIN_SKILL_MISSING.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/plugin-model-visible.stdout" 'GITHUB_PLUGIN_SKILL_VISIBLE|GITHUB_PLUGIN_SKILL_MISSING' 'model-side GitHub plugin visibility probe produced explicit result'
fi

finish_smoke
