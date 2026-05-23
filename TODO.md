# TODO: Codex CLI on HarmonyOS PC

更新时间：2026-05-24 00:35 CST

## 当前目标

HarmonyOS PC 上 Codex CLI 的当前 TUI 端到端验收已完成：第一阶段非交互式 CLI 已通过；TUI 启动时的 bubblewrap 警告已修复、构建已完成并推送。安全版内存 PTY harness 下已验证 TUI 可启动、渲染、输入并提交两轮 prompt、收到两轮模型响应、通过 `/quit` 退出，且无 bubblewrap warning、panic、API error 或遗留 TUI 进程。

当前新增目标是完成用户目录安装、补齐经验文档、将远端源码仓库文档提交到 GitHub `ohos` 分支，并输出一份中文 Agent 能力缺口分析。2026-05-23 后续专项 smoke 已补充覆盖 Code Mode、Linux sandbox 显式命令、多 Agent、MCP client/server、真实 DeepWiki streamable HTTP MCP、plugin/skill、app-server/remote-control/exec-server、cloud/Agent identity 和 GUI 环境边界。

2026-05-24 00:35 CST 更新：无编译验收脚本已固化到本地 `scripts/` 和远端 `~/Claude/codex-ohos/scripts/`。总入口为：

```sh
~/Claude/codex-ohos/scripts/run-no-compile-smoke.zsh
```

最新完整运行 `CODEX_OHOS_SMOKE_RUN_ID=20260524-agent-full` 已通过，输出 `no-compile-smoke failures=0`。该轮在原 `20260523-2210-agent-full` 的基础上新增了 MCP tool approval app-server elicitation、connector/plugin/app/auth inventory、MCP OAuth probe、remote-control standalone layout probe、`CODEX_ACCESS_TOKEN`/Agent identity probe，以及跨进程 parent resume 后 `resume_agent` 恢复 closed child 的端到端验证。

## 远端入口和路径

- SSH：`ssh -p 22222 chenjh@localhost`
- 远端命令必须显式用 zsh：`ssh -p 22222 ... /usr/bin/zsh` 或 `"/usr/bin/zsh -lc '...'"`。
- 远端源码：`/storage/Users/currentUser/Claude/codex-openai`
- 远端辅助目录：`/storage/Users/currentUser/Claude/codex-ohos`
- wrapper：`/storage/Users/currentUser/Claude/codex-ohos/bin/codex`
- 用户安装命令：`/storage/Users/currentUser/.local/bin/codex`
- build log：`/storage/Users/currentUser/Claude/codex-ohos/logs/build-codex-cli.log`
- build status：`/storage/Users/currentUser/Claude/codex-ohos/logs/build-codex-cli.status`
- build pid：`/storage/Users/currentUser/Claude/codex-ohos/logs/build-codex-cli.pid`
- 目标二进制：`/storage/Users/currentUser/Claude/codex-openai/codex-rs/target/release/codex`

## 已完成

- 远端 Codex CLI release build 曾于 2026-05-23 01:03 CST 成功完成，`rc=0`。
- 目标二进制已签名，`codex --version` 输出 `codex-cli 0.0.0`。
- `codex debug models --bundled` 通过。
- 远端 `~/.codex/config.toml` 当前使用 secret-safe custom provider：
  - `model = "gpt-5.4-mini"`
  - `base_url = "https://subapi.elias.ccwu.cc/v1"`
  - `wire_api = "responses"`
  - `env_key = "SUBAPI_ELIAS_API_KEY"`
  - 已确认远端配置不保存 `SUBAPI_ELIAS_API_KEY` 的明文值。
- 非交互 API smoke 通过：`codex exec ... "Return exactly: pong"` 返回 `pong`。
- 工具调用 e2e 通过：`~/Claude/codex-e2e-work/hello.txt` 内容为 `codex-ohos-ok`。
- 远端源码已推送到 GitHub：
  - repo：`git@github.com:chenjh16/codex.git`
  - branch：`ohos`
  - commit：`f2f646d Add HarmonyOS CLI adaptation`
