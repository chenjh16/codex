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

Latest known full pass:

```text
CODEX_OHOS_SMOKE_RUN_ID=20260523-1905-full
no-compile-smoke failures=0
```
