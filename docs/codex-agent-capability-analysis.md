# Codex Agent 能力分析与 HarmonyOS 缺口

更新时间：2026-05-23 05:10 CST

## 摘要

当前 HarmonyOS PC 上的 Codex CLI 主链路已经可用：release build 成功、最终二进制已签名、`codex --version` / `codex --help` / bundled models 通过，非交互 `codex exec` 和 TUI 两轮真实模型交互通过，并已安装到 `/storage/Users/currentUser/.local/bin/codex`。

从源码结构看，当前 Codex 已经不只是单 Agent CLI。它包含单会话执行、工具运行时、MCP client/server、插件和 skill 发现、多 Agent 协作、Agent graph 持久化、Agent identity、app-server/remote-control、cloud task 和 Code Mode 等多层能力。HarmonyOS 适配目前验证到 CLI 和 TUI 的核心使用闭环，但 Agent 相关能力仍有明显缺口：Code Mode 在 OHOS 上被 stub，Linux sandbox 被有意禁用，多 Agent、MCP、plugin、app-server、exec-server、cloud task 和 Agent identity 都尚未在 HarmonyOS 端做端到端验收。

结论：当前安装版 Codex 可作为 HarmonyOS PC 上的交互式和非交互式主力 CLI 使用；若要称为完整 Agent runtime，还需要补 Agent 专项验证矩阵，并决定 Code Mode 与 sandbox 的长期策略。

## 当前已验证状态

- 构建：`~/Claude/codex-ohos/logs/build-codex-cli.status` 为 `rc=0 finished_at=Sat May 23 03:32:46 CST 2026`。
- 签名：最终 `~/Claude/codex-openai/codex-rs/target/release/codex` 已完成 HarmonyOS 自签名。
- 安装：`/storage/Users/currentUser/.local/bin/codex` 已创建，wrapper source `~/Claude/codex-ohos/env.sh`，设置 `CODEX_HOME="$HOME/.codex"`，然后 exec 已签名 release binary。
- 基础命令：`command -v codex` 指向 `/storage/Users/currentUser/.local/bin/codex`；`codex --version` 输出 `codex-cli 0.0.0`；`codex --help` 可输出帮助。
- 非交互：`codex exec` 的基础 API smoke 和工具调用 e2e 已通过。
- TUI：`TERM=xterm-256color`、`screen-256color`、`vt100` 均完成两轮 prompt、收到模型响应、`/quit` 正常退出，且 warning/panic/error 计数为 0。
- 安全配置：远端 `~/.codex/config.toml` 使用 `env_key = "SUBAPI_ELIAS_API_KEY"`，不保存 key 明文。

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

能力判断：上游已有完整的多 Agent 控制面和 UI 表示层。HarmonyOS 当前只验证了单主 Agent 的 TUI/exec 闭环，没有跑多 Agent spawn/wait/close 的端到端测试，因此这层属于“源码具备，目标机未验收”。

### 4. Agent graph 和持久化

`codex-rs/agent-graph-store/src/types.rs` 定义 `ThreadSpawnEdgeStatus::{Open, Closed}`，`store.rs` 负责 parent/child thread spawn edge 的持久化。`AgentControl` 也会把 subagent 的 session source、depth、agent path、role、nickname 等信息挂到 thread 上。

能力判断：Codex 已具备父子 Agent 图谱的基本数据模型，支持恢复、关闭和 UI 呈现。但 HarmonyOS 当前没有验证跨进程恢复后 graph 是否正确、子 Agent 是否能 resume、closed 状态是否持久化。

### 5. MCP client/server

Codex 同时具备 MCP client 和 MCP server 能力：

- `codex-rs/rmcp-client`：stdio / streamable HTTP / OAuth / resource 等 client 侧能力。
- `codex-rs/core/src/mcp.rs`、`mcp_tool_call.rs`、`mcp_tool_exposure.rs`：Codex core 中的 MCP tool 调用和暴露。
- `codex-rs/codex-mcp`：Codex app 相关 MCP 连接管理。
- `codex-rs/mcp-server`：把 Codex 作为 MCP server 暴露，工具包括 `codex` 和 `codex-reply`。`codex_tool_config.rs` 说明 server 接收 prompt、model、profile、cwd、approval、sandbox、config、base/developer instructions 等参数；`message_processor.rs` 使用 `ThreadManager` 创建 MCP 来源的 Codex session。