- 第二批 OHOS sandbox/bubblewrap 补丁已构建、签名、验证并推送：
  - commit：`8dbdc6d Disable Linux sandbox probing on HarmonyOS`
  - build status：`rc=0 finished_at=Sat May 23 03:32:46 CST 2026`
  - `codex --version` 输出 `codex-cli 0.0.0`
  - `codex --help` 通过
  - `codex debug models --bundled` 通过
  - TUI 启动捕获中 `bubblewrap` warning 计数为 0，panic 计数为 0
  - 真实 PTY TUI 验证：模型名加载为 `gpt-5.4-mini`，prompt 提交后进入 `Working` 状态，provider 返回 `429 Too Many Requests` 并在 TUI 中显示，`/quit` 可正常退出且 SSH 连接关闭
  - 远端 provider 配置已改回 `env_key = "SUBAPI_ELIAS_API_KEY"`，不再在远端配置里保存 key 值；通过 SSH stdin 临时注入本地环境变量后，`codex exec "Return exactly: env-ok"` 通过并返回 `env-ok`
  - 安全版内存 PTY TUI e2e 通过：
    - prompt 1：`Reply with the lowercase reverse of ABCD only.`，响应包含 `dcba`
    - prompt 2：`Reply with the lowercase reverse of WXYZ only.`，响应包含 `zyxw`
    - `bubblewrap_warning_count=0`
    - `panic_count=0`
    - `error_count=0`
    - `completed_two_rounds=yes`
    - `shutdown_seen=yes`
  - 补充 TERM 覆盖也通过：
    - `TERM=screen-256color`：两轮响应包含 `hgfe`、`lkji`，warning/panic/error 计数均为 0，`shutdown_seen=yes`
    - `TERM=vt100`：两轮响应包含 `hgfe`、`lkji`，warning/panic/error 计数均为 0，`shutdown_seen=yes`
- 本地规则已补充：
  - `AGENTS.md`
  - `AGENTS.cn.md`
  - `expr/codex-harmonyos-adaptation-notes.md`
- 已按用户建议安装到远端用户目录：
  - `/storage/Users/currentUser/.local/bin/codex`
  - wrapper source `~/Claude/codex-ohos/env.sh`，设置 `CODEX_HOME="$HOME/.codex"`，然后 exec 已签名的 `~/Claude/codex-openai/codex-rs/target/release/codex`
  - 已验证 `command -v codex` 指向 `/storage/Users/currentUser/.local/bin/codex`
  - 已验证 `codex --version` 输出 `codex-cli 0.0.0`
  - 已验证 `codex --help` 可正常输出帮助内容
- 最终配置审计发现远端 `~/.codex/config.toml` 曾残留旧 `experimental_bearer_token` 明文配置；已删除该项、启用 `env_key = "SUBAPI_ELIAS_API_KEY"`，并复扫确认 `secret-scan=clean`。因为明文曾短暂存在于远端配置和审计输出中，仍建议轮换该测试 key。
- Agent 能力专项 smoke 已完成一轮：
  - `codex features list` 显示 `multi_agent`、`plugins`、`skill_mcp_dependency_install` 为 stable true；`code_mode` 和 `code_mode_only` 为 under development false。
  - Code Mode 验证必须使用 `--enable code_mode --enable code_mode_only`；仅开 `code_mode` 时模型可退回普通 shell 工具，不能证明 Code Mode 可用。`code_mode_only` 在 OHOS 上返回 `Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.`。
  - 显式 `codex sandbox linux /data/service/hnp/bin/true` 仍会 panic：`codex-linux-sandbox executable not found`。主 CLI/TUI 已不再误报 bubblewrap warning，但 Linux sandbox 子命令仍需要后续做 OHOS graceful unsupported。
  - 多 Agent 深度验收通过：v1 工具面下 `spawn_agent -> wait_agent -> close_agent`、`SendInput`、并发两个子 Agent、`resume_agent` 探针均通过；脚本同时读取隔离 `CODEX_HOME/state_5.sqlite` 的 `thread_spawn_edges` 和 rollout，确认存在 graph/session 持久化证据。
  - MCP 本地能力通过：`codex mcp add/list/remove` 可管理 stdio MCP；`codex mcp-server` 使用 newline JSON-RPC 可完成 `initialize`、`tools/list` 和 `tools/call codex`；本地 Python stdio MCP server 已被 Codex 作为 client 调用 `echo_token` 工具并通过 app-server `mcpServer/resource/read` 读到 `OHOS_LOCAL_MCP_RESOURCE_OK`。Content-Length framing 不是当前 stdio MCP 成功路径，需按实现习惯用 newline JSON-RPC。
  - 真实 MCP 已验证：DeepWiki 站点根路径 `https://mcp.deepwiki.com/` 只是 HTML landing page，正确 endpoint 是 `https://mcp.deepwiki.com/mcp`；隔离 `CODEX_HOME` 下配置该 endpoint 后，Agent 实际调用 `deepwiki/ask_question` 成功返回 `openai/codex` 摘要。`https://developers.openai.com/mcp` 直接访问返回 403，不作为可用 MCP endpoint 保留。
  - 临时真实 MCP 配置已从远端真实 `~/.codex/config.toml` 移除；当前 `codex mcp list` 为 `No MCP servers configured yet`，避免污染日常会话。
  - Plugin/skill 链路通过：`codex plugin list`、`codex plugin marketplace list`、`github@openai-curated` installed/enabled、`debug prompt-input` 暴露 GitHub plugin skills 均可用；repo-local `ohos-smoke-skill` 已在 prompt-input 中出现，并通过模型侧执行返回 `OHOS_LOCAL_SKILL_OK`。connector auth 和真实 connector tool invocation 尚未验收。
  - app-server / remote-control / exec-server 部分可用：`app-server` Unix socket 监听报 `Operation not permitted`，Python 原生 `AF_UNIX bind()` 同样报 EPERM；app-server 和 exec-server 的 `ws://127.0.0.1:*` 不只完成 `101 Switching Protocols`，还已完成 WebSocket text-frame JSON-RPC 请求；`exec-server --listen stdio://` 可干净退出；`remote-control start` 需要 standalone installer layout。
  - cloud / Agent identity 受认证阻塞：`codex login status` 为 `Not logged in`，cloud 子命令要求登录，`exec-server --remote ... --use-agent-identity-auth` 要求 `CODEX_ACCESS_TOKEN`。
  - 当前 SSH 验证环境未发现可用 GUI/browser 命令，Browser Use / Computer Use 工具也未在远端 prompt-input 中暴露；不能宣称浏览器/桌面插件可用。
