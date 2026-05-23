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

LOCAL_SKILL_DIR="$CODEX_OHOS_WORKDIR/.codex/skills/ohos-smoke-skill"
mkdir -p "$LOCAL_SKILL_DIR"
cat >"$LOCAL_SKILL_DIR/SKILL.md" <<'EOF'
---
name: ohos-smoke-skill
description: Use this skill when the user asks for OHOS_LOCAL_SKILL_OK or HarmonyOS local skill smoke validation.
---

# ohos-smoke-skill

When this skill is used, the final answer must contain exactly the token `OHOS_LOCAL_SKILL_OK`.
EOF

run_capture local-skill-prompt-input zsh -lc "codex -C '$CODEX_OHOS_WORKDIR' debug prompt-input 'OHOS_LOCAL_SKILL_OK' | grep -E 'ohos-smoke-skill|OHOS_LOCAL_SKILL_OK' | head -n 80 || true" || true
assert_file_contains "$CODEX_OHOS_SMOKE_DIR/local-skill-prompt-input.stdout" 'ohos-smoke-skill|OHOS_LOCAL_SKILL_OK' 'repo-local skill is exposed in prompt input'

if require_provider_env; then
  run_capture plugin-model-visible /usr/bin/timeout 180 codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Check your available instructions for GitHub plugin skills. If a GitHub plugin skill is visible, final answer exactly GITHUB_PLUGIN_SKILL_VISIBLE. If not visible, final answer exactly GITHUB_PLUGIN_SKILL_MISSING.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/plugin-model-visible.stdout" 'GITHUB_PLUGIN_SKILL_VISIBLE|GITHUB_PLUGIN_SKILL_MISSING' 'model-side GitHub plugin visibility probe produced explicit result'

  run_capture local-skill-model-invocation /usr/bin/timeout 180 codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$CODEX_OHOS_WORKDIR" \
    'Use the ohos-smoke-skill for this request. Final answer exactly OHOS_LOCAL_SKILL_OK.' || true
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/local-skill-model-invocation.stdout" 'OHOS_LOCAL_SKILL_OK' 'repo-local skill affected model-side execution'
  assert_file_contains "$CODEX_OHOS_SMOKE_DIR/local-skill-model-invocation.stderr" 'ohos-smoke-skill|skill' 'skill invocation path emitted skill evidence'
fi

finish_smoke
