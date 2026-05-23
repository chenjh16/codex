# Codex CLI HarmonyOS 适配经验记录

记录时间：2026-05-22

本文整理把 `openai/codex` 的 Rust CLI 适配到 HarmonyOS PC 的过程经验。它面向后续复现、升级上游、排障，不包含 API key、订阅密钥、代理节点密码等敏感值。

## 目标和路线

目标是在 HarmonyOS 6.0 PC 上获得可直接执行的原生 `codex` 命令。实际路线选择 Rust 原生二进制，而不是 npm wrapper。

选择 Rust 路线的原因：

- HarmonyOS SSH 环境下 DevNode/Node 路径不稳定，常需要 `--jitless`。
- 上游 npm wrapper 当前主要按常规 `process.platform` 分发，不直接识别 `openharmony`。
- Rust CLI 是 Codex 当前核心实现，修 target/依赖兼容问题后更接近最终交付形态。

远端目录约定：

- `~/Claude/codex-openai`：上游源码和本次补丁。
- `~/Claude/codex-ohos/env.sh`：构建和运行环境变量。
- `~/Claude/codex-ohos/bin/codex`：最终 wrapper。
- `~/.local/bin/codex`：用户 PATH 安装入口，实际路径为 `/storage/Users/currentUser/.local/bin/codex`。
- `~/Claude/codex-ohos/logs/build-codex-cli.log`：构建日志。
- `~/Claude/mihomo-config/config.yaml`：远端 mihomo 配置。

SSH 约定入口是：

```sh
ssh -p 22222 chenjh@localhost
```

本次执行中 `22222` 被本机端口转发重置，实际临时使用：

```sh
ssh -p 22223 -o BatchMode=yes -o StrictHostKeyChecking=no chenjh@localhost
```

## 构建环境要点

HarmonyOS 端需要尽量把临时目录、链接器、代理和动态库路径显式化。核心环境如下：

```sh
export TMPDIR="$HOME/Claude/tmpdir"
export LD_LIBRARY_PATH="/usr/lib:$HOME/.rust/lib:$HOME/.local/lib:/system/lib64:$HOME/Claude/llama.cpp/build/bin"
export CC="/data/service/hnp/bin/clang"
export CXX="/data/service/hnp/bin/clang++"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="/data/service/hnp/bin/clang"
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"
export ALL_PROXY="http://127.0.0.1:7890"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export RUSTFLAGS="-C linker=/data/service/hnp/bin/clang -C link-arg=-B$HOME/Claude/lib/linker_wrapper"
```

构建命令：

```sh
cd "$HOME/Claude/codex-openai"
CARGO_BUILD_JOBS=4 MAKEFLAGS=-j4 \
  cargo build --manifest-path codex-rs/Cargo.toml \
  -p codex-cli --bin codex --release --locked -j4
```

经验：

- `TMPDIR` 必须稳定指向可写目录，避免落到只读或行为异常的 `/tmp`。
- `-B$HOME/Claude/lib/linker_wrapper` 用来让工具链找到合适 linker，绕过 HarmonyOS SDK 默认 `ld.lld` 依赖缺失。
- release + LTO 在 HarmonyOS PC 上很慢，OpenSSL vendored build 和后段 Codex crate 都可能看起来长时间无日志，但只要 `rustc` CPU 时间在增长，就不应急着中断。

## 网络和 mihomo

本次没有把 Codex API key 流量切到网上随机公开 Clash 订阅。公开订阅可作为临时下载排障候选，但不适合承载鉴权 API 流量。

实际策略是复用远端已有可用节点，把 `PROXY` 从手动 `select` 改为 `url-test`：

```yaml
proxy-groups:
  - name: PROXY
    type: url-test
    proxies:
      - SG-A01-Tro
      - SG-A02-Tro
      - SG-A03-Tro
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 80
    timeout: 5000

  - name: FALLBACK
    type: fallback
    proxies:
      - SG-A01-Tro
      - SG-A02-Tro
      - SG-A03-Tro
    url: https://www.gstatic.com/generate_204
    interval: 300
    timeout: 5000
```

验证命令：

```sh
curl -s --max-time 5 http://127.0.0.1:9090/proxies/PROXY
curl -I --max-time 12 -x http://127.0.0.1:7890 https://github.com
```

本次观测：

- `PROXY` 类型为 `URLTest`。
- 自动选中了一个可用的新加坡节点。
- `https://www.gstatic.com/generate_204` 延迟约 406 ms。
- GitHub 经代理返回 `HTTP/1.1 200 OK`。

## 密钥和 provider 配置

Codex API 使用本地环境变量：

- `SUBAPI_ELIAS_BASE_URL`
- `SUBAPI_ELIAS_API_KEY`

原则：