- 无编译 smoke 脚本固化结果：
  - 本地脚本目录：`/Users/substance/vibe/codex/harmonyos/codex-ohos/scripts`
  - 远端运行目录：`/storage/Users/currentUser/Claude/codex-ohos/scripts`
  - 远端源码仓库镜像：`/storage/Users/currentUser/Claude/codex-openai/scripts/harmonyos`
  - 总入口：`run-no-compile-smoke.zsh`
  - 最新完整通过日志目录：`/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260524-agent-full`
  - 扩展分项通过日志目录：
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260523-2145-multi-agent-v2`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260523-2145-mcp-v2`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260523-2145-plugin-v2`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260523-2130-app-exec`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260524-agent-deep-08c`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260523-agent-deep-09b`
    - `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260524-agent-deep-10`
  - 重要经验：`~/.local/bin/codex` wrapper 会强制 `CODEX_HOME="$HOME/.codex"`；需要隔离 `CODEX_HOME` 的脚本必须直接调用已签名 release binary `~/Claude/codex-openai/codex-rs/target/release/codex`。
  - 多 Agent `send_input` 已实测出现 `collab: SendInput` 并返回 `MULTI_AGENT_SEND_OK CHILD_TOKEN_OK`；并发和 v1 `resume_agent` 探针也已进入 smoke。
  - `codex mcp-server` 的 `tools/call` 已实测通过，返回 `MCP_CODEX_TOOL_OK`；本地 stdio MCP tool/resource 和 app-server MCP resource read 也已进入 smoke。
  - TUI `/agent` picker 已通过 PTY harness 打开，捕获到 `Subagents / Select an agent to watch / Main [default]` 类输出。
  - `resume --last --include-non-interactive` 已在隔离 `CODEX_HOME` 下完成 seed session 恢复并跑出 `vcxz`。
  - Python 直接 `AF_UNIX bind()` 在当前 OHOS 路径也返回 `Operation not permitted`；app-server Unix socket 失败更像平台/权限行为。app-server 和 exec-server `ws://127.0.0.1:*` 均完成 WebSocket `101 Switching Protocols` 握手和最小 JSON-RPC 请求。
  - MCP approval prompt-mode 已通过 app-server `mcpServer/elicitation/request` 验收，`approval_smoke/echo_approval` 进入 `waitingOnApproval` 并投递带 `codex_approval_kind = "mcp_tool_call"` 的 approval request。
  - app-server plugin/app/auth inventory 已验证：未登录 ChatGPT 时 remote plugin catalog / plugin detail / skill detail 明确返回 `chatgpt authentication required`，`app/list` 返回空列表，`account/read` / `getAuthStatus` 返回明确未登录状态。
  - MCP OAuth probe 已走到 `mcpServer/oauth/login` 路径并返回显式结果。
  - remote-control standalone layout probe 使用隔离 `CODEX_HOME/packages/standalone/current/codex` symlink 移除了 `managed standalone Codex install not found` 阻塞；`app-server daemon start` 进入 pid/socket/backend 阶段，当前失败点是 pid start time 读取或 OHOS socket/进程元数据行为。
  - Agent identity probe 已覆盖 `CODEX_ACCESS_TOKEN` 缺失/存在性检测和 `exec-server --remote ... --use-agent-identity-auth` 的显式错误路径，日志未泄露 bearer secret。
  - 跨进程多 Agent 验证通过：先在一个进程 seed parent/child 并 close child，再用新的 `codex exec resume <parent>` 进程调用 `resume_agent <child>`，最终返回 `CROSS_PROCESS_RESUME_OK CROSS_PROCESS_CHILD_RESUMED`，并在 graph/rollout 中留下证据。

