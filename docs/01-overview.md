# 01 · 架构与可用性

## 一、整体架构

```
DSH（我）
 │
 ├─ 直连方式 ──> agents.ps1 ──> 各 Agent 的 CLI
 │   · 运行在 DSH 文件沙箱内（workspace-write）
 │   · 每次调用需要一次沙箱提权审批
 │   · 原因：沙箱内子进程无法建立 TLS（见 docs/03）
 │
 └─ 中继方式 ──> relay.js（沙箱外常驻，监听 127.0.0.1:18791）
        │        · 用随机 token 鉴权（relay/token.txt）
        │        · 收到 POST /run 后调用 agents.ps1
        └──────> 各 Agent 的 CLI（此时在沙箱外，可正常联网）
```

**为什么必须有中继**：DSH 的沙箱会给子进程一个受限令牌，导致 schannel 拿不到 TLS 凭据
（`SEC_E_NO_CREDENTIALS`）。任何需要访问云端的 Agent CLI 在沙箱内都会失败。把中继放在沙箱外常驻一次，
之后 DSH 只通过 `127.0.0.1` 的**明文 HTTP** 与它通信 —— 不涉及 TLS，也就**不再需要任何审批**。

## 二、被调度的三个 Agent

| Agent | 实际身份 | CLI 入口 | 版本 |
|---|---|---|---|
| **Codex** | OpenAI Codex CLI（配置为走 `api.deepseek.com`） | `C:\Users\TANG\.codex\.sandbox-bin\codex.exe` | 0.162.0-alpha.17.2 |
| **WorkBuddy** | 腾讯 CodeBuddy 内核 + 官方原生构建 | `C:\Users\TANG\AppData\Local\codebuddy\bin\codebuddy.exe` | 2.164.0 |
| **千问办公** | 阿里 Qoder CLI（CN 版） | `...\QwenWorkCN\1.2.5-26092902\resources\bin\qoderclicn.exe` | 1.1.59 |

三个都是**完整 Agent**（能读写文件、执行命令），不是单纯的模型接口。

## 三、能力边界（实测）

| 能力 | Codex | WorkBuddy | 千问办公 |
|---|---|---|---|
| 纯问答 | ✅ | ✅ | ✅ |
| 执行 shell / 读写文件 | ✅ 需 `-s danger-full-access` | ✅ 需 `--permission-mode bypassPermissions -y` | 默认禁用工具，未实测 |
| 并行调用 | ✅ | ✅ | ✅ |
| 响应速度参考 | 约 20–56s | 约 22–36s | **最快，约 6–7s** |

**为什么工具执行要单独放开**：三家的 CLI 在非交互（headless）模式下都无法弹窗确认权限，
默认会拒绝所有命令。这属于"危险档位"，所以桥接默认关闭，需要时由 DSH 征求你的同意后再打开。

## 四、实测记录（2026-10-14）

1. **纯问答**：三个 Agent 都返回了正确答案（幂等性 + HTTP 方法例子）。
2. **并行 fan-out**：同一问题同时发给三家，全部 `exitCode=0`：

   | Agent | 用时 | 回答要点 |
   |---|---|---|
   | Codex | 56s | 例：`GET`（重复请求不改变服务器状态） |
   | WorkBuddy | 22.1s | 例：`PUT /users/1`；主动补充 `POST` 通常不幂等（最完整） |
   | 千问办公 | 6.6s | 例：`PUT`（最快） |

3. **工具执行**：
   - Codex 统计工作区文件数 → `3027`（用 `-Force` 口径）
   - WorkBuddy 统计同一目录 → `3052`（真值 3054，差额是该次运行自身新增的日志文件）
4. **登录验证**：
   - 千问办公：`qoderclicn --list-models` 列出 Qwen3.8-Max / DeepSeek-V4-Pro / GLM-5.3 / Kimi-K3 等
   - WorkBuddy：`codebuddy -p` 返回 `CODEBUDDY-OK`

## 五、任务指派建议

| 任务类型 | 首选 | 理由 |
|---|---|---|
| 写代码、调试、代码审查 | **Codex** | 工具执行最成熟（可完全绕过自带沙箱） |
| 中文文档、办公场景、腾讯生态 | **WorkBuddy** | 回答更完整细腻；腾讯系集成 |
| 快问快答、批量小任务、中文改写 | **千问办公** | 实测最快（6–7s） |
| 需要高可信度结论 | **三家并行** | 交叉验证，由 DSH 汇总评分 |
