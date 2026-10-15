# 06 · 部署记录与运维速查

> 记录 2026-10-14 完成的正式部署：**迁移到本目录 + 配置开机自启 + 实测验证**。
> **运维时第一个该看的文件就是这篇。**

## 一、最终部署形态

| 项 | 值 |
|---|---|
| 唯一实体 | `D:\document\deepseek-harness\multi-agent`（原 `default-workspace\agent-bridge` 已降级为历史备份，不再维护） |
| 中继 | `scripts\relay\relay.js`，监听 `127.0.0.1:18791` |
| 中继启动方式 | **开机自启**：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\agent-bridge-relay.vbs`（隐藏窗口、脱离 DSH 会话独立运行） |
| 中继日志 | `scripts\relay\relay-autostart.log` |
| token | `scripts\relay\token.txt`（每次启动重新生成；DSH 每次从中读取最新值） |
| 调用日志 | `scripts\out\<agent>-<时间戳>.log` |
| 临时产物 | `scripts\tmp\` |

## 二、运维速查表

| 想做什么 | 怎么做 |
|---|---|
| 确认中继在跑 | 访问 `http://127.0.0.1:18791/` → 返回 **404** 即正常（它只接受 POST `/run`） |
| 停止中继 | 双击 `scripts\stop-relay.cmd` |
| 手动启动（带窗口看日志） | 双击 `scripts\start-relay.cmd` |
| 看自启日志 | `scripts\relay\relay-autostart.log` |
| 永久取消自启 | 删除 Startup 里的 `agent-bridge-relay.vbs` |
| 暂时禁用自启（保留文件） | 把该 vbs 移出 Startup 文件夹即可 |
| 查某次调用的完整输出 | `scripts\out\` 下的对应日志文件 |

## 三、三条注意事项（重要）

### 1. 自启是"登录时启动一次"，不是守护进程
中继中途崩溃**不会**被自动重拉。恢复方式：双击 `scripts\start-relay.cmd`（或重启电脑）。
如果需要"崩了自动重启"，那要另做计划任务（当前未配置）。

### 2. 路径是写死的，移动目录/换机必须同步修改
- `scripts\relay-autostart.vbs`：内含 `node.exe` 与 `relay.js` 的绝对路径
- `scripts\start-relay.cmd`：同上
- `scripts\agents.ps1` 顶部 5 个常量：`$RealCodexHome`、`$WbRoot`、`$QwRoot`、`$CbNative`、`$SystemNode`
- `scripts\login-codebuddy.cmd`、`scripts\login-qoder.cmd`：内含 CLI 绝对路径

### 3. 安全边界
中继等价于给 DSH 一个"本机命令执行入口"（被调 Agent 拥有你当前用户的文件与命令权限）。
- 只监听 `127.0.0.1`，token 每次启动随机生成；
- **不要**把 `scripts\relay\`（含 token）或 `req-*.json` 提交到仓库、发到聊天工具；
- 不需要时用 `scripts\stop-relay.cmd` 关闭，或删除自启 VBS；
- 放开工具执行（`-AllowTools` / `allowTools: true`）前应确认任务可信。

## 四、部署时的实测验证（可复现）

| 验证项 | 结果 |
|---|---|
| 自启脚本本身可用 | 用**同一条** `relay-autostart.vbs` 实际执行，成功拉起中继（隐藏窗口，PID 18064/40460） |
| 中继健康 | `http://127.0.0.1:18791/` → **404** |
| 中继确实运行在新目录 | 自启日志内容：`script=D:\document\deepseek-harness\multi-agent\scripts\agents.ps1` |
| end-to-end 真实调用 | CodeBuddy 返回 `MIGRATION-OK`，10.9s，`exitCode=0`，日志落在 `scripts\out\` |
| 单一实体 | 工作区内的暂存副本已删除，避免出现两份会各自漂移的拷贝 |

> 说明：VBS 的"开机登录时自动执行"这一环无法在会话内直接复现，但**同一条 VBS 已被实际执行过并成功拉起中继**，
> 因此启动链路本身是验证过的；真正的开机场景请在下一次重启登录后按第二节"确认中继在跑"核对一次。

## 五、变更历史

| 日期 | 变更 |
|---|---|
| 2026-10-14 | 打通 Codex / WorkBuddy / 千问办公 三路调用，建立"中继"实现零审批调度 |
| 2026-10-14 | 修复 WorkBuddy：安装官方原生构建 2.164.0 + 通过 Web UI 完成登录（详见 [04-workbuddy-fix.md](04-workbuddy-fix.md)） |
| 2026-10-14 | 资料包迁入本目录成为唯一实体；配置开机自启；端到端实测通过；删除暂存副本 |