## TUI 已观察到的现象

- `ssh -tt` 可启动 TUI。
- `--no-alt-screen` 模式下可捕获到 TUI 渲染、spinner、输入区和模型输出片段。
- 早期 expect 脚本有假阳性：期望 token 出现在启动命令行中，被误认为模型响应。后续自动化不能让期望 marker 直接出现在启动命令行，或必须等待模型输出状态后再匹配。
- 旧构建中手工启动 `~/Claude/codex-ohos/bin/codex` 会显示：

```text
Codex could not find bubblewrap on PATH. Install bubblewrap with your OS package manager.
```

- 新构建启动捕获未再出现该 warning。
- expect/SSH PTY 的 `log_file` 方案不适合传 API key：它会记录 `send` 内容。已删除相关本地 `/tmp/codex-ohos-tui-real-e2e.*` 临时日志。后续若需要含 key 的自动化，使用不落盘、输出前强制脱敏的内存型 PTY harness。
- 清理过遗留的 TUI 自动化孤儿进程，恢复时仍应先检查：

```sh
ssh -p 22222 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost \
  "/usr/bin/zsh -lc 'ps -ef | grep -E \"codex --no-alt-screen|codex-e2e-work\" | grep -v grep || true'"
```

## bubblewrap 警告分析

结论：这不是简单 PATH 漏配，而是 HarmonyOS target 被 Codex 当成普通 Linux sandbox 平台。

证据：

- 远端 `command -v bwrap` 和 `command -v bubblewrap` 为空。
- 源码树有 vendored bubblewrap 和 `codex-linux-sandbox` crate，但当前没有已验证的系统 bwrap 可放入 PATH。
- TUI 启动时调用 `codex_sandboxing::system_bwrap_warning(config.permissions.permission_profile())`。
- `codex-rs/sandboxing/src/lib.rs` 原本只按 `target_os = "linux"` 启用 bwrap warning；HarmonyOS Rust target 同时表现为 `target_os = "linux"` 和 `target_env = "ohos"`。

已采用修复：

- 不在 OHOS 上硬装未验证的 bwrap。
- 将 Linux sandbox/bwrap 逻辑收窄到普通 Linux：`all(target_os = "linux", not(target_env = "ohos"))`。
- OHOS 默认不选择 `LinuxSeccomp`，`system_bwrap_warning()` 返回 `None`。

## 当前远端源码状态

远端 `/storage/Users/currentUser/Claude/codex-openai` 的 `ohos` 分支当前 HEAD 为 `fe2625d5463578a40c3520ce53ed6524612472ce`，已推送到 `origin/ohos` 和 GitHub `refs/heads/ohos`。最新文档/脚本提交为：

- `745788c Document HarmonyOS install and agent gaps`
- `b3d7651 Document HarmonyOS config audit`
- `00d10ff Document HarmonyOS agent capability smoke tests`
- `115cd2b Add HarmonyOS no-compile smoke scripts`
- `fe2625d Expand HarmonyOS agent smoke coverage`

第二批 sandbox/bubblewrap 改动仍对应 `8dbdc6d Disable Linux sandbox probing on HarmonyOS`，内容：

- `arg0`：`codex_linux_sandbox_exe` 只在普通 Linux 下设置。
- `sandboxing/src/lib.rs`：bwrap 模块和 warning 只在普通 Linux 下启用；非普通 Linux含 OHOS时提供：
  - `system_bwrap_warning() -> None`
  - `find_system_bwrap_in_path() -> None`
- `sandboxing/src/manager.rs`：OHOS 不再被 `get_platform_sandbox()` 判为 `LinuxSeccomp`；WSL/bubblewrap 支持检查也只在普通 Linux 下启用。

## 当前构建状态

当前 detached release build 已完成：

```text
detached-build-start Sat May 23 02:00:32 CST 2026
Finished `release` profile [optimized] target(s) in 92m 11s
detached-build-end Sat May 23 03:32:46 CST 2026 rc=0
rc=0 finished_at=Sat May 23 03:32:46 CST 2026
```

