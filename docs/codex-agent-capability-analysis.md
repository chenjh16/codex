# Codex Agent 能力分析与 HarmonyOS 缺口

更新时间：2026-05-24 00:35 CST

## 摘要

当前 HarmonyOS PC 上的 Codex CLI 主链路已经可用：release build 成功、最终二进制已签名、`codex --version` / `codex --help` / bundled models 通过，非交互 `codex exec` 和 TUI 两轮真实模型交互通过，并已安装到 `/storage/Users/currentUser/.local/bin/codex`。

从源码结构看，当前 Codex 已经不只是单 Agent CLI。它包含单会话执行、工具运行时、MCP client/server、插件和 skill 发现、多 Agent 协作、Agent graph 持久化、Agent identity、app-server/remote-control、cloud task 和 Code Mode 等多层能力。HarmonyOS 适配目前已经验证到 CLI 和 TUI 的核心使用闭环，并固化了无编译 Agent 能力 smoke：多 Agent v1 最小链路、`SendInput`、并发子 Agent、`resume_agent`、跨进程 parent/child graph 恢复、SQLite/rollout graph 证据、MCP client/server、`mcp-server tools/call codex`、本地 stdio MCP tool/resource、真实 DeepWiki streamable HTTP MCP、MCP tool approval elicitation、MCP OAuth probe、plugin/skill 发现与 repo-local skill 模型侧调用、app-server/exec-server ws JSON-RPC、remote-control standalone layout probe、Agent identity token probe、TUI `/agent` picker、隔离 `resume --last --include-non-interactive` 都有实测结果。但 Code Mode 在 OHOS 上仍为 stub，Linux sandbox 被有意禁用，真实 ChatGPT 登录态下的 connector/cloud/Agent identity 正向链路和 GUI/浏览器插件仍未完成验收。

结论：当前安装版 Codex 可作为 HarmonyOS PC 上的交互式和非交互式主力 CLI 使用；多 Agent、MCP、plugin/skill、app-server/exec-server 的核心非 GUI 路径已有可用证据。若要称为完整 Agent runtime，还需要补齐真实 ChatGPT/connector/cloud/Agent identity 正向认证能力、GUI 能力，以及 Code Mode 的长期策略。

## 当前已验证状态

