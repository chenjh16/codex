# HarmonyOS Codex Agent 后续能力补齐工作计划

更新时间：2026-05-24

本文细化当前剩余的 Agent 优先目标。排序原则是先完成真实 Agent 能力，再处理安全/sandbox；先补齐真实认证和服务链路，再考虑 Code Mode 的重型编译路线。每一项都按“要做什么、为什么要做、怎么验收、可能需要的改动、失败时如何判断”组织，方便后续直接拆脚本或拆代码任务。

## 1. ChatGPT / GitHub connector 正向认证与 tool invocation

### 当前状态

已验证 plugin/skill 基础链路：`codex plugin list`、marketplace list、GitHub plugin 安装状态、`debug prompt-input` 暴露 GitHub plugin skills、repo-local skill 模型侧调用均可用。app-server plugin/app/auth inventory 也已验证：未登录 ChatGPT 时 remote plugin catalog/detail/skill detail 会明确返回 `chatgpt authentication required`，`app/list` 为空。

尚未完成的是“正向认证后，模型真的调用 GitHub connector 工具”。这和本地 `gh` CLI、普通 shell、repo-local skill 都不是一回事。

### 要做什么

1. 在 HarmonyOS 远端建立真实 ChatGPT 登录态。
2. 让 Codex 能读取 authenticated account/auth status。
3. 验证 remote plugin catalog、plugin detail、skill detail 在登录后能返回 GitHub connector 相关内容。
4. 完成 GitHub connector 授权，确认授权对象是 `chenjh16` 可访问的 GitHub 账号或组织范围。
5. 让模型在一次真实任务中调用 GitHub connector tool，而不是退回 shell、`gh`、curl 或 repo-local skill。
6. 记录 tool-call 证据、返回结果、错误处理和 approval 行为。

### 具体验收动作

建议按从低风险到高风险执行：

1. 认证状态探测：
   - `codex login status`
   - app-server `account/read`
   - app-server `getAuthStatus`
   - remote plugin catalog/list/detail/skill detail
2. GitHub connector 授权探测：
   - plugin marketplace 中确认 GitHub connector 可见。
   - 触发 connector auth/install 流程。
   - 若需要浏览器 OAuth，优先使用可复制 URL 或 device-code 流程；不要把 token 写入日志。
3. 真实 tool invocation：
   - 让模型执行一个只读 GitHub 操作，例如读取 `chenjh16/codex` 的默认分支、列出最近 issues/PR、查询当前 `ohos` 分支最近 commit。
   - 禁用或约束 shell 退路，要求 evidence 中出现 connector/tool 名称。
   - 用 `git ls-remote` 或 GitHub 网页/CLI 只做交叉核验，不能把交叉核验当作 connector 成功。
4. approval 验证：
   - 对一个需要确认的 GitHub 操作触发 approval，例如创建草稿 issue 或读取更高权限资源前的授权提示。
   - 只做无副作用或可立即清理的动作。

### 成功标准

- 登录态 API 不再返回 `chatgpt authentication required`。
- GitHub connector skill/detail 可见，授权状态明确。
- 模型响应中有真实 connector tool call 证据，且结果能被独立核验。
- 不依赖本机 `gh`、shell、curl 或 repo-local fake skill。
- 日志不包含 OAuth code、access token、refresh token、session cookie 或 bearer token。

### 可能需要的代码或环境改动

- 如果 HarmonyOS 无法打开浏览器 OAuth，需要支持 device-code、copy URL、SSH-friendly callback 或手动粘贴 auth code。
- 如果 app-server 认证依赖 Unix socket，需要优先改为 ws loopback 路径，绕过当前 OHOS `AF_UNIX bind()` EPERM。
- 如果 connector tool discovery 依赖 PATH 或 standalone layout，需要补 wrapper 中的 `CODEX_HOME`、`PATH`、plugin cache 路径和 app-server 启动布局。

### 失败时如何判断

- `chatgpt authentication required`：ChatGPT 登录态未建立或未传到 app-server。
- GitHub plugin visible 但 tool call 不出现：模型侧 tool exposure 或 connector skill injection 未生效。
- 模型用 shell/`gh` 完成：只能说明普通工具可用，不能算 connector invocation。
- OAuth 成功但 GitHub API 403：GitHub connector 授权 scope 或账号权限不足。

## 2. Cloud task 正向链路

### 当前状态

已验证 cloud 子命令在未登录时会明确要求 ChatGPT 登录。尚未验证 task registration、list、status、diff、apply 等正向服务链路。

### 要做什么

1. 在真实 ChatGPT 登录态下运行 cloud task 基础命令。
2. 注册一个最小、低风险、可清理的 cloud task。
3. 覆盖 task list、task status、task output/log、task diff、task apply 或等价流程。
4. 验证任务执行身份、工作区绑定、分支/补丁应用和错误恢复。

