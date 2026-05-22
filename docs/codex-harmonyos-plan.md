# HarmonyOS PC 上运行 Codex CLI

## Summary

目标是在 HarmonyOS 6.0 PC 上从 [openai/codex](https://github.com/openai/codex) 源码构建并运行 Codex CLI，主交付物是远端可直接执行的原生 `codex` 命令。远端 HarmonyOS PC 的约定入口是 `ssh -p 22222 chenjh@localhost`；本次执行期间 `22222` 连接被本机端口转发重置，临时使用已验证可用的 `ssh -p 22223 chenjh@localhost`，待 `22222` 转发恢复后可切回。基于调研结果，走 Rust 原生二进制路线，不把 npm wrapper 作为主路径，因为 DevNode 在 SSH 下需要 `--jitless`，且上游 `codex-cli/bin/codex.js` 目前不识别 `process.platform = "openharmony"`。

2026-05-23 更新：当前 `22222` 已恢复可用；Codex release build、签名、非交互 smoke、工具调用 e2e、TUI 两轮 e2e 和多 TERM 覆盖均已完成。用户级安装入口已创建为 `/storage/Users/currentUser/.local/bin/codex`，该 wrapper 会加载 `~/Claude/codex-ohos/env.sh` 并执行已签名的 release binary。

## Key Changes

- 在 HarmonyOS 端创建独立工作区：`~/Claude/codex-openai` 放源码，`~/Claude/codex-ohos/bin/codex` 放启动包装脚本，`~/Claude/codex-ohos/env.sh` 放构建/运行环境变量。
- 克隆 `https://github.com/openai/codex.git`，记录执行时的 `main` HEAD；构建入口固定为 `codex-rs`，命令目标为 `cargo build --manifest-path codex-rs/Cargo.toml -p codex-cli --bin codex --release --locked`。
- 配置 HarmonyOS 构建环境：
  - `TMPDIR=$HOME/Claude/tmpdir`
  - `LD_LIBRARY_PATH=/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin`
  - `CC=/data/service/hnp/bin/clang`
  - `CXX=/data/service/hnp/bin/clang++`
  - `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=/data/service/hnp/bin/clang`
  - `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY=http://127.0.0.1:7890`（使用远端已运行的 mihomo mixed proxy）
  - `CARGO_NET_GIT_FETCH_WITH_CLI=true`
  - `RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-arg=-B$HOME/Claude/lib/linker_wrapper"`
- 创建 `ld.lld -> ld.bfd` wrapper，避开 HarmonyOS SDK `ld.lld` 依赖缺失问题。
- 增加 `RUSTC_WRAPPER` 自动签名脚本：每次 `rustc` 成功后扫描本次 `--out-dir` 新产出的 ELF、`.so`、build script、proc-macro dylib，并用 `/data/service/hnp/bin/binary-sign-tool sign -selfSign 1` 签名。最终再批量签名 `target/release/codex`。
- 参考 HarmonyOS PC 上的 mihomo 适配文档与 mihomo 官方 `proxy-groups`/`proxy-providers` 配置说明，优先复用远端已有可用订阅与节点；将 `~/Claude/mihomo-config/config.yaml` 的 `PROXY` 组从手动 `select` 改为 `url-test`，用 `https://www.gstatic.com/generate_204` 做健康检查和最低延迟选择，并增加 `FALLBACK` 组作为后续切换方案。未知公开 Clash 订阅只作为临时网络排障候选，不用于承载 Codex API key 流量；本次实际执行未把密钥流量切到来源不明的公开代理。
- 如果上游因 `target_os="linux", target_env="ohos"` 误启用 Linux sandbox 代码导致编译失败，补最小补丁：把相关 Linux sandbox/landlock/bwrap 分支 gate 为 `all(target_os = "linux", not(target_env = "ohos"))`，HarmonyOS 上默认使用 no-sandbox/danger-full-access 路径。
- 如果 `openssl-sys` 探测不到系统 OpenSSL dev headers/pkg-config，为 `target.aarch64-unknown-linux-ohos` 补 target-specific `openssl-sys = { workspace = true, features = ["vendored"] }`，与 musl target 一样从源码构建 OpenSSL。
- 如果 `rustyline` 经由 `nix::ioctl_read_bad!` 编译时报 `expected i32, found u64`，说明 HarmonyOS 的 `libc::ioctl` request 参数类型与 `nix` 的默认 Linux `c_ulong` 假设不一致；对 `nix-0.28.0/src/sys/ioctl/linux.rs` 补 `target_env = "ohos"`，让 `ioctl_num_type` 使用 `libc::c_int`。若 Cargo 仍复用旧 `nix` 宏元数据，则在 `rustyline-14.0.0/src/tty/unix.rs` 给 OHOS 增加直接 `libc::ioctl(fd, libc::TIOCGWINSZ as _, data)` 分支，绕开宏内类型假设。
- 如果任一 `nix` 版本的 `src/sys/socket/mod.rs` 在 `cmsghdr.cmsg_len` 赋值时报 `expected u32, found usize`，对赋值右侧补 `as _`，让 OHOS 的 libc 字段类型参与推断；这是 HarmonyOS `cmsghdr` 字段类型与常规 Linux 目标不同导致的最小兼容补丁。本次远端 registry 中已对 `nix-0.28.0`、`nix-0.29.0`、`nix-0.30.1`、`nix-0.31.2` 做同类预防补丁。
- 如果 `v8` 构建尝试下载 `librusty_v8_release_aarch64-unknown-linux-ohos.a.gz` 并 404，说明 upstream rusty_v8 没有 HarmonyOS 预编译包。第一阶段不从源码编译 V8；对 `codex-code-mode` 增加 `target_env = "ohos"` stub，并把 `v8`/`deno_core_icudata` 依赖移到非 OHOS target-specific dependencies。结果是 HarmonyOS Codex CLI 可运行主功能，但 Code Mode 会返回不可用提示。

## Runtime Config

- 在远端 `~/.codex/config.toml` 只写非密钥配置，密钥不落盘。
- 配置自定义 provider，按官方 Codex 文档放在用户级配置而不是项目 `.codex/config.toml`：

```toml
model = "gpt-5.4-mini"
model_provider = "subapi_elias"

[model_providers.subapi_elias]
name = "SUBAPI ELIAS OpenAI-compatible"
base_url = "<SUBAPI_ELIAS_BASE_URL>/v1"
env_key = "SUBAPI_ELIAS_API_KEY"
wire_api = "responses"
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
stream_idle_timeout_ms = 120000
```

- 运行测试时从本地环境变量读取 `SUBAPI_ELIAS_API_KEY` 和 `SUBAPI_ELIAS_BASE_URL`，通过 SSH 命令临时传入远端；密钥不写入远端 shell 配置或文件。
- 远端 `~/.codex/config.toml` 可以写入由 `SUBAPI_ELIAS_BASE_URL` 推导出的 `base_url`，但不得写入 `SUBAPI_ELIAS_API_KEY` 的值。
- 最终 `~/Claude/codex-ohos/bin/codex` 是 shell wrapper，负责 source env、设置 `CODEX_HOME`/`TMPDIR`/库路径，然后 exec 已签名的 `target/release/codex`。
- 用户 PATH 安装入口是 `/storage/Users/currentUser/.local/bin/codex`。该 wrapper 与辅助 wrapper 一样加载 `~/Claude/codex-ohos/env.sh`，设置 `CODEX_HOME="$HOME/.codex"`，然后 exec `~/Claude/codex-openai/codex-rs/target/release/codex`。已验证 `command -v codex`、`codex --version` 和 `codex --help`。

## Test Plan

- 环境 smoke：
  - `curl -x http://127.0.0.1:7890 -I https://github.com`
  - `curl http://127.0.0.1:9090/proxies/PROXY` 确认 mihomo `PROXY` 类型为 `URLTest` 且有当前可用节点。
  - `codex --version`
  - `codex --help`
  - `codex debug models --bundled`
- API smoke：
  - `codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Return exactly: pong"`
  - 通过 stdout 验证最终回答包含 `pong`。
- 工具调用端到端：
  - 在 `~/Claude/codex-e2e-work` 创建一次性测试目录。
  - 运行 `codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Create hello.txt containing exactly codex-ohos-ok"`
  - 验证 `hello.txt` 内容完全等于 `codex-ohos-ok`。
- PTY/TUI smoke：
  - 用 `ssh -tt` 启动 `codex --help` 和一次短 TUI 启动检查，确认无 panic、无签名 permission denied、无 `/tmp` 写入错误。
- 失败判定与修复：
  - `permission denied` 且文件是 ELF：补签名。
  - `/tmp` read-only：确认 `TMPDIR` 没丢。
  - linker/libxml2 报错：确认 `-B$HOME/Claude/lib/linker_wrapper` 生效。
  - npm/Node 崩溃：不走 npm 主路径；需要 npm 包时再单独 patch `codex-cli/bin/codex.js` 支持 `openharmony` 并用 `node --jitless`。

## Execution Status

- 2026-05-22 19:26 CST：`ssh -p 22222 chenjh@localhost` 仍返回 `Connection reset by 127.0.0.1 port 22222`；`ssh -p 22223 chenjh@localhost` 可正常执行命令。本次执行继续使用 `22223` 临时通道。
- 2026-05-22 19:26 CST：mihomo 已重启并使用 `~/Claude/mihomo-config/config.yaml`；`PROXY` 为 `URLTest`，当前自动选择 `SG-A02-Tro`，`https://www.gstatic.com/generate_204` 延迟记录约 406 ms。`curl -I -x http://127.0.0.1:7890 https://github.com` 返回 `HTTP/1.1 200 OK`，GitHub 访问已通过代理验证。
- 2026-05-22 19:30 CST：`cargo build --manifest-path codex-rs/Cargo.toml -p codex-cli --bin codex --release --locked -j4` 正在远端运行。已通过 OpenSSL vendored build、`reqwest`、`codex-protocol`、`codex-client`、`codex-api`、`codex-code-mode` stub 等阶段；当前仍在 release/LTO 后段编译，尚未进入最终签名和 smoke 测试。
- 本地环境变量 `SUBAPI_ELIAS_BASE_URL` 和 `SUBAPI_ELIAS_API_KEY` 均已确认存在；后续 API smoke 只通过 SSH 命令临时传入，不写入远端文件或日志。
- 2026-05-22 20:49 CST：用户误关 HarmonyOS PC SSH 服务后，`22223` 已恢复可连接，但原先由 SSH 会话托管的 `cargo build`/`rustc` 进程已消失，`target/release/codex` 尚未产出，日志停在最终 `codex` fat LTO 阶段且无明确失败。为避免再次被 SSH 断连影响，已改用 detached 构建。
- 2026-05-22 20:50 CST：用 `/bin/setsid zsh -lc ...` 重启增量构建，日志仍写入 `~/Claude/codex-ohos/logs/build-codex-cli.log`，PID 写入 `~/Claude/codex-ohos/logs/build-codex-cli.pid`，退出结果写入 `~/Claude/codex-ohos/logs/build-codex-cli.status`。新日志开头为 `detached-build-start Fri May 22 20:50:13 CST 2026`，`cargo build` 已确认运行。
- 2026-05-22 22:05 CST：detached build 在最终 `codex-cli` 链接阶段失败，`aws-lc-sys-0.39.0` 的 `bcm.c.obj` 引用了 AArch64 asm 符号但 `libaws_lc_0_39_0_crypto.a` 未包含对应 asm 对象。CMake 日志显示 `Detected generic linux platform. No assembly files will be included.`；修复方向是在 HarmonyOS 构建环境中设置 `AWS_LC_SYS_NO_ASM=1`，让 aws-lc 头文件和 C 实现一致走 no-asm 路径后重启增量构建。
- 2026-05-23 01:03 CST：detached release build 成功完成，`~/Claude/codex-ohos/logs/build-codex-cli.status` 写入 `rc=0`，`~/Claude/codex-openai/codex-rs/target/release/codex` 产出，大小约 127M。
- 2026-05-23 01:15 CST：最终 `codex` 二进制已完成 HarmonyOS 自签名，`codex --version` 和 `codex debug models --bundled` 通过。
- 2026-05-23 01:17 CST：创建远端 `~/.codex` 后，基础 CLI smoke 正常。临时测试 provider 使用 `experimental_bearer_token`，不是 `api_key`；远端配置已改为 `model = "gpt-5.4-mini"`、`model_provider = "custom"`、`base_url = "https://opr.tokents.top/v1"`、`wire_api = "responses"`。
- 2026-05-23 01:20 CST：非交互式 API smoke 通过，`codex exec ... "Return exactly: pong"` 返回 `pong`。工具调用 e2e 通过，Codex 在 `~/Claude/codex-e2e-work` 创建 `hello.txt`，内容严格等于 `codex-ohos-ok`。
- 2026-05-23 01:42 CST：远端源码已关联 `git@github.com:chenjh16/codex.git` 并推送 `ohos` 分支，提交为 `f2f646d Add HarmonyOS CLI adaptation`。远端 HTTPS push 会认证失败，使用已有 GitHub SSH key 可成功推送。
- 2026-05-23 01:47-01:54 CST：开始 TUI 端到端自动化。`ssh -tt` 可启动 TUI，`--no-alt-screen` 模式下可看到界面渲染、spinner 和输入区；初始自动化脚本曾误把启动命令行中的 marker 当成模型响应，需要后续脚本避免在命令行出现期望 token。
- 2026-05-23 01:54 CST：手工启动 `~/Claude/codex-ohos/bin/codex` 时仍显示 `Codex could not find bubblewrap on PATH` 警告。分析确认这不是单纯 PATH 问题：HarmonyOS Rust target 命中 `target_os = "linux"`，导致 TUI 启动时走 `system_bwrap_warning` 的 Linux bubblewrap 探测。`command -v bwrap`/`bubblewrap` 为空；源码树有 vendored bubblewrap 和 `codex-linux-sandbox` crate，但当前 OHOS 运行策略不应把系统当普通 Linux sandbox 平台。
- 2026-05-23 01:57 CST：对远端源码新增第二批 OHOS sandbox 补丁，当前未提交文件为 `codex-rs/arg0/src/lib.rs`、`codex-rs/sandboxing/src/lib.rs`、`codex-rs/sandboxing/src/manager.rs`。补丁方向：把 Linux bwrap warning、platform sandbox 选择、`codex_linux_sandbox_exe` arg0 路径计算从 `target_os = "linux"` 收窄为 `all(target_os = "linux", not(target_env = "ohos"))`；同时为非普通 Linux target 提供 `find_system_bwrap_in_path() -> None` stub，保证 `codex-linux-sandbox` crate 仍可编译。
- 2026-05-23 01:57 CST：第一次增量构建因 `codex-linux-sandbox` 仍引用被 cfg 掉的 `find_system_bwrap_in_path` 失败，`rc=101`。随后补 stub 并于 02:00 CST 重启 detached release build，日志仍写入 `~/Claude/codex-ohos/logs/build-codex-cli.log`，pid/status 仍使用既有路径。
- 2026-05-23 02:16 CST：第二次增量 build 仍在运行，已通过 `codex-linux-sandbox` 前一个 import 错误，正在重编 `codex-core`、`codex-app-server`、`codex-tui`、`codex-exec` 等，说明已进入较完整的 release 编译/链接链路。当前无需继续前台等待；后续应先检查 status/log/process，再决定是否等待或签名测试。
- 2026-05-23 03:32 CST：第二次增量 detached release build 成功完成，日志显示 `Finished release profile`，`build-codex-cli.status` 写入 `rc=0 finished_at=Sat May 23 03:32:46 CST 2026`，目标二进制大小约 127M。
- 2026-05-23 03:46 CST：重新自签名最终 `target/release/codex` 后，`codex --version` 输出 `codex-cli 0.0.0`，`codex debug models --bundled` 通过；随后 `codex --help` 也通过。
- 2026-05-23 03:47-03:58 CST：用 `ssh -tt`、`--no-alt-screen`、`TERM=xterm-256color` 做 TUI 启动捕获，已确认 bubblewrap warning 计数为 0，panic 计数为 0。自动化完整 e2e 仍未通过：expect 捕获只看到终端查询序列和逐字符启动 tip，发送 prompt 或 `/quit` 后远端会留下 `codex --no-alt-screen` 测试进程；已清理这些孤儿测试进程。
- 2026-05-23 03:58 CST：新构建后的非交互 `codex exec "Return exactly: pong-after-sandbox"` 到 provider 返回 `429 Too Many Requests`。这说明当前 API provider 可能限流，不能作为 sandbox/bwrap 补丁失败证据；待限流恢复后需重跑 API smoke 和 TUI 真实模型交互。
- 2026-05-23 03:59 CST：远端 `ohos` 分支已提交并推送第二批补丁，commit 为 `8dbdc6d Disable Linux sandbox probing on HarmonyOS`，`git status -sb` 干净且跟踪 `origin/ohos`。
- 2026-05-23 04:03 CST：改用真实 PTY 会话测试 TUI，确认 TUI 能渲染完整启动界面、加载模型 `gpt-5.4-mini`、接收输入、提交 prompt、进入 `Working` 状态、显示 provider 的 `429 Too Many Requests` 错误，并通过 `/quit` 显示 `Shutting down...` 后关闭 SSH 连接。真实 PTY 中观察到输入文本后通常需要额外一次 Return 才提交。
- 2026-05-23 04:17 CST：远端 provider 配置已恢复为 `env_key = "SUBAPI_ELIAS_API_KEY"`，不在远端 config 保存 key 值；通过 SSH stdin 临时注入本地 key 后，非交互 `codex exec "Return exactly: env-ok"` 通过并返回 `env-ok`。
- 2026-05-23 04:22 CST：安全版内存 PTY harness 完成 TUI 两轮 e2e：第一轮 prompt 返回 `dcba`，第二轮 prompt 返回 `zyxw`，`bubblewrap_warning_count=0`、`panic_count=0`、`error_count=0`、`completed_two_rounds=yes`、`shutdown_seen=yes`。远端无遗留 TUI 测试进程。
- 2026-05-23 04:25 CST：同一安全版内存 PTY harness 补充覆盖 `TERM=screen-256color` 和 `TERM=vt100`；两者均完成两轮 prompt，返回 `hgfe` 和 `lkji`，warning/panic/error 计数均为 0，`shutdown_seen=yes`。
- 2026-05-23 04:55 CST：按用户建议完成用户目录安装：`/storage/Users/currentUser/.local/bin/codex`。安装后在远端 zsh 中把 `$HOME/.local/bin` 加到 PATH，`command -v codex` 返回该路径，`codex --version` 返回 `codex-cli 0.0.0`，`codex --help` 可正常输出帮助内容。
- 2026-05-23 04:55 CST：补充 Agent 能力分析文档 `docs/codex-agent-capability-analysis.md`。结论是 HarmonyOS 当前已完成单 Agent CLI/TUI 主链路，Agent 相关源码能力包括多 Agent、MCP、plugin/skill、Agent graph、Agent identity、app-server/remote-control 和 cloud task；但 Code Mode 在 OHOS 上为 stub，多 Agent/MCP/plugin/app-server/cloud/identity 尚未端到端验收。
- 2026-05-23 04:55 CST：最终配置审计发现远端 `~/.codex/config.toml` 曾残留旧 `experimental_bearer_token` 明文配置；已删除该项、启用 `env_key = "SUBAPI_ELIAS_API_KEY"`，并复扫确认 `secret-scan=clean`。因为明文曾短暂存在于远端配置和审计输出中，建议轮换该测试 key 后再长期使用。

## Next Steps

1. 第一阶段非交互式 Codex CLI 已通过构建、签名、基础 smoke、API smoke 和工具调用 e2e；第二批 sandbox/bwrap 补丁也已构建、签名、验证启动 warning 消失，并推送到 `origin/ohos`。
2. TUI 两轮成功模型响应已通过，`TERM=xterm-256color`、`screen-256color` 和 `vt100` 均已覆盖完整两轮 TUI e2e；当前交付状态满足本阶段 TUI 端到端验收。
3. 用户目录安装已完成，推荐日常入口是 `/storage/Users/currentUser/.local/bin/codex`。保留 `~/Claude/codex-ohos/bin/codex` 作为工程辅助 wrapper。
4. 后续如需把 TUI e2e 固化为脚本，应复用内存型 PTY harness 思路，避免 `expect log_file` 记录 `send` 的 key。当前会话中曾因错误 harness 暴露测试 key，建议轮换后再长期使用。
5. 下一阶段重点是 Agent 能力专项：多 Agent spawn/wait/close/resume、MCP client/server、plugin/skill、app-server/remote-control、exec-server、cloud task 和 Agent identity。
6. Code Mode 当前在 OHOS 上不可用；若后续要补齐完整 Agent runtime，需要单独决策 rusty_v8 源码构建、替代 JS runtime，或显式保留 stub 并降低功能暴露。

## TUI Adaptation Plan

目标是在 HarmonyOS PC 的 SSH/PTY 环境里让 `codex` 交互式界面可实际使用，而不仅是 `--help` 不崩溃。范围包括启动、渲染、输入、终端状态恢复、API 流式输出和一次真实短会话。

1. 建立 TUI 基线：
   - 用 `ssh -tt -p 22223 chenjh@localhost '~/Claude/codex-ohos/bin/codex'` 启动交互式 TUI。
   - 同时覆盖 `TERM=xterm-256color`、`TERM=screen-256color`、`TERM=vt100` 的行为差异。
   - 记录是否出现 panic、空屏、乱码、光标错位、无法退出、终端 raw mode 未恢复。
2. 终端能力适配：
   - 验证 `crossterm` raw mode、alternate screen、cursor show/hide、clear screen、resize event 在 HarmonyOS SSH PTY 下是否正常。
   - 若终端尺寸读取失败，优先检查 `TIOCGWINSZ` 和 `rustyline`/`nix` ioctl 补丁是否覆盖 TUI 路径。
   - 对 HarmonyOS 特有 ioctl 类型差异继续使用最小 cfg 补丁，避免影响普通 Linux target。
3. 输入适配：
   - 验证普通字符、Enter、Backspace、Ctrl-C、Ctrl-D、Esc、方向键、PageUp/PageDown。
   - 验证中文输入和粘贴长 prompt，检查多字节字符宽度、换行、删除和光标位置。
   - 若 bracketed paste 或特殊键序列异常，定位到 `crossterm` event parsing 或 Codex TUI input 层做 target-specific 降级。
4. 渲染适配：
   - 检查 Ratatui 布局、边框、颜色、streaming token 刷新、滚动区域、底部输入框是否稳定。
   - 验证窄窗口和常见窗口尺寸，例如 `80x24`、`120x40`。
   - 如果 Unicode 边框或宽字符导致错位，优先切换到已有 ASCII/兼容渲染路径，或为 OHOS PTY 增加保守 fallback。
5. 交互式 API 验证：
   - 通过 SSH 临时注入 `SUBAPI_ELIAS_*`，启动 TUI 后发送一个短 prompt，例如 `Return exactly: pong`。
   - 验证流式输出、完成状态、错误展示和可继续输入下一轮。
   - 密钥仍不写入远端文件或日志。
6. 终端恢复和退出：
   - 验证 `/quit`、Ctrl-C、Ctrl-D、异常中断后终端 echo/raw mode 能恢复。
   - 如果退出后本地终端不可见输入或光标状态异常，补 panic hook/drop guard 或终端恢复路径。
7. 自动化/半自动化验收：
   - 优先用 `script`、`timeout`、`ssh -tt` 捕获 TUI 启动和退出日志。
   - 对需要人工观察的渲染问题，记录复现命令、窗口大小和截图/录屏路径。
   - TUI 完成标准：能在 SSH PTY 中启动、输入 prompt、看到模型响应、继续第二轮、正常退出，且终端状态恢复。

## Assumptions

- 源码基准使用执行时的 `openai/codex` `main`，并记录 commit 以便复现。
- 首个通过标准选择 `gpt-5.4-mini`，API endpoint 改用本地环境变量 `SUBAPI_ELIAS_BASE_URL` 对应服务；Codex 当前上游只支持 `wire_api = "responses"`。
- 第一阶段优先验证非交互式 `codex exec` 和工具调用；第二阶段把交互式 TUI 作为独立交付项完成适配和验收。
- 参考依据包括：[Codex install docs](https://github.com/openai/codex/blob/main/docs/install.md)、[Codex auth docs](https://developers.openai.com/codex/auth#alternative-model-providers)、[Codex custom provider docs](https://developers.openai.com/codex/config-advanced#custom-model-providers)、[Codex config reference](https://developers.openai.com/codex/config-reference)、[mihomo proxy-groups docs](https://wiki.metacubex.one/en/config/proxy-groups/)、[mihomo proxy-providers docs](https://wiki.metacubex.one/en/config/proxy-providers/)。