- 构建：`~/Claude/codex-ohos/logs/build-codex-cli.status` 为 `rc=0 finished_at=Sat May 23 03:32:46 CST 2026`。
- 签名：最终 `~/Claude/codex-openai/codex-rs/target/release/codex` 已完成 HarmonyOS 自签名。
- 安装：`/storage/Users/currentUser/.local/bin/codex` 已创建，wrapper source `~/Claude/codex-ohos/env.sh`，设置 `CODEX_HOME="$HOME/.codex"`，然后 exec 已签名 release binary。
- 基础命令：`command -v codex` 指向 `/storage/Users/currentUser/.local/bin/codex`；`codex --version` 输出 `codex-cli 0.0.0`；`codex --help` 可输出帮助。
- 非交互：`codex exec` 的基础 API smoke 和工具调用 e2e 已通过。
- TUI：`TERM=xterm-256color`、`screen-256color`、`vt100` 均完成两轮 prompt、收到模型响应、`/quit` 正常退出，且 warning/panic/error 计数为 0。
- 安全配置：最终审计已将远端 `~/.codex/config.toml` 修正为 `env_key = "SUBAPI_ELIAS_API_KEY"`，不保存 key 明文；旧 `experimental_bearer_token` 残留已删除，复扫为 clean。因明文曾短暂存在于远端配置和审计输出中，建议轮换该测试 key。
- Feature flags：`codex features list` 显示 `multi_agent`、`plugins`、`skill_mcp_dependency_install` 为 stable true；`code_mode` 和 `code_mode_only` 为 under development false。
- Code Mode：`--enable code_mode --enable code_mode_only` 返回 OHOS rusty_v8 prebuilt 缺失提示，确认当前为 stub；仅启用 `code_mode` 时模型可退回普通 shell 工具，不能作为 Code Mode 可用证据。
- Linux sandbox：显式 `codex sandbox linux /data/service/hnp/bin/true` 仍 panic 为 `codex-linux-sandbox executable not found`。主 CLI/TUI 已正确降级，但该子命令需要后续修成 graceful unsupported。
- 多 Agent：v1 工具面下最小 `spawn_agent -> wait_agent -> close_agent`、`SendInput`、并发两个子 Agent、`resume_agent` 均通过；隔离 `CODEX_HOME/state_5.sqlite` 的 `thread_spawn_edges` 与 rollout 中均有 graph/session 证据。最新 `10-multi-agent-cross-process-smoke.zsh` 还验证了新进程 `codex exec resume <parent>` 后调用 `resume_agent <child>`，最终返回 `CROSS_PROCESS_RESUME_OK CROSS_PROCESS_CHILD_RESUMED`。
- MCP：`codex mcp add/list/remove`、`codex mcp-server` newline JSON-RPC `initialize` / `tools/list` 通过；`mcp-server tools/call codex` 返回 `MCP_CODEX_TOOL_OK`；本地 Python stdio MCP server 的 `echo_token` tool 被 Codex 调用成功，app-server `mcpServer/resource/read` 读到 `OHOS_LOCAL_MCP_RESOURCE_OK`；真实 DeepWiki MCP endpoint `https://mcp.deepwiki.com/mcp` 通过，Agent 实际调用 `deepwiki/ask_question` 返回 `openai/codex` 摘要；MCP approval prompt-mode 会进入 `waitingOnApproval` 并投递 app-server `mcpServer/elicitation/request`，其中 `_meta.codex_approval_kind = "mcp_tool_call"`；MCP OAuth probe 已走到 `mcpServer/oauth/login` 并返回显式结果。`https://developers.openai.com/mcp` 直接访问返回 403，不作为可用 endpoint。
- Plugin/skill：plugin list、marketplace list、GitHub plugin 安装和 prompt-input skills 暴露通过；repo-local `ohos-smoke-skill` 已在 prompt-input 中出现，并通过模型侧执行返回 `OHOS_LOCAL_SKILL_OK`；app-server plugin/app/auth inventory 已验证未登录 ChatGPT 时 remote plugin catalog/detail/skill detail 明确要求 `chatgpt authentication required`，`app/list` 返回空列表。connector auth 和真实 connector tool invocation 仍需真实 ChatGPT/GitHub connector 登录态。
- 服务型能力：Python 直接 `AF_UNIX bind()` 也报 `Operation not permitted`，app-server Unix socket 报同类错误；app-server/exec-server `ws://127.0.0.1:*` 均可完成 WebSocket `101 Switching Protocols` 握手和最小 JSON-RPC 请求；exec-server stdio 可启动；remote-control standalone layout probe 已用隔离 `CODEX_HOME/packages/standalone/current/codex` 移除 managed-install blocker，并进入 pid/socket/backend 阶段，当前失败点是 pid start time 读取或 OHOS 进程/套接字元数据行为；cloud/Agent identity 正向仍受登录或真实 token 阻塞，负向 token path 已有明确错误和无泄漏证据。
- TUI/resume：TUI `/agent` picker 已捕获 `Subagents` / `Select an agent to watch`；隔离 `CODEX_HOME` 下 `resume --last --include-non-interactive` 可恢复非交互 seed 并完成后续 prompt。
- GUI：当前 SSH 环境未发现可用浏览器命令，Browser Use / Computer Use 未在远端 prompt-input 中暴露。
- 自动化：无编译 smoke 已固化到 `~/Claude/codex-ohos/scripts/run-no-compile-smoke.zsh`。扩展分项 `20260524-agent-deep-08c`、`20260523-agent-deep-09b`、`20260524-agent-deep-10` 均为 `failures=0`；整套总回归 `20260524-agent-full` 已通过，输出 `no-compile-smoke failures=0`。
- 配置卫生：真实 DeepWiki/OpenAI MCP 临时配置已从远端真实 `~/.codex/config.toml` 清理，当前真实 `codex mcp list` 为无 MCP server。

## 能力分层