检查命令仍可使用：

```sh
ssh -p 22222 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost /usr/bin/zsh <<'REMOTE'
set -eu
LOG=/storage/Users/currentUser/Claude/codex-ohos/logs/build-codex-cli.log
STATUS=/storage/Users/currentUser/Claude/codex-ohos/logs/build-codex-cli.status
printf 'time='; date
printf 'status='; cat "$STATUS" 2>/dev/null || true
printf 'log-size='; wc -c < "$LOG" 2>/dev/null || true
tail -n 180 "$LOG" 2>/dev/null || true
printf '\nprocesses:\n'
ps -ef | grep -E 'cargo build|rustc-sign-wrapper|rustc --crate-name codex|clang|ld.lld' | grep -v grep || true
ls -lh /storage/Users/currentUser/Claude/codex-openai/codex-rs/target/release/codex 2>/dev/null || true
REMOTE
```

## 当前交接状态

当前轮最终审计已完成：

- 远端 `ohos` 分支 HEAD、`origin/ohos` 和 GitHub `refs/heads/ohos` 均指向最新已推送提交 `fe2625d5463578a40c3520ce53ed6524612472ce`。
- build status 为 `rc=0`，最终 release binary 已签名。
- `codex --version` / `--help` / bundled models、非交互 API smoke、工具调用 e2e、TUI 两轮 e2e、多 TERM 覆盖均已通过。
- `/storage/Users/currentUser/.local/bin/codex` 用户安装入口和 PATH 解析通过。
- 无编译 smoke 已固化并完整通过，最新完整日志目录为 `/storage/Users/currentUser/Claude/codex-ohos/logs/smoke/20260524-agent-full`。
- 远端真实 `~/.codex/config.toml` 已清理临时 MCP server，最终 `codex mcp list` 为空，配置扫描未发现明显 secret pattern。
- smoke 过程中遗留的 app-server/exec-server/ws 和旧 resume 测试进程已清理。
- `docs/codex-agent-capability-analysis.md` 已在本地当前项目和远端源码仓库存在。

## 下一步

1. 后续每次构建后优先跑 `~/Claude/codex-ohos/scripts/run-no-compile-smoke.zsh`，再决定是否需要进入长编译。
2. 当前会话中曾因错误 harness 暴露过测试 key；建议轮换该 key 后再长期使用。
3. 下一轮优先做需要真实 ChatGPT 登录或真实服务 token 的正向链路。详细拆解见 `docs/codex-agent-next-capability-workplan.md`：
   - ChatGPT / GitHub connector 正向认证与真实 tool invocation：建立 ChatGPT 登录态、完成 GitHub connector 授权、让模型执行一次只读 GitHub connector tool，并证明不是 shell/`gh`/curl 退路。
   - Cloud task 正向链路：覆盖 task create/register、list/status/log、diff、apply 或等价闭环，使用临时文件验证补丁应用。
   - 真实 Agent Identity JWT：临时注入短期 token，脱敏解码 claims，JWKS 验签，并跑通 exec-server remote 或 cloud task 的 identity auth。
   - remote-control connected 状态：调查 OHOS pid start time / `/proc` 差异，使用 ws 作为优先 transport，完成 start/status/connected/stop 生命周期。
   - GUI / 浏览器插件实机能力：区分 SSH headless 和本机 GUI session，验证浏览器导航/截图/点击和桌面截图/输入。
4. Code Mode 当前在 OHOS 上为 stub；短期策略是显式降级并防止误判为 shell exec 成功。长期策略先评估替代 JS runtime 或外部 bridge，再决定是否投入 rusty_v8/V8 源码构建。
5. `codex sandbox linux` graceful unsupported 属安全/平台入口问题，仍建议后续修复，但优先级低于 Agent 能力闭环。

## TUI 自动化注意事项

- 本机有 `expect`，可以用来驱动 `ssh -tt`。
- 不要让期望 marker 出现在启动命令行里，否则 expect 会提前匹配。
- 推荐先用手工或半自动验证输入区 ready，再做完整自动化。
- `--no-alt-screen` 有利于日志捕获。
- 测试时优先加：

```sh
--no-alt-screen --dangerously-bypass-approvals-and-sandbox -C /storage/Users/currentUser/Claude/codex-e2e-work
```

## 本地需保持同步的文档

- `docs/codex-harmonyos-plan.md`
- `expr/codex-harmonyos-adaptation-notes.md`
- `AGENTS.md`
- `AGENTS.cn.md`
- `TODO.md`
- `docs/codex-agent-capability-analysis.md`
- `scripts/*.zsh`