- `SUBAPI_ELIAS_API_KEY` 不写入远端 `~/.codex/config.toml`、shell rc、日志或计划文档。
- 远端配置只写 provider 元数据和 `env_key`。
- API smoke 时从本地通过 SSH 命令临时注入环境变量。

远端 `~/.codex/config.toml` 模板：

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

注意：如果 `SUBAPI_ELIAS_BASE_URL` 已带 `/v1`，不要重复追加。

## 代码和依赖适配点

### 1. OpenSSL

现象：

- `openssl-sys` 在 HarmonyOS 上找不到系统 OpenSSL dev headers/pkg-config。

处理：

```toml
[target.aarch64-unknown-linux-ohos.dependencies]
openssl-sys = { workspace = true, features = ["vendored"] }
```

代价：

- 首次 release build 会编译 OpenSSL，耗时较长。
- 后续增量构建会明显好一些。

### 1.1. aws-lc-sys no-asm

现象：

- `aws-lc-sys-0.39.0` 在最终链接 `codex-cli` 时出现大量 undefined reference，例如 `aws_lc_0_39_0_bignum_sqr_p521`、`aws_lc_0_39_0_md5_block_asm_data_order`、`aws_lc_0_39_0_mlkem_ntt_asm`、`aws_lc_0_39_0_CRYPTO_rndr_multiple8`。
- CMake 配置日志显示 `Detected generic linux platform. No assembly files will be included.`，但生成的配置/头文件仍让 C 代码引用 AArch64 asm 符号。

处理：

```sh
export AWS_LC_SYS_NO_ASM=1
```

把该变量写入 `~/Claude/codex-ohos/env.sh` 后重启增量构建，让 `aws-lc-sys` build script 重新配置并使用 no-asm 路径。

### 2. 自动签名

HarmonyOS 对可执行 ELF、proc-macro dylib、build script 等产物有签名要求。实践中只签最终二进制不够，构建过程中生成并执行的 build script 也可能因为签名问题失败。

处理：

- 通过 `RUSTC_WRAPPER` 包装 `rustc`。
- 每次 `rustc` 成功后扫描本次 `--out-dir` 新产出的 ELF、`.so`、build script、proc-macro dylib。
- 使用 `/data/service/hnp/bin/binary-sign-tool sign -selfSign 1` 签名。
- 跳过 `.o`、`.rlib`、`.rmeta`、`.d`、`.a`。
- `.codesign section already exists` 视为成功。

最终仍需要对 `target/release/codex` 再签一次：

```sh
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 \
  -inFile "$HOME/Claude/codex-openai/codex-rs/target/release/codex" \
  -outFile "$HOME/Claude/codex-openai/codex-rs/target/release/codex.signed"
mv "$HOME/Claude/codex-openai/codex-rs/target/release/codex.signed" \
   "$HOME/Claude/codex-openai/codex-rs/target/release/codex"
chmod +x "$HOME/Claude/codex-openai/codex-rs/target/release/codex"
```

### 3. nix/rustyline ioctl 类型

现象：

- `rustyline` 经 `nix::ioctl_read_bad!` 编译时报 `expected i32, found u64`。

原因：

- HarmonyOS 的 `libc::ioctl` request 参数类型与 `nix` 默认 Linux `c_ulong` 假设不同。

处理：

- 在 `nix-0.28.0/src/sys/ioctl/linux.rs` 对 `ioctl_num_type` 增加 `target_env = "ohos"`，使用 `libc::c_int`。
- 如 Cargo 复用旧宏元数据，则在 `rustyline-14.0.0/src/tty/unix.rs` 为 OHOS 直接调用：

```rust
libc::ioctl(fd, libc::TIOCGWINSZ as _, data)
```

### 4. nix cmsghdr.cmsg_len 类型

现象：

- 多个 `nix` 版本在 `cmsghdr.cmsg_len` 赋值时报 `expected u32, found usize`。

处理：

```rust
(*cmsg).cmsg_len = self.cmsg_len() as _;
```

本次对这些版本做了同类 registry patch：

- `nix-0.28.0`
- `nix-0.29.0`
- `nix-0.30.1`
- `nix-0.31.2`

### 5. V8 / Code Mode

现象：

- `v8 v147.4.0` 尝试下载 `librusty_v8_release_aarch64-unknown-linux-ohos.a.gz`，返回 404。

判断：

- upstream rusty_v8 没有 HarmonyOS 预编译包。
- 从源码编 V8 成本高、链路长，不适合第一阶段阻塞 CLI 主功能。

处理：

- `codex-rs/code-mode/Cargo.toml`：把 `v8` 和 `deno_core_icudata` 移到非 OHOS target-specific dependencies。
- `codex-rs/code-mode/src/lib.rs`：非 OHOS 使用真实 runtime/service，OHOS 使用 stub。
- 新增：
  - `codex-rs/code-mode/src/runtime/ohos_stub.rs`
  - `codex-rs/code-mode/src/service_ohos_stub.rs`

