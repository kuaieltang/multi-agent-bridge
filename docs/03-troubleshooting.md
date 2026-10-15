# 03 · 故障排查

## 一、症状速查表

| 现象 | 根本原因 | 解决 |
|---|---|---|
| 调用任何 Agent 都返回 `Reconnecting... waiting for network` 或直接失败 | **DSH 沙箱内子进程无法建立 TLS**（`SEC_E_NO_CREDENTIALS`） | 走中继（沙箱外），或对该次调用提权 |
| `EPERM: operation not permitted, mkdir/write ...` 指向 `C:\Users\...` | 被调 CLI 想写自己的家目录，被 DSH 文件沙箱拒绝 | 用 `-Native`（走中继，沙箱外）或隔离模式重定向配置目录 |
| `Authentication required. Please use /login command` | 该 CLI 未登录 | 见 docs/04 的登录方式 |
| `Not logged in. Run \`qoderclicn login\`` | 千问办公 CLI 未登录 | `qoderclicn login`（必须在沙箱外） |
| `Cannot find module '../dist/codebuddy'` | WorkBuddy **内置 CLI 缺交互式产物** | 用官方原生构建 `C:\Users\TANG\AppData\Local\codebuddy\bin\codebuddy.exe`（见 docs/04） |
| `rejected: blocked by policy` | 被调 CLI **自带沙箱**拒绝了命令 | Codex → `-s danger-full-access`；CodeBuddy → `--permission-mode bypassPermissions -y` |
| 调用卡住很久、最后 `[stdout 未在 10s 内关闭...]` | Codex 的子进程占住了 stdout 管道 | 已内置处理：有界读取 + `taskkill /T`；答案靠 `-o` 落盘获取 |
| 中继启动报 `EADDRINUSE` | 已有中继在跑 | 无需处理；或先结束旧进程 |
| `curl: (6) Could not resolve host: <token>` | PowerShell 把带空格的 curl 参数拆坏了 | 参数中不要含空格：`-Hx-bridge-token:$token` |
| `{"error":"bad json"}` | JSON 请求体被 PowerShell 吃掉引号 | 用 `--data-binary '@文件'`，不要用 `--data '{...}'` |
| 中继返回 `{"error":"need agent + prompt"}` | 探测类命令没传 `prompt` | 传占位值 `"x"` |

## 二、四个核心坑（设计层面的原因）

### 坑 1：沙箱内子进程无法建立 TLS
**证据**：沙箱内 `curl.exe https://api.deepseek.com` → `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`；
同一个 curl 在提权后 → `HTTP 401`（说明网络与 TLS 都正常）。
对 `https://www.baidu.com` 同样失败，因此**不是** DNS、不是域名封锁、也不是断网，而是沙箱令牌拿不到 TLS 凭据。

**结论**：任何需要联网的 Agent CLI 都无法在 DSH 沙箱内工作。→ **中继是唯一能实现"零审批"的方案**。

### 坑 2：`powershell -File` 的参数解析
以 `-` 开头的值（如 `-d`）会被当成参数名，无法作为 `-ExtraArgs` 的值传递。
**解决**：用环境变量 `BRIDGE_EXTRA_ARGS='-d'`。

### 坑 3：输出管道被孙进程占用
Codex 会派生后台进程并持有 stdout 句柄，导致 `ReadToEnd()` **永久阻塞**（实测卡死 210 秒以上）。
**解决**：`agents.ps1` 改为「有界读取 10 秒 + `taskkill /F /T` 杀进程树」，Codex 另用 `-o <file>` 把最终回答落盘读取。

### 坑 4：`qoderclicn` 的 `--tools` 是可变参数
`--tools ""` 会把后面的 query 一起吞掉，现象是它回 **"It looks like your message came through empty"**。
**解决**：在 query 前加 `--` 分隔符。

## 三、恢复操作

| 要恢复什么 | 操作 |
|---|---|
| **中继挂了** | 已配置**开机自启**；手动恢复：双击 `scripts/start-relay.cmd`；确认：`http://127.0.0.1:18791/` 应返回 **404** |
| **凭据过期** | CodeBuddy：`scripts/login-codebuddy.cmd` 或让 DSH 拉起 Web UI 登录；千问办公：`scripts/login-qoder.cmd` |
| **换了电脑 / 路径变了** | 按 `docs/05-environment.md` 的清单核对并修改 `agents.ps1` 顶部的路径常量 |
| **想停掉中继 / 取消自启** | 双击 `scripts/stop-relay.cmd` 立即停止；删除 Startup 里的 `agent-bridge-relay.vbs` 即永久取消自启 |
| **想看某次调用的完整输出** | 每次调用的日志都在 `out/` 目录，文件名形如 `codex-20261014-115358.log` |