能力判断：MCP 是 Codex Agent 能力的关键扩展面。HarmonyOS 上尚未 smoke `codex mcp`、`codex mcp-server`、外部 stdio MCP server、streamable HTTP MCP、OAuth 或资源读取，因此属于高优先级未验收项。

### 6. Plugin / skill / connector 发现

CLI 有 `plugin` 子命令；tools crate 中也有 discoverable tool、request-plugin-install、connector install completion 等模型可见机制。TUI 里还有 external agent config migration 相关模块，说明 Codex 正在把外部 Agent/插件配置纳入统一发现和迁移体验。

能力判断：上游具备插件和 skill 发现能力，但 HarmonyOS 上没有验证 plugin marketplace、插件安装、skill 加载、connector install request、外部 Agent 配置迁移 UI。考虑到 HarmonyOS 文件系统、SSH 环境和远端网络代理都特殊，这部分不能默认等同于普通 macOS/Linux 可用。

### 7. Agent identity、cloud task、app server 和 remote control

`codex-rs/agent-identity/src/lib.rs` 支持：

- Agent identity JWT 解码和 JWKS 验证。
- 生成/保存 Agent key material。
- task registration。
- 构造 `AgentAssertion` authorization header。

CLI 还包含 `cloud`、`app-server`、`remote-control`、`exec-server` 等实验性/服务型入口。

能力判断：这些能力更接近“Codex 作为分布式 Agent runtime”的形态，但当前 HarmonyOS 验证只覆盖本机 CLI/TUI。Agent identity 依赖 ChatGPT 认证和后端接口，exec-server/app-server 依赖 socket、daemon、远程控制和环境注册；这些都还没有在 HarmonyOS 上验收。

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

3. 多 Agent 端到端未验收。
   影响：源码有 `spawn_agent` / `wait_agent` / `close_agent`，但未验证 HarmonyOS 上子线程创建、并发执行、状态订阅、TUI picker、resume/close graph 持久化。

4. MCP client/server 未验收。
   影响：无法确认 stdio MCP server、Codex MCP server、OAuth、resource、streamable HTTP、MCP tool approval 在 OHOS 上可用。

5. Plugin / skill / connector 流程未验收。
   影响：插件安装、marketplace、skill 加载、外部 Agent config migration、request-plugin-install 可能受 PATH、网络、文件权限和代理影响。

6. App server / remote-control / exec-server 未验收。
   影响：Unix socket、daemon 生命周期、远程控制、exec-server 注册和 ChatGPT auth 约束都可能在 OHOS 上暴露新问题。

7. Cloud task 与 Agent identity 未验收。
   影响：`AgentAssertion`、task registration、JWKS、ChatGPT auth、cloud task apply 等服务型 Agent 能力尚不能宣称可用。

8. 浏览器/桌面/GUI 类插件不适合默认视为可用。
   影响：当前验证环境是 SSH 到 HarmonyOS PC；没有验证本机 GUI 自动化、浏览器控制或桌面插件能力。

9. 自动化 harness 尚未固化。
   影响：当前 TUI 两轮 e2e 是安全版内存 PTY harness 完成，但还没有进入仓库脚本。后续复测需要把“不落盘、不在进程参数暴露 key、输出前脱敏”固化成工具。

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
  - 覆盖 `send_input`、`close_agent`、`resume_agent`。
  - 验证 TUI `/agent` picker 和快捷切换。
  - 验证重启后 graph store 中 open/closed 状态仍正确。
- MCP：
  - `codex mcp-server` 初始化、tools/list、tools/call `codex`。
  - 本地 stdio MCP server 作为外部工具被 Codex 调用。
  - MCP tool approval 和错误展示。
- Plugin / skill：
  - `codex plugin list`、marketplace list、安装一个小插件、删除。
  - 验证 skill 加载、工具搜索、request-plugin-install。

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

多 Agent 最小 smoke 建议在确认 provider 额度稳定后执行，要求固定输出 token，且输出前脱敏。

## 结论

HarmonyOS 版 Codex 当前已经完成“可安装、可启动、可交互、可调用模型、可使用基础工具”的主目标。Agent 相关源码能力很丰富，但 HarmonyOS 侧的验证边界还停在单 Agent CLI/TUI。下一阶段应把多 Agent、MCP、plugin/skill、app-server/exec-server/cloud、Agent identity 和 Code Mode 逐项拆开验收，其中 Code Mode 是唯一已知的编译期功能缺失，其余多为尚未验证或需要环境适配。