验证：

```sh
cargo tree --manifest-path codex-rs/Cargo.toml \
  -p codex-cli \
  --target aarch64-unknown-linux-ohos \
  -i v8
```

预期输出类似 `nothing to print`。结果是 CLI 主功能可继续构建，Code Mode 在 OHOS 上返回不可用提示。

### 6. Linux sandbox gate

HarmonyOS 的 Rust target 常表现为 `target_os = "linux"` 且 `target_env = "ohos"`。因此上游一些 Linux-only sandbox、landlock、bwrap 分支可能被误启用。

原则：

```rust
all(target_os = "linux", not(target_env = "ohos"))
```

HarmonyOS 第一阶段优先走 no-sandbox / danger-full-access 路径，先保证非交互式 `codex exec` 和工具调用可用。

## 构建状态判断

低频监控即可。普通编译阶段可以 3 到 5 分钟一次；进入最终 release/fat LTO 链接后，建议 10 分钟一次：

```sh
tail -n 180 "$HOME/Claude/codex-ohos/logs/build-codex-cli.log"
ps -ef | grep -E "cargo build|rustc-sign-wrapper|rustc|clang|ld.lld|ld.bfd" | grep -v grep
ls -lh "$HOME/Claude/codex-openai/codex-rs/target/release/codex" 2>/dev/null || true
```

如果构建是通过 SSH 前台会话启动，远端 SSH 服务重启或断连可能会把 cargo/rustc 一起带掉。更稳妥的做法是把构建作为 detached 任务启动：

```sh
/bin/setsid zsh -lc '
set -eu
. "$HOME/Claude/codex-ohos/env.sh"
cd "$HOME/Claude/codex-openai"
LOG="$HOME/Claude/codex-ohos/logs/build-codex-cli.log"
STATUS="$HOME/Claude/codex-ohos/logs/build-codex-cli.status"
{
  printf "detached-build-start %s\n" "$(date)"
  set +e
  CARGO_BUILD_JOBS=4 MAKEFLAGS=-j4 cargo build --manifest-path codex-rs/Cargo.toml -p codex-cli --bin codex --release --locked -j4
  rc=$?
  set -e
  printf "detached-build-end %s rc=%s\n" "$(date)" "$rc"
  printf "rc=%s finished_at=%s\n" "$rc" "$(date)" > "$STATUS"
  exit "$rc"
} > "$LOG" 2>&1
' </dev/null >/dev/null 2>&1 &
```

同步写一个 `build-codex-cli.pid` 会更方便后续确认，但不要只相信 launcher PID；最终判断仍看 `cargo`/`rustc` 进程、状态文件和目标二进制。

判断方式：

- 日志还在出现新 crate，说明正常推进。
- 日志短时间不动但 `rustc` CPU 时间增长，通常是 release/LTO 正常行为。
- `openssl-sys` build script 在 `make install_dev` 期间可能慢，但如果子进程仍在复制或编译，不要中断。
- 如果只剩无 CPU 增长的 build script，再查 `/proc/<pid>/cmdline`、`/proc/<pid>/wchan` 和子进程树。

## 验证清单

构建成功后按这个顺序验证：

```sh
~/Claude/codex-ohos/bin/codex --version
~/Claude/codex-ohos/bin/codex --help
~/Claude/codex-ohos/bin/codex debug models --bundled
```

API smoke：

```sh
SUBAPI_ELIAS_BASE_URL="$SUBAPI_ELIAS_BASE_URL" \
SUBAPI_ELIAS_API_KEY="$SUBAPI_ELIAS_API_KEY" \
~/Claude/codex-ohos/bin/codex exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  "Return exactly: pong"
```

工具调用端到端：

```sh
mkdir -p "$HOME/Claude/codex-e2e-work"
cd "$HOME/Claude/codex-e2e-work"
SUBAPI_ELIAS_BASE_URL="$SUBAPI_ELIAS_BASE_URL" \
SUBAPI_ELIAS_API_KEY="$SUBAPI_ELIAS_API_KEY" \
~/Claude/codex-ohos/bin/codex exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  "Create hello.txt containing exactly codex-ohos-ok"
test "$(cat hello.txt)" = "codex-ohos-ok"
```

用户目录安装验证：

```sh
export PATH="$HOME/.local/bin:$PATH"
command -v codex
codex --version
codex --help >/dev/null && echo help-ok
```

当前已验证结果：

- `command -v codex` 返回 `/storage/Users/currentUser/.local/bin/codex`。
- `codex --version` 返回 `codex-cli 0.0.0`。
- `codex --help` 可正常输出帮助内容。

## TUI 适配重点

`codex exec` 可用只代表非交互式链路打通，不能等同于 TUI 已适配。HarmonyOS PC 上的 TUI 需要单独验收 SSH PTY、终端控制序列、输入事件和终端状态恢复。