### 具体验收动作

1. 命令发现：
   - `codex cloud --help`
   - 子命令 help：list/status/diff/apply/exec/register 等以实际 CLI 为准。
2. 只读任务：
   - 在临时目录或测试 repo 中创建任务，要求只输出环境信息或读取一个文件。
   - 确认 task id、状态流转和结束码。
3. 受控写入任务：
   - 让 cloud task 修改一个临时文件，例如 `cloud-smoke.txt`。
   - 获取 diff，确认 patch 内容只触及临时文件。
   - 应用或拒绝 patch，验证本地工作区结果。
4. 失败路径：
   - 未登录、无权限、网络断开、任务超时都应有明确错误。

### 成功标准

- 能创建或注册 cloud task，并拿到稳定 task id。
- 能查询 list/status/log 或等价状态。
- 能获取 task diff，并在本地安全应用到临时文件。
- 认证、网络、权限错误不会被吞掉或误报为成功。
- secret 不进入任务 prompt、日志、进程参数或远端配置文件。

### 可能需要的代码或环境改动

- ChatGPT auth/token 注入路径。
- 代理设置：远端可能需要 `http://127.0.0.1:7890`。
- task apply 若依赖 git/path assumptions，需要适配 HarmonyOS 路径、权限和 shell。
- 若 cloud task 依赖 Agent identity，需要先完成第 3 项。

### 失败时如何判断

- 仍提示 login required：认证未接通。
- task created 但 status 不更新：长连接、轮询或网络代理问题。
- diff/apply 失败：本地 git/worktree/path 权限问题。
- task 运行但身份错误：Agent identity 或 account binding 未正确传入。

## 3. 真实 Agent Identity JWT

### 当前状态

已验证 `CODEX_ACCESS_TOKEN` 缺失/存在性路径和 `exec-server --remote ... --use-agent-identity-auth` 的显式错误；日志未泄露 bearer secret。尚未使用真实 Agent Identity JWT 完成正向注册、JWKS 验证或远程服务认证。

### 要做什么

1. 获取真实、短期、可撤销的 Agent Identity token。
2. 只在当前 shell/session 中临时注入，不写远端配置。
3. 解码 JWT header/claims 做最小审计，禁止输出完整 token。
4. 通过 JWKS 验证签名和 issuer/audience/expiry。
5. 使用 token 跑一次真实 Agent identity auth 链路，例如 exec-server remote 或 cloud task 注册。

### 具体验收动作

1. secret-safe 注入：
   - 从本机 stdin 或临时环境变量传入。
   - 远端命令不要把 token 放进进程参数。
2. JWT 结构审计：
   - 打印 `iss`、`aud`、`exp`、`sub` 的脱敏摘要。
   - 检查 `exp` 未过期，`aud` 与 Codex 服务匹配。
3. JWKS 验证：
   - 从官方 JWKS endpoint 获取 key。
   - 按 `kid` 验签。
   - 失败时区分 kid 不匹配、签名失败、issuer/audience 不匹配、过期。
4. 正向调用：
   - `exec-server --remote ... --use-agent-identity-auth` 或 cloud task 注册。
   - 验证服务端接受 token，并返回非 auth 错误或成功响应。

### 成功标准

- token 只临时存在于环境/stdin，文档和日志里只有脱敏 claim。
- JWT header/claim/JWKS 验证通过。
- 远程 Agent 服务接受 identity auth。
- 失败路径能明确区分 token 过期、scope 不足、audience 不匹配和网络错误。

### 可能需要的代码或环境改动

- 增加 secret-safe JWT probe 脚本，输出前统一脱敏。
- 如果 OHOS TLS/JWKS fetch 有问题，需要确认根证书、代理和 DNS。
- 如果 exec-server remote 只支持特定 auth source，需要补配置或 CLI 参数。

### 失败时如何判断

- `CODEX_ACCESS_TOKEN required`：token 没传到目标进程。
- JWT 解码成功但 JWKS 失败：issuer/kid/JWKS endpoint 不匹配。
- JWKS 通过但服务拒绝：audience/scope/account binding 不匹配。
- 服务连接失败：不是身份问题，转查网络、代理或 app-server/exec-server。

## 4. remote-control connected 状态

### 当前状态

已验证 isolated standalone layout 可以通过 `CODEX_HOME/packages/standalone/current/codex` symlink 越过 `managed standalone Codex install not found`。daemon start 已进入 pid/socket/backend 阶段，当前失败点是读取 pid start time 或 OHOS socket/进程元数据行为。app-server/exec-server 的 ws JSON-RPC 已可用，Unix socket/`AF_UNIX bind()` 在 OHOS 上报 EPERM。