### 1. 单 Agent CLI 执行闭环

Codex CLI 的入口在 `codex-rs/cli/src/main.rs`。当前命令面包括：

- 默认 TUI 交互入口。
- `exec`：非交互执行。
- `review`：非交互代码审查。
- `login` / `logout`：认证。
- `apply`：应用 Codex 生成的 diff。
- `resume` / `fork`：恢复或分叉历史 session。
- `mcp` / `mcp-server`：管理外部 MCP 或作为 MCP server 暴露 Codex。
- `plugin`：管理插件。
- `app-server` / `remote-control`：实验性 app server 和远程控制。
- `cloud`：Codex Cloud task。
- `exec-server`：独立 exec-server service。
- `features`：feature flag 检查与启停。

这层在 HarmonyOS 上的基础可用性较好，因为 `--version`、`--help`、`exec`、TUI 已通过。但 `review`、`apply`、`resume`、`fork`、`cloud`、`exec-server` 等子命令尚未逐项验收。

### 2. 工具运行时与工具暴露

`codex-rs/tools/src/lib.rs` 显示当前工具层已经抽成共享 crate，覆盖：

- Responses API tool spec 和 namespace tool。
- MCP / dynamic tool 到 Responses API 的转换。
- Code Mode tool augmentation。
- plugin install request / tool discovery。
- image detail normalization。
- tool executor、tool payload、tool output 等共享契约。

这说明 Codex 的 Agent 能力高度依赖工具运行时，而不是只靠模型自然语言。HarmonyOS 上已通过普通 shell/file 工具调用 e2e，但尚未完整覆盖 MCP tool、dynamic tool、plugin install request、tool search 和 Code Mode nested tool。

### 3. 多 Agent 协作工具

源码中有两套多 Agent 工具形态：

- v1 namespace：`multi_agent_v1.spawn_agent`、`send_input`、`resume_agent`、`wait_agent`、`close_agent`。
- v2 function tools：`spawn_agent`、`send_message`、`followup_task`、`wait_agent`、`list_agents`、`close_agent`。

关键证据：

- `codex-rs/core/src/tools/handlers/multi_agents_spec.rs` 定义工具 schema、描述、输出 schema 和 usage guidance。
- `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` 会构建子 Agent config，应用角色、模型、reasoning、service tier、runtime override，并调用 `agent_control.spawn_agent_with_metadata`。
- `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` 订阅子 Agent 状态，等待 final status 或 timeout。
- `codex-rs/core/src/agent/control.rs` 管理 spawn、fork、session source、shell snapshot、exec policy、AgentRegistry 和 thread graph 相关状态。
- `codex-rs/tui/src/multi_agents.rs` 负责 TUI 里的多 Agent 历史行、`/agent` picker、状态点、快捷切换等展示逻辑。
- `codex-rs/app-server-protocol/src/protocol/event_mapping.rs` 和 `thread_history.rs` 将 spawn/send/wait/close/resume 事件映射为 UI thread item。
- `codex-rs/analytics/src/reducer.rs` 对 `spawn_agent`、`send_input`、`resume_agent`、`wait_agent`、`close_agent` 做事件归因。

能力判断：上游已有完整的多 Agent 控制面和 UI 表示层。HarmonyOS 当前已通过 v1 `spawn_agent -> wait_agent -> close_agent`、`SendInput`、并发多个子 Agent、`resume_agent`、跨进程 parent resume 后恢复 closed child、TUI `/agent` picker。仍需进一步覆盖的是 TUI picker 快捷切换和更复杂的多层子 Agent 树。

### 4. Agent graph 和持久化

`codex-rs/agent-graph-store/src/types.rs` 定义 `ThreadSpawnEdgeStatus::{Open, Closed}`，`store.rs` 负责 parent/child thread spawn edge 的持久化。`AgentControl` 也会把 subagent 的 session source、depth、agent path、role、nickname 等信息挂到 thread 上。