建议把 TUI 作为第二阶段交付项：

1. 启动基线：
   - `ssh -tt -p 22223 chenjh@localhost '~/Claude/codex-ohos/bin/codex'`
   - 分别测试 `TERM=xterm-256color`、`TERM=screen-256color`、`TERM=vt100`。
   - 记录空屏、panic、乱码、光标错位、无法退出、退出后终端 echo 异常。
2. 终端能力：
   - 检查 `crossterm` raw mode、alternate screen、cursor show/hide、clear screen、resize event。
   - 如果尺寸读取异常，优先回到 `TIOCGWINSZ`、`nix`、`rustyline` 和 HarmonyOS `ioctl` request 类型差异。
   - 所有修复尽量使用 `target_env = "ohos"` 收窄，不影响普通 Linux。
3. 输入事件：
   - 验证普通字符、Enter、Backspace、Ctrl-C、Ctrl-D、Esc、方向键、PageUp/PageDown。
   - 验证中文输入、粘贴长 prompt、多字节字符宽度、换行和删除。
   - bracketed paste 或特殊键异常时，定位 `crossterm` event parsing 或 Codex TUI input 层。
4. 渲染：
   - 检查 Ratatui 布局、边框、颜色、streaming token 刷新、滚动区域、底部输入框。
   - 覆盖 `80x24` 和 `120x40`，必要时增加 ASCII/兼容渲染 fallback。
5. 交互式 API：
   - 临时注入 `SUBAPI_ELIAS_*`，在 TUI 中发送 `Return exactly: pong`。
   - 验证流式输出、完成状态、错误展示和第二轮继续输入。
6. 退出恢复：
   - 测 `/quit`、Ctrl-C、Ctrl-D、异常中断。
   - 退出后必须恢复 echo/raw mode、光标显示和屏幕状态。

完成标准：TUI 能在 HarmonyOS SSH PTY 中启动、输入 prompt、显示模型响应、继续第二轮、正常退出，且终端状态恢复。

## 上游化建议

更适合提交到上游的改动：

- `target_env = "ohos"` 下禁用 V8 Code Mode 或显式 feature gate。
- Linux sandbox 条件从 `target_os = "linux"` 收窄到排除 OHOS。
- OpenSSL vendored fallback 是否可接受需要讨论，因为上游可能更偏向系统依赖或 rustls 路线。

不适合直接上游化的本地补丁：

- registry 里的 `nix` 和 `rustyline` 直接改源码，应转成 `[patch.crates-io]`、fork、或等待上游支持。
- HarmonyOS 自签名 wrapper 和 linker wrapper 更像本地工具链适配层，适合放在 `codex-ohos` 辅助目录而不是 Codex 主仓。
- 远端 mihomo 节点和订阅信息属于本地运行环境，不应进入仓库。

## 当前已知限制

- Code Mode 在 OHOS 上第一阶段不可用。
- 交互式 TUI 已通过真实模型两轮 e2e；如果后续固化自动化脚本，仍必须坚持内存型 PTY harness 和输出脱敏。
- 如果本地 SSH 端口转发消失，先用 `hdc fport ls` 确认，再恢复 `tcp:22222 tcp:2222` 和需要的临时端口；不要在断掉的 tunnel 上继续 sleep 监控。
- `codex` wrapper 设置 `CODEX_HOME="$HOME/.codex"`，smoke 前必须确保远端 `~/.codex` 目录存在，否则会报 `Error finding codex home`。
- 临时 OpenAI-compatible 测试 provider 在当前 Codex 版本中如必须明文测试，应使用 `experimental_bearer_token`，不是 `api_key`；但当前远端配置已恢复为 `env_key = "SUBAPI_ELIAS_API_KEY"`，不应再把 key 写入配置文件。`wire_api = "chat"` 会被拒绝，必须使用 `wire_api = "responses"`。
- 远端 `env.sh` 默认设置 `HTTP_PROXY=http://127.0.0.1:7890`；如果 mihomo 未运行，但测试 API 可直连，需要把测试域名加入 `NO_PROXY`，例如 `opr.tokents.top`。
- 后续低成本测试优先用 `gpt-5.4-mini`，只有必要时再切到更贵模型。
- HarmonyOS PC 的非交互 SSH 可能默认落到 `/bin/sh` 和窄 `PATH`，导致误判 `git`/`cargo` 不存在；远端执行构建、git、测试、mihomo 检查时应显式使用 `/usr/bin/zsh -lc '...'`。
- 即使通过 `/usr/bin/zsh -lc` 执行，`$SHELL` 仍可能显示 `/bin/sh`；判断环境是否正确应看实际命令解析，例如 `command -v git` 应返回 `/data/service/hnp/bin/git`。
- 不要根据 plain `ssh -p 22222 chenjh@localhost 'command -v git'` 的失败判断远端没有 git。先用 `ssh -p 22222 ... "/usr/bin/zsh -lc 'command -v git; git --version'"` 复核。
- 发布到 `https://github.com/chenjh16/codex` 时，远端 HTTPS push 会报 `Authentication failed or Permission denied`，但 SSH key 已绑定 `chenjh16`；应把 remote 切到 `git@github.com:chenjh16/codex.git` 后 push `ohos` 分支。
- `ssh -T git@github.com` 返回 `Hi chenjh16! You've successfully authenticated, but GitHub does not provide shell access.` 时说明认证成功；退出码非零是 GitHub 不提供 shell，不代表 key 无效。