### 要做什么

1. 明确 remote-control 需要的 standalone layout、pid file、socket/backend 文件和进程元数据。
2. 找出 pid start time 读取失败的实际系统调用或 `/proc` 文件差异。
3. 让 remote-control daemon 在 OHOS 上进入 started/connected 状态。
4. 通过 ws loopback 完成一次 app-server/remote-control 协议交互。
5. 验证 stop/restart/cleanup 生命周期。

### 具体验收动作

1. 进程元数据调查：
   - 对比 Linux 期望读取的 `/proc/<pid>/stat`、start time、cmdline、exe。
   - 在 OHOS 上用 shell/Rust/Python 小探针验证哪些字段可读。
2. socket/backend 调查：
   - 继续保留 ws 路线作为优先路径。
   - Unix socket 只记录 unsupported，不作为短期 blocker。
3. daemon 生命周期：
   - `codex remote-control start --json`
   - `codex remote-control status --json`
   - `codex remote-control stop --json`
   - 重复 start/stop，确认不会留下孤儿进程。
4. connected 验证：
   - 通过 app-server 或 remote-control endpoint 发最小 JSON-RPC。
   - 确认返回 connected/ready，而不是仅有 pid。

### 成功标准

- `remote-control start --json` 返回成功或 clearly connected 状态。
- `status --json` 能看到 daemon、backend、connection 信息。
- `stop --json` 能清理进程、pid、socket/ws 监听。
- 重复运行不会因旧 pid 或旧端口失败。
- 不依赖 Unix socket；ws 模式可作为 OHOS 主路径。

### 可能需要的代码或环境改动

- 对 OHOS 增加 pid start time fallback，例如无法读取时改用 pid file + liveness check + executable path 校验。
- remote-control/app-server 默认 transport 在 OHOS 上偏向 ws，而不是 Unix socket。
- standalone layout 可由安装 wrapper 正式创建，不再依赖测试 symlink。
- status/stop 需要容忍 OHOS `/proc` 元数据缺口。

### 失败时如何判断

- managed standalone 错误：安装布局仍未满足。
- pid start time 错误：进程元数据适配问题。
- EPERM on socket：Unix socket/权限问题，优先切 ws。
- start 成功但未 connected：backend handshake、auth 或 endpoint 注册问题。

## 5. GUI / 浏览器插件实机能力

### 当前状态

当前验证环境是 SSH 到 HarmonyOS PC。远端未发现可用 browser/desktop 自动化命令，Browser Use / Computer Use 工具也未在远端 prompt-input 中暴露。因此不能宣称 GUI 或浏览器插件可用。

### 要做什么

1. 确认 HarmonyOS PC 是否存在可自动化的本机 GUI session。
2. 确认浏览器命令、窗口系统、权限提示、输入法和截图能力。
3. 验证 Codex 插件/skill 是否能把浏览器或桌面工具暴露给模型。
4. 完成至少一个真实浏览器任务和一个桌面/截图任务。

### 具体验收动作

1. 环境发现：
   - 检查 DISPLAY/Wayland/ArkUI 相关环境变量。
   - 查找系统浏览器可执行文件和启动方式。
   - 检查截图、剪贴板、输入模拟能力。
2. 插件发现：
   - `debug prompt-input` 中确认 Browser Use / Computer Use 或等价 tool 是否出现。
   - plugin/app inventory 中确认 GUI plugin 是否 installed/enabled。
3. 浏览器任务：
   - 打开一个本地或公网低风险页面。
   - 获取标题/截图。
   - 执行点击或输入。
4. 桌面任务：
   - 列窗口、截图、点击或键盘输入。
   - 验证权限弹窗和失败信息。

### 成功标准

- 模型可见 GUI/browser tool。
- 至少一次真实浏览器导航、截图或 DOM/标题读取成功。
- 至少一次真实桌面截图、窗口枚举或输入动作成功。
- SSH/headless 环境失败时能明确说明是无 GUI session，而非 Codex 能力缺失。

### 可能需要的代码或环境改动

- 需要 hdc/本机 GUI bridge，SSH 可能不足。
- 需要安装或适配浏览器驱动。
- 需要为 HarmonyOS 桌面权限、截图、输入注入增加 backend。
- 插件可能需要区分远端 headless 和本机 desktop runtime。

### 失败时如何判断

- tool 不在 prompt-input：插件没有暴露给模型。
- tool 可见但无法连接浏览器：浏览器 backend 或端口问题。
- 浏览器可启动但无法截图/点击：GUI 权限或窗口系统问题。
- SSH 下不可用但本机可用：需要本机 session harness，不是功能缺失。