能力判断：Codex 已具备父子 Agent 图谱的基本数据模型，支持恢复、关闭和 UI 呈现。HarmonyOS 已通过脚本读取 `state_5.sqlite` 中的 `thread_spawn_edges` 和 rollout 事件，确认多 Agent smoke 产生了 graph/session 持久化证据；并已通过新进程 resume 父会话后恢复 closed child。更深的验收仍应覆盖多层子树和 TUI 侧浏览/切换。

### 5. MCP client/server

Codex 同时具备 MCP client 和 MCP server 能力：

- `codex-rs/rmcp-client`：stdio / streamable HTTP / OAuth / resource 等 client 侧能力。
- `codex-rs/core/src/mcp.rs`、`mcp_tool_call.rs`、`mcp_tool_exposure.rs`：Codex core 中的 MCP tool 调用和暴露。
- `codex-rs/codex-mcp`：Codex app 相关 MCP 连接管理。
- `codex-rs/mcp-server`：把 Codex 作为 MCP server 暴露，工具包括 `codex` 和 `codex-reply`。`codex_tool_config.rs` 说明 server 接收 prompt、model、profile、cwd、approval、sandbox、config、base/developer instructions 等参数；`message_processor.rs` 使用 `ThreadManager` 创建 MCP 来源的 Codex session。

能力判断：MCP 是 Codex Agent 能力的关键扩展面。HarmonyOS 当前已通过 `codex mcp add/list/remove`、Codex MCP server newline JSON-RPC `initialize` / `tools/list`、`tools/call codex`、本地 stdio MCP tool 调用、app-server MCP resource read、真实 DeepWiki streamable HTTP MCP 的 `deepwiki/ask_question` 调用、MCP approval elicitation、MCP OAuth probe。当前源码 stdio 路径是 newline JSON，不是 Content-Length framing。仍未覆盖的是 authenticated streamable HTTP 的真实登录态、approval UI 展示和错误 UI。

### 6. Plugin / skill / connector 发现

CLI 有 `plugin` 子命令；tools crate 中也有 discoverable tool、request-plugin-install、connector install completion 等模型可见机制。TUI 里还有 external agent config migration 相关模块，说明 Codex 正在把外部 Agent/插件配置纳入统一发现和迁移体验。

能力判断：上游具备插件和 skill 发现能力。HarmonyOS 当前已验证 plugin list、marketplace list、GitHub plugin 安装、prompt-input 中暴露 GitHub plugin skills、repo-local skill discovery，以及模型侧使用 repo-local skill 返回固定 token。考虑到 HarmonyOS 文件系统、SSH 环境和远端网络代理都特殊，connector auth、真实 connector tool invocation、request-plugin-install 和外部 Agent 配置迁移 UI 仍不能默认等同于普通 macOS/Linux 可用。

### 7. Agent identity、cloud task、app server 和 remote control

`codex-rs/agent-identity/src/lib.rs` 支持：

- Agent identity JWT 解码和 JWKS 验证。
- 生成/保存 Agent key material。
- task registration。
- 构造 `AgentAssertion` authorization header。

CLI 还包含 `cloud`、`app-server`、`remote-control`、`exec-server` 等实验性/服务型入口。

能力判断：这些能力更接近“Codex 作为分布式 Agent runtime”的形态。HarmonyOS 当前验证结果是：Python 原生 `AF_UNIX bind()` 和 app-server Unix socket 都报 `Operation not permitted`；app-server/exec-server ws 模式都完成了 WebSocket `101 Switching Protocols` 握手和最小 JSON-RPC 请求；exec-server stdio 可启动；remote-control standalone layout 可通过隔离 symlink 构造并越过 managed-install 检查，但 daemon start 当前停在 pid/socket/backend 细节；cloud task 和 Agent identity 正向受 ChatGPT login 或真实 `CODEX_ACCESS_TOKEN` 阻塞。也就是说，服务型入口不是全不可用，后续 runtime 适配应优先走 ws 模式，再处理认证和远程注册链路。

### 8. Code Mode

Code Mode 是当前 HarmonyOS 最大的明确缺口。适配中因为 `rusty_v8` 没有 `aarch64-unknown-linux-ohos` 预编译包，已将 `v8` 和 `deno_core_icudata` 移出 OHOS 依赖，并启用 stub。