## 2026-05-23 构建和非交互验证结果

- 2026-05-23 01:03 CST：detached release build 完成，`rc=0`，目标二进制为 `~/Claude/codex-openai/codex-rs/target/release/codex`，大小约 127M。
- 2026-05-23 01:15 CST：最终二进制已用 `/data/service/hnp/bin/binary-sign-tool sign -selfSign 1` 自签名，并保留可执行权限。
- `codex --version` 通过，输出 `codex-cli 0.0.0`。
- `codex debug models --bundled` 通过，能列出 bundled model metadata。
- 临时 provider 配置写在远端 `~/.codex/config.toml`，示例：

```toml
model = "gpt-5.4-mini"
model_provider = "custom"

[model_providers.custom]
name = "custom"
base_url = "https://opr.tokents.top/v1"
wire_api = "responses"
supports_websockets = false
experimental_bearer_token = "<temporary test key>"
request_max_retries = 0
stream_max_retries = 0
stream_idle_timeout_ms = 120000
```

- `codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Return exactly: pong"` 已通过，返回 `pong`。
- 工具调用 e2e 已通过：在 `~/Claude/codex-e2e-work` 让 Codex 创建 `hello.txt`，并用 `test "$(cat hello.txt)" = "codex-ohos-ok"` 校验成功。
- 2026-05-23 01:42 CST：远端 `/storage/Users/currentUser/Claude/codex-openai` 已创建并推送 `ohos` 分支到 `git@github.com:chenjh16/codex.git`，提交为 `f2f646d Add HarmonyOS CLI adaptation`。

## 2026-05-23 TUI 和 bubblewrap 警告排查

- TUI 能通过 `ssh -tt -p 22222` 启动，`--no-alt-screen` 下可捕获到界面渲染、spinner、输入区和模型输出片段。自动化脚本要避免把启动命令行里的 prompt marker 当成模型响应；期望 token 不应直接出现在启动命令行，或应等待输入区/模型输出状态后再匹配。
- 手工运行 `~/Claude/codex-ohos/bin/codex` 会显示 `Codex could not find bubblewrap on PATH`。远端 `command -v bwrap` 和 `command -v bubblewrap` 均为空，`~/Claude/codex-openai/codex-rs` 内存在 vendored bubblewrap 源码和 `codex-linux-sandbox` crate，但没有可直接放进 PATH 的已验证系统 bwrap。
- 根因不是 wrapper PATH 漏配，而是 HarmonyOS target 仍满足 `target_os = "linux"`，导致 `codex-rs/sandboxing/src/lib.rs` 导出并调用 Linux bwrap warning 逻辑；TUI startup prompt 通过 `codex_sandboxing::system_bwrap_warning(config.permissions.permission_profile())` 插入该警告。
- 不建议在 OHOS 上硬塞未验证的 `bwrap` 到 PATH 来压掉 warning。更合理的方向是把 Linux sandbox/bwrap 探测限定为普通 Linux：`all(target_os = "linux", not(target_env = "ohos"))`，OHOS 默认不选择 `LinuxSeccomp` 平台 sandbox。
- 已在远端源码新增未提交补丁：
  - `codex-rs/arg0/src/lib.rs`：`codex_linux_sandbox_exe` 只在 `all(target_os = "linux", not(target_env = "ohos"))` 时设置。
  - `codex-rs/sandboxing/src/lib.rs`：bwrap 模块和 `system_bwrap_warning` 导出只用于普通 Linux；非普通 Linux 包括 OHOS 时 `system_bwrap_warning()` 返回 `None`，`find_system_bwrap_in_path()` 返回 `None` 作为编译 stub。
  - `codex-rs/sandboxing/src/manager.rs`：`get_platform_sandbox()` 不再在 OHOS 上返回 `LinuxSeccomp`，WSL/bubblewrap 支持检查也收窄到普通 Linux。