## 6. Code Mode 长期策略

### 当前状态

OHOS 当前使用 Code Mode stub。`--enable code_mode --enable code_mode_only` 会返回：

```text
Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.
```

仅启用 `--enable code_mode` 时，模型可能退回普通 shell 工具并成功执行 JS/Node 命令；这不能算 Code Mode 可用。Code Mode 的影响范围包括 V8/JS runtime、代码单元执行、nested tool orchestration 和高级工具组合。

### 要做什么

先定策略，再进入长编译。建议拆成短期、中期、长期三层。

### 短期策略：明确降级

1. 保留 OHOS stub。
2. 保证 `code_mode_only` 总是明确失败，不会退回 shell。
3. 在 help、feature discovery、文档和 smoke 中明确标注不可用。
4. 防止模型把普通 shell/Node 执行误判为 Code Mode 成功。

成功标准：

- smoke 中固定检查 stub 文案。
- Code Mode 不可用时错误清晰、可行动。
- 不影响普通 `codex exec`、TUI、多 Agent、MCP、plugin/skill 主路径。

### 中期策略：替代 runtime 可行性

候选路径：

1. 外部 Node/DevNode bridge：
   - 优点：可能最快补 JS 执行。
   - 风险：权限边界、nested tool 协议、沙箱和进程生命周期需要重新设计。
2. 轻量 JS runtime：
   - 优点：比 V8 小。
   - 风险：兼容 deno_core/rusty_v8 API 的成本可能很高。
3. 远端 Code Mode service：
   - 优点：OHOS 本机不编 V8。
   - 风险：网络、认证、延迟、secret 和工作区同步复杂。

中期验收应先做一个 proof-of-concept：只跑无副作用 JS 表达式、结构化输入输出和超时控制，不直接开放文件/网络。

### 长期策略：rusty_v8/V8 源码构建

只有在确认 Code Mode 是 Agent runtime 的硬需求后，再进入 V8 路线。需要评估：

1. `aarch64-unknown-linux-ohos` toolchain 是否能完整构建 V8。
2. GN/Ninja、sysroot、libc++、ICU、snapshot、压缩产物和签名流程。
3. 构建时间和远端磁盘空间。
4. 产物体积和启动时间。
5. JIT、W^X、可执行内存、sandbox、ptrace/seccomp 等 OHOS 限制。
6. 与 Codex release binary 的链接、LTO、strip、sign 是否稳定。

长期成功标准：

- `code_mode_only` 能运行真实 JS code cell。
- nested tool orchestration 可跑一个最小端到端任务。
- 超时、取消、输出截断、错误堆栈和资源清理可控。
- 构建脚本可重复，失败可诊断。

### 失败时如何判断

- rusty_v8 prebuilt 404：仍是上游预编译包缺失，不是网络问题。
- 源码构建失败在 GN/sysroot：toolchain/平台识别问题。
- 链接失败：libc++/ICU/snapshot/符号或 LTO 问题。
- 运行期崩溃：JIT/可执行内存/线程/信号/沙箱限制。
- JS 能跑但 nested tool 不行：runtime 可用不等于 Code Mode orchestration 可用。

## 建议执行顺序

1. ChatGPT 登录态 + GitHub connector 真实 tool invocation。
2. Cloud task 正向链路。
3. 真实 Agent Identity JWT。
4. remote-control connected 状态。
5. GUI / 浏览器插件实机能力。
6. Code Mode 长期策略评审和 PoC。

理由：前 3 项直接决定 Codex 是否能作为服务型 Agent runtime；第 4 项决定本机远控和 app-server 生命周期；第 5 项受 HarmonyOS GUI session 条件影响，可能需要不同接入方式；Code Mode 代价最大，应在确认前面 Agent 链路确实需要它之后再投入长编译。

## 建议新增脚本

- `11-chatgpt-github-connector-positive.zsh`：登录态、GitHub connector discovery、只读 tool invocation。
- `12-cloud-task-positive.zsh`：cloud task create/list/status/diff/apply 最小闭环。
- `13-agent-identity-jwt-positive.zsh`：JWT 脱敏审计、JWKS 验证、identity auth 正向调用。
- `14-remote-control-connected.zsh`：standalone layout、daemon start/status/stop、ws connected probe。
- `15-gui-browser-plugin-probe.zsh`：GUI session、browser command、plugin tool exposure、截图/导航 smoke。
- `16-code-mode-strategy-poc.zsh`：短期 stub 防误判检查；中长期 PoC 成功后再扩展。

所有脚本继续遵守 secret-safe 约束：secret 只走 stdin 或临时环境；不写配置、不写日志、不放命令行参数；输出前脱敏；失败时保留错误分类和最小证据。
