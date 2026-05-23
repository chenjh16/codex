# HarmonyOS no-compile smoke scripts

These scripts validate the already-built HarmonyOS Codex binary without running
`cargo build`.

Runtime location on the HarmonyOS PC:

```sh
~/Claude/codex-ohos/scripts/run-no-compile-smoke.zsh
```

The scripts expect:

- `~/Claude/codex-ohos/env.sh`
- `~/Claude/codex-openai/codex-rs/target/release/codex`
- `~/.local/bin/codex`
- `SUBAPI_ELIAS_API_KEY` and `SUBAPI_ELIAS_BASE_URL` in the environment for
  provider-backed tests

Important: `~/.local/bin/codex` forces `CODEX_HOME="$HOME/.codex"`. Tests that
need an isolated `CODEX_HOME` call the signed release binary directly.

Latest full pass:

```text
CODEX_OHOS_SMOKE_RUN_ID=20260524-agent-full
no-compile-smoke failures=0
```

This pass includes the expanded deep Agent checks:

- `08-mcp-approval-smoke.zsh`: app-server `mcpServer/elicitation/request`
  for prompt-mode MCP tool approval.
- `09-connector-remote-identity-smoke.zsh`: plugin/app/auth inventory,
  MCP OAuth probe, remote-control standalone layout probe, and
  `CODEX_ACCESS_TOKEN`/Agent identity probe.
- `10-multi-agent-cross-process-smoke.zsh`: cross-process parent resume and
  `resume_agent` for a closed child.

Previous full pass:

```text
CODEX_OHOS_SMOKE_RUN_ID=20260523-2210-agent-full
no-compile-smoke failures=0
```

Expanded Agent suite targeted passes:

```text
CODEX_OHOS_SMOKE_RUN_ID=20260523-2145-multi-agent-v2  failures=0
CODEX_OHOS_SMOKE_RUN_ID=20260523-2145-mcp-v2          failures=0
CODEX_OHOS_SMOKE_RUN_ID=20260523-2145-plugin-v2       failures=0
CODEX_OHOS_SMOKE_RUN_ID=20260523-2130-app-exec        failures=0
```

Previous full pass before the expanded suite:

```text
CODEX_OHOS_SMOKE_RUN_ID=20260523-1905-full
no-compile-smoke failures=0
```