`codex-rs/code-mode/src/service_ohos_stub.rs` 当前会返回：

```text
Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.
```

Code Mode 在非 OHOS 构建中承载 JS orchestration、nested tool call、`exec` / `wait` 等组合式能力。OHOS stub 不会影响普通 TUI 和 `codex exec` 的主路径，但会影响复杂 Agent 编排、JS 数据处理、跨工具聚合和部分高级模型工具使用体验。

## HarmonyOS 当前缺失或弱验证项

1. Code Mode 不可用。
   影响：无法使用基于 V8/JS runtime 的代码单元、nested tool orchestration 和相关高级工具组合。

2. Linux sandbox 不可用且已主动降级。
   影响：OHOS 不再误探测 bubblewrap，也不再默认进入 LinuxSeccomp。安全边界依赖 Codex approval、工作目录和用户操作约束，不能等同普通 Linux sandbox。

3. 多 Agent 已覆盖 v1 核心链路、并发、`resume_agent`、跨进程恢复和 graph 证据。
   影响：`spawn_agent` / `wait_agent` / `close_agent` / `SendInput` / 并发 / `resume_agent` / TUI picker 已通过；`codex exec resume <parent>` 后恢复 closed child 也已通过。仍需验证多层子 Agent 树和 TUI picker 快捷切换。

4. MCP client/server 已完成基础、tool、resource、真实 DeepWiki、approval elicitation 和 OAuth probe。
   影响：stdio add/list/remove、Codex MCP server newline JSON-RPC、`tools/call codex`、本地 stdio MCP tool/resource、真实 DeepWiki streamable HTTP MCP、app-server `mcpServer/elicitation/request` 均已通过；authenticated streamable HTTP 正向登录态、approval UI 展示和错误 UI 仍未覆盖。

5. Plugin / skill 基础和 repo-local skill 模型侧调用可用，connector 正向调用仍需真实登录态。
   影响：插件 marketplace、安装、skill 暴露、repo-local skill 注入、app-server plugin/app/auth inventory 已通过；未登录 ChatGPT 时 remote plugin catalog 明确要求认证。外部 connector auth/tool invocation、Agent config migration、request-plugin-install 可能受 PATH、网络、文件权限、代理和 ChatGPT connector 授权影响。

6. App server / exec-server ws 基础协议可用，remote-control 已越过 standalone layout 阻塞但未 connected。
   影响：ws handshake、最小 JSON-RPC 和 exec-server stdio 已有证据；Unix socket 在 Python 原生 bind 层即 EPERM；隔离 standalone layout 已能让 daemon start 进入 pid/socket/backend 阶段，后续要调查 OHOS pid start time、Unix socket 和 remote-control connected 状态。

7. Cloud task 与 Agent identity 正向未验收。
   影响：`AgentAssertion`、task registration、JWKS、ChatGPT auth、cloud task apply 等服务型 Agent 能力尚不能宣称可用；缺失/存在性 token probe 和无泄漏检查已进入 smoke。

8. 浏览器/桌面/GUI 类插件不适合默认视为可用。
   影响：当前验证环境是 SSH 到 HarmonyOS PC；没有验证本机 GUI 自动化、浏览器控制或桌面插件能力。

9. 自动化 harness 已覆盖本轮 Agent 优先项，但正向认证链路仍需凭据。
   影响：当前无编译 smoke 已进入 `~/Claude/codex-ohos/scripts`，并补齐多 Agent v1 resume/concurrency/cross-process、MCP stdio resource/tool/approval/OAuth probe、skill invocation、ws JSON-RPC、remote-control layout 和 Agent identity token probe；仍需补真实 ChatGPT login、GitHub connector 正向调用、cloud task 正向和真实 Agent identity JWT。

## 建议路线图

### P0：安装和基础回归固化

- 保留 `/storage/Users/currentUser/.local/bin/codex` 作为用户 PATH 安装入口。
- 在远端保留 secret-safe `~/.codex/config.toml`，只写 `env_key`，不写 key 值。
- 固化基础 smoke：
  - `codex --version`
  - `codex --help`
  - `codex debug models --bundled`
  - `codex exec` 短回答
  - 工具调用创建文件
  - TUI 两轮 prompt，覆盖 3 个 TERM
