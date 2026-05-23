#!/usr/bin/env zsh

set -uo pipefail

if [[ -f "$HOME/Claude/codex-ohos/env.sh" ]]; then
  source "$HOME/Claude/codex-ohos/env.sh"
fi

export PATH="$HOME/.local/bin:$HOME/Claude/codex-ohos/bin:$PATH"
: "${CODEX_BIN:=$HOME/Claude/codex-openai/codex-rs/target/release/codex}"

: "${CODEX_OHOS_TMP:=$HOME/Claude/tmpdir}"
: "${CODEX_OHOS_SMOKE_ROOT:=$HOME/Claude/codex-ohos/logs/smoke}"
: "${CODEX_OHOS_SMOKE_RUN_ID:=$(date +%Y%m%d-%H%M%S)}"
: "${CODEX_OHOS_SMOKE_DIR:=$CODEX_OHOS_SMOKE_ROOT/$CODEX_OHOS_SMOKE_RUN_ID}"
: "${CODEX_OHOS_WORKDIR:=$HOME/Claude/codex-e2e-work}"

mkdir -p "$CODEX_OHOS_TMP" "$CODEX_OHOS_SMOKE_DIR" "$CODEX_OHOS_WORKDIR"

SMOKE_FAILURES=0
SMOKE_SKIPS=0

smoke_log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

redact_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -E 's/sk-[A-Za-z0-9_-]{8,}/sk-REDACTED/g; s/(Authorization: Bearer )[A-Za-z0-9._-]+/\1REDACTED/g' "$file"
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

run_capture() {
  local name="$1"
  shift
  local safe
  safe="$(safe_name "$name")"
  local raw_out="$CODEX_OHOS_SMOKE_DIR/$safe.stdout.raw"
  local raw_err="$CODEX_OHOS_SMOKE_DIR/$safe.stderr.raw"
  local out="$CODEX_OHOS_SMOKE_DIR/$safe.stdout"
  local err="$CODEX_OHOS_SMOKE_DIR/$safe.stderr"
  local rc_file="$CODEX_OHOS_SMOKE_DIR/$safe.rc"

  smoke_log "RUN $name"
  "$@" >"$raw_out" 2>"$raw_err"
  local rc=$?
  printf '%s\n' "$rc" >"$rc_file"
  redact_file "$raw_out" >"$out"
  redact_file "$raw_err" >"$err"
  rm -f "$raw_out" "$raw_err"
  smoke_log "RC  $name = $rc"
  return "$rc"
}

pass() {
  smoke_log "PASS $*"
}

fail() {
  smoke_log "FAIL $*"
  SMOKE_FAILURES=$((SMOKE_FAILURES + 1))
}

skip() {
  smoke_log "SKIP $*"
  SMOKE_SKIPS=$((SMOKE_SKIPS + 1))
}

require_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    fail "codex not found on PATH"
    return 1
  fi
  if [[ ! -x "$CODEX_BIN" ]]; then
    fail "Codex release binary is not executable: $CODEX_BIN"
    return 1
  fi
  return 0
}

require_provider_env() {
  if [[ -z "${SUBAPI_ELIAS_API_KEY:-}" || -z "${SUBAPI_ELIAS_BASE_URL:-}" ]]; then
    skip "SUBAPI_ELIAS_API_KEY or SUBAPI_ELIAS_BASE_URL missing; provider-backed smoke skipped"
    return 1
  fi
  return 0
}

new_temp_codex_home() {
  local name="$1"
  local dir="$CODEX_OHOS_TMP/codex-home-$name-$$"
  rm -rf "$dir"
  mkdir -p "$dir"
  if [[ -f "$HOME/.codex/config.toml" ]]; then
    cp "$HOME/.codex/config.toml" "$dir/config.toml"
  fi
  printf '%s\n' "$dir"
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -E "$pattern" "$file" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
    smoke_log "Missing pattern: $pattern in $file"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -E "$pattern" "$file" >/dev/null 2>&1; then
    fail "$label"
    smoke_log "Unexpected pattern: $pattern in $file"
  else
    pass "$label"
  fi
}

finish_smoke() {
  smoke_log "logs: $CODEX_OHOS_SMOKE_DIR"
  smoke_log "failures=$SMOKE_FAILURES skips=$SMOKE_SKIPS"
  [[ "$SMOKE_FAILURES" -eq 0 ]]
}
