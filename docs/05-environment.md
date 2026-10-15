# 05 · 环境清单与恢复检查表

## 一、三个 Agent 的关键路径

### Codex
| 项 | 值 |
|---|---|
| CLI | `C:\Users\TANG\.codex\.sandbox-bin\codex.exe`（0.162.0-alpha.17.2） |
| 配置 | `C:\Users\TANG\.codex\config.toml`（provider=custom → `https://api.deepseek.com`，model=`deepseek-flash`） |
| 凭据 | `C:\Users\TANG\.codex\auth.json`（字段 `OPENAI_API_KEY`） |
| 桥接隔离 home | `<包目录>\home\codex`（`CODEX_HOME`） |
| 调用模式 | **isolated**（密钥只从真实 auth.json 读入后注入环境变量，不复制文件） |
| 工具执行 | `-s danger-full-access`（`-AllowTools` 或 `-FullAccess`） |

### WorkBuddy（CodeBuddy）
| 项 | 值 |
|---|---|
| **原生构建（桥接首选）** | `C:\Users\TANG\AppData\Local\codebuddy\bin\codebuddy.exe`（2.164.0，自包含 142.7 MB） |
| 内置 CLI（回退） | `D:\Users\TANG\AppData\Local\Programs\WorkBuddy\resources\app.asar.unpacked\cli\bin\codebuddy`（genie 5.7.7，**缺 TUI 产物**） |
| 凭据目录 | `C:\Users\TANG\.codebuddy`（含 `settings.json`、`agent-home/`） |
| 登录方式 | `codebuddy.exe --serve --open --port 57450` → 浏览器完成 SSO |
| 调用模式 | **native**（登录态在真实家目录） |
| 工具执行 | `--permission-mode bypassPermissions -y` |

### 千问办公（Qoder）
| 项 | 值 |
|---|---|
| CLI | `D:\Users\TANG\AppData\Local\Programs\QwenWorkCN\1.2.5-26092902\resources\bin\qoderclicn.exe`（1.1.59） |
| 服务 CLI | 同目录 `qwenwork-win32-x64.exe`（0.1.0） |
| 凭据 | `C:\Users\TANG\.qoder-cn\.auth\user` |
| 登录方式 | `qoderclicn login`（沙箱外） |
| 调用模式 | **native** |
| 工具执行 | 默认 `--tools ""` 禁用；需要时加 `-AllowTools` |

## 二、运行时组件

| 组件 | 位置 / 端口 | 说明 |
|---|---|---|
| 中继 | `scripts/relay/relay.js`，监听 `127.0.0.1:18791` | 零审批调用的入口；**同一时间只能跑一个** |
| 中继自启入口 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\agent-bridge-relay.vbs` | 登录时**隐藏启动**中继；日志写 `scripts\relay\relay-autostart.log` |
| 中继 token | `relay/token.txt` | 每次启动随机重新生成 |
| 调度器 | `agents.ps1` | 唯一逻辑来源，中继与直连都调用它 |
| 调用日志 | `out/` | 形如 `codex-20261014-115358.log` |
| 临时产物 | `tmp/` | Codex 的 `-o` 最终回答落盘等 |
| CodeBuddy Web UI | `127.0.0.1:57450` | 登录用；登录完成后可以关闭 |

## 二·补、中继的启停与自启管理

| 操作 | 方法 |
|---|---|
| 开机自动启动 | 已启用：Startup 文件夹里的 `agent-bridge-relay.vbs`；**删除该文件即取消自启** |
| 手动启动 | 双击 `scripts\start-relay.cmd`（有窗口，能直接看到日志） |
| 停止 | 双击 `scripts\stop-relay.cmd` |
| 看日志 | `scripts\relay\relay-autostart.log`（自启方式）或 `start-relay.cmd` 的窗口 |
| 确认在跑 | 访问 `http://127.0.0.1:18791/` 返回 **404** 即正常（它只接受 POST /run） |

> · 中继每次启动都会重新生成 `relay\token.txt`，DSH 每次都从该文件读取当前 token。
> · 改了 `relay\relay.js` 需要重启中继才生效；改了 `agents.ps1` **立即生效**（每次调用都会重新执行）。
> · 自启的 VBS 里写死了 node 与 relay.js 的绝对路径；若换了安装位置，需要同步修改该 VBS 和 `start-relay.cmd`。

## 三、换机 / 重装恢复检查表

1. **装齐三个 Agent**：Codex CLI、WorkBuddy 桌面端、千问办公。
2. **修 WorkBuddy CLI**：`CODEBUDDY_FORCE_LITE_WB_BUNDLE=1` + `codebuddy install`（见 docs/04）。若新版本的 WorkBuddy 已经自带 TUI 产物，可跳过。
3. **逐个登录**：Codex（配置 `auth.json`）、WorkBuddy（Web UI 登录）、千问办公（`qoderclicn login`）。
4. **核对 `agents.ps1` 顶部的路径常量**：`$RealCodexHome`、`$WbRoot`、`$QwRoot`、`$CbNative`、`$SystemNode`。这些是硬编码的，换机/换版本号就要改。
5. **启动中继**：`scripts/start-relay.cmd`。
6. **验证三连**：
   ```powershell
   # 1) 中继活着（404 = 正常）
   curl.exe -sS -o NUL -w "%{http_code}" http://127.0.0.1:18791/
   # 2) 千问办公登录态（应列出模型）
   #    {"agent":"qoder-models","prompt":"x","native":true}
   # 3) CodeBuddy 登录态（应回 CODEBUDDY-OK）
   #    {"agent":"codebuddy","prompt":"只输出 CODEBUDDY-OK","native":true}
   ```

## 四、安全注意事项

- 中继只监听 `127.0.0.1`，且每次启动生成随机 token；但**它能在你机器上执行任意 Agent 任务**，不要把这个 token 泄露或转发。
- `relay/` 目录下的 `req-*.json`、`token.txt`、`gw-login.json` 属于本机运行态文件，含本机口令，**不要提交到代码仓库或分享**。
- 各 Agent 的凭据文件（`~/.codex/auth.json`、`~/.codebuddy/settings.json`、`~/.qoder-cn/.auth/`）都留在各自的真实家目录；
  桥接在 isolated 模式只通过环境变量注入 Codex 的 Key，不复制密钥文件。
- 放开工具执行（`-AllowTools`）等于让被调 Agent 拥有你当前用户的文件与命令权限，**只在可信任务中开启**。