- 将安全版内存 PTY harness 脚本化，要求默认脱敏且不写 key。

### P1：Agent 专项验证矩阵

- 多 Agent：
  - 让主 Agent spawn 一个子 Agent，要求子 Agent 返回固定 token。
  - 覆盖 `wait_agent` timeout 和 completed 两种结果。
  - 已覆盖 `send_input`、`close_agent`、`resume_agent` 探针和并发子 Agent。
  - 已验证 TUI `/agent` picker，仍需补快捷切换。
  - 已读取 SQLite/rollout graph 证据，并已验证跨进程 parent resume 后恢复 closed child。
- MCP：
  - `codex mcp-server` tools/call `codex`。
  - 本地 stdio MCP server 作为外部工具被 Codex 调用，并通过 app-server 读取 resource。
  - DeepWiki 之外再覆盖一个 authenticated streamable HTTP MCP。
  - MCP OAuth 正向登录、resource/list 和 resource/read。
  - MCP tool approval UI 和错误展示。
- Plugin / skill：
  - 在真实 ChatGPT/GitHub connector 登录态下验证 connector auth 和真实 connector tool invocation。
  - 验证 skill 加载、工具搜索、request-plugin-install。
  - 验证 external agent config migration UI。

### P1/P2：Code Mode 决策

可选路径：

- 保持 OHOS stub，但在文档、help 或 feature discovery 中明确展示不可用，避免模型误用。
- 尝试从源码构建 V8/rusty_v8，评估构建时长、签名、ICU、链接器和产物体积。
- 设计轻量替代 runtime，只支持安全子集或外部 Node/DevNode，但需要解决 `--jitless`、权限和 sandbox 问题。

### P2：sandbox 和服务型能力

- 梳理 OHOS 可用的进程隔离、权限模型和文件系统限制，明确是否能提供等价于 LinuxSeccomp/bwrap 的 sandbox profile。
- 验证 app-server daemon、remote-control、exec-server、cloud task、Agent identity。
- 给 SSH/hdc tunnel 掉线、端口恢复、长任务 detached 运行补运维脚本。

## 建议验收命令

安装状态：

```sh
ssh -p 22222 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost \
  "/usr/bin/zsh -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; command -v codex; codex --version; codex --help >/dev/null && echo help-ok'"
```

secret-safe provider：

```sh
ssh -p 22222 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost \
  "/usr/bin/zsh -lc 'grep -n \"env_key\\|base_url\\|experimental_bearer_token\" \$HOME/.codex/config.toml; ! grep -Eq \"sk-[A-Za-z0-9]\" \$HOME/.codex/config.toml'"
```

Agent 专项 smoke 已固化为无编译脚本，后续复测优先使用：

```sh
ssh -p 22222 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost \
  "/usr/bin/zsh -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; ~/Claude/codex-ohos/scripts/run-no-compile-smoke.zsh'"
```

复测要求继续保持 secret-safe：API key 只通过临时环境或 stdin 传入，输出前脱敏，不写入远端配置、日志或进程参数。

## 结论

HarmonyOS 版 Codex 当前已经完成“可安装、可启动、可交互、可调用模型、可使用基础工具”的主目标，并已把 Agent 专项验收推进到多 Agent v1 resume/concurrency/cross-process、MCP stdio tool/resource/DeepWiki/approval/OAuth probe、plugin/skill 模型侧调用、app-server/exec-server ws JSON-RPC、remote-control layout、Agent identity token probe、TUI `/agent` picker 和跨进程 `resume --last --include-non-interactive`。下一阶段应继续补齐需要真实认证的 Agent runtime 正向链路：ChatGPT login、GitHub connector tool invocation、cloud task、真实 Agent identity JWT 和 remote-control connected 状态。Code Mode 是当前唯一明确的编译期功能缺失；sandbox 则应在 Agent 关键链路稳定后再做长期隔离策略。