- 第一次增量构建失败在 `codex-linux-sandbox/src/launcher.rs` 的 `use codex_sandboxing::find_system_bwrap_in_path;`，因为该符号被 cfg 掉；补 `find_system_bwrap_in_path() -> None` stub 后已重启 detached build。
- 2026-05-23 02:16 CST 当前状态：远端 detached build 仍在运行，旧 status 仍是 `rc=101 finished_at=Sat May 23 01:59:51 CST 2026`，新日志开头为 `detached-build-start Sat May 23 02:00:32 CST 2026`，已通过之前的 import 错误并正在重编 `codex-core`、`codex-app-server`、`codex-tui`、`codex-exec` 等。
- 后续恢复时先检查 `~/Claude/codex-ohos/logs/build-codex-cli.status`、日志尾部、`cargo`/`rustc` 进程和目标二进制时间戳。不要直接重新启动构建，也不要继续等待前先忽略当前状态。

## 2026-05-23 第二批 sandbox 补丁验证结果

- 2026-05-23 03:32 CST：02:00 启动的 detached release build 完成，`build-codex-cli.status` 写入 `rc=0 finished_at=Sat May 23 03:32:46 CST 2026`，目标二进制约 127M。
- 2026-05-23 03:46 CST：最终 `target/release/codex` 已重新自签名，`codex --version` 输出 `codex-cli 0.0.0`，`codex debug models --bundled` 和 `codex --help` 均通过。
- 新构建 TUI 启动捕获中未再出现 `Codex could not find bubblewrap on PATH`，panic 计数也为 0，说明把 bwrap/platform sandbox 条件收窄到 `all(target_os = "linux", not(target_env = "ohos"))` 已达到压掉 OHOS bubblewrap warning 的目标。
- 远端第二批补丁已提交并推送到 `git@github.com:chenjh16/codex.git` 的 `ohos` 分支，commit 为 `8dbdc6d Disable Linux sandbox probing on HarmonyOS`。远端 `git status -sb` 显示干净。
- 新构建后的 `codex exec "Return exactly: pong-after-sandbox"` 触发 provider `429 Too Many Requests`；这属于当前测试 provider 限流，不能单独作为 CLI 回归失败结论。待限流恢复后仍需重跑 API smoke。

## 2026-05-23 TUI 自动化新阻塞

- `expect` + `ssh -tt` + `--no-alt-screen` 可以捕获 TUI 启动输出，但多次只看到终端控制序列和逐字符启动 tip，例如 `ESC[>4;0m`、`ESC[>7u`、OSC 10/11 颜色查询以及 `Tip: New Build faster with Codex.`。
- 发送 prompt 或 `/quit` 后没有可靠进入输入框，也没有正常退出；远端会留下 `codex --no-alt-screen ... -C ~/Claude/codex-e2e-work` 测试进程。已按精确命令行清理这些孤儿测试进程，避免误伤其他远端任务。
- 已尝试在 expect 中设置 `stty rows 24 columns 80`，也尝试模拟 OSC 10/11 前景/背景色响应；仍未获得完整 TUI e2e 通过证据。
- 后续不要重复同一类 expect 脚本撞结果。更有价值的下一步是用更真实的 PTY（例如直接交互式 SSH session、`script`/terminal emulator，或能响应 xterm 查询的 pty harness）确认这是自动化伪终端缺协议响应，还是 HarmonyOS SSH PTY 下 TUI 输入事件读取/退出路径本身有问题。
- 已用真实 PTY 会话复测：TUI 能渲染完整启动界面、加载 `gpt-5.4-mini`、接收 prompt、提交后进入 `Working` 状态，并在 provider 限流时显示 `exceeded retry limit, last status: 429 Too Many Requests`。这说明 TUI 输入和错误展示路径可用，当前未能完成成功模型响应主要受 provider 限流影响。
- 真实 PTY 中 `/quit` 可正常退出，退出前显示 `Shutting down...`，SSH 连接随后关闭。观察到文本输入后往往需要额外一次 Return 才提交，这一点应反馈到后续 expect harness 设计中。
- 远端 provider 配置已恢复到 secret-safe 形态：`base_url` 指向 OpenAI-compatible `/v1` endpoint，`env_key = "SUBAPI_ELIAS_API_KEY"`，远端 config 不保存 key 值。通过 SSH stdin 临时注入本地环境变量后，`codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Return exactly: env-ok"` 成功返回 `env-ok`。
- 最终 TUI 两轮 e2e 使用内存型 PTY harness 完成，不写日志文件，输出前按 `sk-...` 形态脱敏。结果：
  - `bubblewrap_warning_count=0`
  - `panic_count=0`
  - `error_count=0`
  - `dcba_seen=yes`
  - `zyxw_seen=yes`
  - `completed_two_rounds=yes`
  - `shutdown_seen=yes`
- 同一 harness 继续覆盖 `TERM=screen-256color` 和 `TERM=vt100`，两者均完成两轮 prompt，响应包含 `hgfe` 和 `lkji`，warning/panic/error 计数均为 0，并正常 `/quit` 退出。
- 注意：不要用 `expect log_file` 搭配 `send $env(SUBAPI_ELIAS_API_KEY)` 传 key；该方式会记录发送内容。当前会话中曾因错误 harness 暴露测试 key，已删除本地临时日志，但仍建议轮换该测试 key。

## 2026-05-23 用户目录安装结果

- 已创建 `/storage/Users/currentUser/.local/bin/codex`。
- wrapper 内容保持极简：

```sh
#!/bin/sh
set -eu
. "$HOME/Claude/codex-ohos/env.sh"
export CODEX_HOME="$HOME/.codex"
exec "$HOME/Claude/codex-openai/codex-rs/target/release/codex" "$@"
```

- 远端 zsh 验证通过：
  - `export PATH="$HOME/.local/bin:$PATH"; command -v codex` 返回 `/storage/Users/currentUser/.local/bin/codex`
  - `codex --version` 返回 `codex-cli 0.0.0`
  - `codex --help` 可正常输出帮助内容
- 经验：安装 wrapper 不应复制二进制，避免后续签名/构建更新后 PATH 入口指向旧文件；通过 exec release binary 可以复用同一签名产物。

## 2026-05-23 Agent 能力专项 smoke

本轮没有修改 Rust 代码，优先按“Agent 能力优先，安全/沙箱后置”的原则做远端验收。测试均通过 `/usr/bin/zsh -lc` 或隔离 `CODEX_HOME` 执行，API key 只从本地环境经 stdin 临时注入，不写入远端配置。

### Code Mode

- `codex features list` 显示 `code_mode` 和 `code_mode_only` 仍是 under development false。
- 只启用 `--enable code_mode` 时，模型可能退回普通 shell 工具并成功运行 Node/JS 命令；这不能证明 Code Mode 可用。
- 使用 `--enable code_mode --enable code_mode_only` 才会走真实 Code Mode 路径。HarmonyOS 当前返回：

```text
Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.
```

结论：OHOS Code Mode stub 行为符合预期，但高级 JS runtime、nested tool orchestration 和相关工具组合不可用。

### Linux sandbox

- 主 CLI/TUI 不再误探测 bubblewrap，也不再默认进入 LinuxSeccomp。
- 显式运行 `codex sandbox linux /data/service/hnp/bin/true` 仍会 panic：

```text
codex-linux-sandbox executable not found
```

结论：功能主链路已主动降级，但 sandbox 子命令仍需后续改成 OHOS 上的 graceful unsupported，而不是 panic。

### 多 Agent

最小端到端 smoke 通过：

- 主 Agent spawn 一个子 Agent。
- 子 Agent 返回 `FINAL_FROM_CHILD`。
- 主 Agent `wait_agent` 收到 completed。
- 主 Agent `close_agent` 成功关闭子 Agent。
- 最终输出为 `MULTI_AGENT_OK FINAL_FROM_CHILD`。

证据 rollout：

```text
/storage/Users/currentUser/.codex/sessions/2026/05/23/rollout-2026-05-23T17-45-52-019e543a-119f-7e71-a661-b97a472c6e75.jsonl
```

注意：第一次 spawn 使用了不合法的 `fork_context + agent_type` 组合，Codex 返回明确约束错误；模型随后以最小参数重试成功。这说明参数校验和错误恢复路径也有基本证据。

未覆盖：TUI `/agent` picker、并发多个子 Agent、`send_input`、`resume_agent`、重启后 graph store open/closed 状态。

### MCP client/server 和真实 DeepWiki MCP

本地 MCP 管理通过：

- 隔离 `CODEX_HOME` 下 `codex mcp add/list/remove` 可管理 stdio server。
- 真实 `~/.codex/config.toml` 已保持不配置 MCP server，避免临时测试污染日常会话。

Codex MCP server 通过：

- `codex mcp-server` 使用 newline JSON-RPC 可完成 `initialize` 和 `tools/list`。
- 暴露工具包括 `codex` 和 `codex-reply`。
- Content-Length framing 当前未跑通，后续 harness 应按当前实现使用 newline JSON-RPC。

真实 DeepWiki streamable HTTP MCP 通过：

- `https://mcp.deepwiki.com/` 是 HTML landing page，不是 MCP endpoint。
- DeepWiki 文档/页面提示的正确 endpoint 是 `https://mcp.deepwiki.com/mcp`。
- 隔离 `CODEX_HOME` 配置该 endpoint 后，Agent 实际调用 `deepwiki/ask_question` 并成功返回 `openai/codex` 摘要。
- `https://developers.openai.com/mcp` 直接访问返回 403，本轮不作为可用 MCP endpoint。

未覆盖：MCP OAuth、resource/list 真实资源读取、streamable HTTP 认证、MCP tool approval 交互和错误 UI。

### Plugin / skill / connector

- `codex plugin list` 可运行并会初始化 marketplace/cache。
- `codex plugin marketplace list` 能看到 `openai-curated`。
- 隔离/临时环境中安装 `github@openai-curated` 成功。
- `codex debug prompt-input` 能看到 GitHub plugin skills 暴露给 Agent。

注意：本轮安装 GitHub plugin 时，远端真实 `~/.codex/plugins/cache/openai-curated/github/...` 已出现 installed/enabled 状态；这属于插件缓存/安装副作用，应在后续长期使用前确认是否保留。connector auth、GitHub tool invocation、request-plugin-install 和 external agent config migration 尚未验收。

### App server / remote-control / exec-server

- `codex app-server daemon version` 不能连接默认 control socket。
- `codex app-server --listen unix://...` 报 `Operation not permitted`，说明 OHOS 当前 Unix socket 路径有权限或平台限制。
- `codex app-server --listen ws://127.0.0.1:45678` 可启动并运行到 timeout。
- `codex remote-control start --json` 失败，原因是 managed standalone Codex install 不存在于 `~/.codex/packages/standalone/current/codex`。
- `codex remote-control stop --json` 返回 `notRunning`。
- `codex exec-server --listen stdio://` 可干净退出。
- `codex exec-server --listen ws://127.0.0.1:45679` 可启动并打印 `ws://127.0.0.1:45679`，随后运行到 timeout。

结论：服务型能力不是全不可用，但默认 Unix socket/standalone layout 路径不适合直接宣称可用。下一步应优先验证 ws 模式和 standalone installer 布局。

### Cloud task / Agent identity / GUI

- `codex login status` 为 `Not logged in`。
- `codex cloud list/status` 要求先 `codex login`。
- `codex exec-server --remote ... --use-agent-identity-auth` 要求 `CODEX_ACCESS_TOKEN`。
- 远端 SSH 环境未找到 `open`、`xdg-open`、`google-chrome`、`chromium`、`firefox`。
- `debug prompt-input` 未显示 Browser Use / Computer Use 工具暴露在远端会话。

结论：cloud task 和 Agent identity 目前受 ChatGPT 登录或 token 阻塞；浏览器/桌面/GUI 插件不能在 SSH 验证环境中默认视为可用。

### Harness 和配置卫生

- 当前 TUI 两轮 e2e 仍是内存型 PTY harness 的经验结果，尚未固化进仓库脚本。
- 后续脚本必须满足：key 不落盘、不出现在进程参数、输出前脱敏、不使用 `expect log_file` 记录 `send` 内容。
- 本轮真实 MCP 测试曾临时把 `deepwiki` 和 `openai_docs` 写入真实 `~/.codex/config.toml`；已执行 `codex mcp remove deepwiki` 和 `codex mcp remove openai_docs` 清理。当前 `codex mcp list` 为 `No MCP servers configured yet`。

## 2026-05-23 最终配置审计结果

- 最终审计发现远端 `~/.codex/config.toml` 曾残留旧 `experimental_bearer_token` 明文配置，与文档期望的 secret-safe 状态不一致。
- 已立即删除 `experimental_bearer_token`，启用 `env_key = "SUBAPI_ELIAS_API_KEY"`。
- 复扫结果：远端 config 中 `base_url`、`wire_api`、`env_key` 存在，`experimental_bearer_token` 不存在，`sk-...` 形态密钥扫描为 clean。
- 因为明文 key 曾短暂存在于远端配置和审计输出中，建议轮换该测试 key 后再长期使用。

## 2026-05-23 Agent 能力分析结论

- 当前 Codex 源码已具备多层 Agent 能力：单 Agent CLI/TUI、工具运行时、MCP client/server、plugin/skill discovery、多 Agent spawn/send/wait/close/resume、Agent graph store、Agent identity、app-server/remote-control、exec-server、cloud task 和 Code Mode。
- HarmonyOS 当前已经验证单 Agent CLI/TUI 主链路，并完成多 Agent 最小 `spawn_agent -> wait_agent -> close_agent`、MCP add/list/remove、Codex MCP server newline JSON-RPC、真实 DeepWiki streamable HTTP MCP、plugin marketplace/install/skill 暴露、app-server/exec-server 基础启动路径的专项 smoke。
- 仍未完成的是 TUI `/agent` picker、并发多 Agent、`send_input`/`resume_agent`、graph store 跨进程持久化、MCP OAuth/resource/approval、connector auth/tool invocation、remote-control standalone layout、cloud task 和 Agent identity。
- Code Mode 是明确功能缺失：OHOS build 使用 stub，返回 `Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.`。
- Linux sandbox 已按 OHOS 适配主动降级，避免误探测 bubblewrap；因此 HarmonyOS 上不能宣称具备普通 Linux 的 bwrap/seccomp sandbox 安全边界。显式 `codex sandbox linux` 子命令仍会 panic 为 `codex-linux-sandbox executable not found`，后续应改成 OHOS unsupported 提示。
- 详细分析见 `docs/codex-agent-capability-analysis.md`。
