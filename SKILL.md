---
name: multi-agent-bridge
description: "调度本机另外三个 Agent（Codex / WorkBuddy(CodeBuddy) / 千问办公(Qoder)）实际执行任务，并汇总或交叉验证结果。当用户说「让 Codex 做…」「三家各做一版」「用 CodeBuddy / 千问办公…」，或需要多模型交叉验证、需要某个 Agent 的专属能力（写代码、腾讯生态、中文办公文档）时使用。注意：豆包工作无法被调用（无编程接口，见第 7 节）。Delegate tasks to the local Codex / WorkBuddy / Qwen-Office agents through the local relay at 127.0.0.1:18791."
---

# multi-agent-bridge

把任务派给本机上另外三个 Agent，用它们各自的能力与额度干活；本技能负责调用、取回结果、并做交叉验证。

**完整文档**：`D:\document\deepseek-harness\multi-agent\`（README + docs/01~08）。
本文件是可执行的最小操作手册。

## 何时使用

- 用户点名某个 Agent：「让 Codex 写…」「用千问办公总结…」
- 用户要多家对比：「三家各写一版，你来评分」
- 需要交叉验证提高可信度
- 需要某个 Agent 的专属优势（代码工具链 / 腾讯生态 / 中文办公 / 最快响应）

**不能调用豆包工作**（无 CLI、无本地 API），原因与替代方案见第 7 节。

## 0. 前提检查与中继恢复（重要）

中继必须活着。**默认由开机自启拉起**（用户登录时由 Startup 里的 VBS 启动，独立于 DSH）。检查：

```powershell
# 返回 404 即正常（中继只接受 POST /run）
(& curl.exe -sS -o NUL -w "%{http_code}" --max-time 8 http://127.0.0.1:18791/ 2>&1) -join ''
```

**中继连不上时，按下面顺序处理：**

1. **首选：请用户双击** `D:\document\deepseek-harness\multi-agent\scripts\start-relay.cmd`
   （在用户自己的终端里启动＝完全脱离 DSH，最稳）
2. **或由 DSH 以「后台任务」方式启动**：`node <...>\relay\relay.js`，用后台运行（managed job），
   这样它在本会话内持续存活。
3. ⚠️ **不要用一次性命令启动它**（哪怕是提权的一次性命令）：DSH 在该命令结束后会回收进程树，
   中继会在几十分钟内悄悄消失 —— 这是本项目踩过的真实坑（2026-10-14 实测）。

- **token 每次都从文件重新读**，不要跨调用缓存（中继每次启动都会重新生成）：

```powershell
$token = (Get-Content 'D:\document\deepseek-harness\multi-agent\scripts\relay\token.txt' -Raw).Trim()
```

## 1. 怎么调用

`POST http://127.0.0.1:18791/run`，请求头 `x-bridge-token: <token>`，
请求体是 **JSON 文件**（必须用 `--data-binary '@文件'`——PowerShell 直接传 JSON 字符串会把引号吃掉）。

| 字段 | 必填 | 说明 |
|---|---|---|
| `agent` | ✅ | `codex` \| `codebuddy` \| `qoder`；另有探测用 `qoder-models`、`qwenwork-version` |
| `prompt` | ✅ | 任务文本；探测类命令也要传占位值 `"x"` |
| `workdir` | | 工作目录，默认当前目录 |
| `timeoutSec` | | 硬超时，默认 300（Codex 常 20–60s，Qoder 约 6–10s） |
| `native` | | `true` = 用真实登录态。**CodeBuddy / Qoder 必须 true**；Codex 用 false（隔离模式，密钥只注入环境变量） |
| `allowTools` | | `true` = 放开工具执行（**危险档位**，见第 4 节） |
| `fullAccess` | | 仅 Codex，等同 `-s danger-full-access` |
| `extraArgs` | | 追加参数，如 `"-s danger-full-access"` |

响应 JSON：`exitCode`、`seconds`、`logFile`、`log`（完整输出）。

标准写法：

```powershell
$relay = 'D:\document\deepseek-harness\multi-agent\scripts\relay'
$token = (Get-Content "$relay\token.txt" -Raw).Trim()
$body  = '{"agent":"codebuddy","prompt":"把这段话改成商务语气：……","native":true,"timeoutSec":200}'
[System.IO.File]::WriteAllText("$env:TEMP\req.json", $body, (New-Object System.Text.UTF8Encoding($false)))
$resp = & curl.exe -sS -X POST 'http://127.0.0.1:18791/run' `
    -H "x-bridge-token: $token" -H 'Content-Type: application/json; charset=utf-8' `
    --data-binary "@$env:TEMP\req.json" --max-time 240 2>&1
($resp | Out-String | ConvertFrom-Json).log
```

> 用 `write` 工具生成 JSON 文件同样可行（UTF-8 无 BOM），比手拼字符串更安全。

## 2. 选哪个 Agent

| 任务类型 | 首选 | 说明 |
|---|---|---|
| 写代码 / 调试 / 代码审查 | **codex** | 工具执行最成熟；默认隔离模式，不碰真实家目录 |
| 中文文档 / 办公 / 腾讯生态 | **codebuddy** | 回答更完整细腻；必须 `native:true` |
| 快问快答 / 批量小任务 / 中文改写 | **qoder** | 实测最快（6–10s）；必须 `native:true` |
| 需要高可信度结论 | **三家并行** | 交叉验证，由你对比汇总 |

## 3. 并行 fan-out

- 每个 Agent 一个独立的 JSON body 文件
- 用 `Start-Process curl.exe` 并行时**参数里不要含空格**（会被拆坏）：
  写 `-Hx-bridge-token:$token`、`-HContent-Type:application/json`、`--data-binary=@$bf`
- 超时按各自情况设，不要共用一个值

## 4. 工具执行（危险档位，必须先问用户）

默认只读/禁工具。当任务确实需要被调 Agent 改文件或执行命令时：

- **Codex** → `"allowTools": true`（等价 `-s danger-full-access`，绕过它自带沙箱）
- **CodeBuddy** → `"allowTools": true`（等价 `--permission-mode bypassPermissions -y`）
- **Qoder** → 默认禁工具；需要时同样传 `allowTools`

这三档都等于**把本机文件与命令权限交给另一个 Agent**，因此：
先向用户说明并取得同意，再放开；并尽量给独立工作目录，避免多个 Agent 同时改同一个仓库。

## 5. 额度

每次调用消耗对应产品的额度：Codex 走 `api.deepseek.com` 按量计费；
WorkBuddy 花 CodeBuddy 账号额度；千问办公是个人免费版。
用户没要求时，不要无谓地三家齐发。

## 6. 出错时

| 症状 | 处理 |
|---|---|
| `{"error":"need agent + prompt"}` | 探测类命令也要传 `prompt`（占位 `"x"`） |
| `{"error":"bad json"}` | 改用 `--data-binary '@文件'`，别用 `--data '{...}'` |
| `curl: (6) Could not resolve host: <token>` | `Start-Process` 的参数含空格被拆开了 |
| `Authentication required` / `Not logged in` | 该 Agent 登录过期：CodeBuddy 走 Web UI 登录，Qoder 跑 `qoderclicn login` |
| `Reconnecting... waiting for network` | 中继跑在沙箱内了；必须沙箱外（见第 0 节） |
| 连接被拒 | 中继没跑，见第 0 节 |

完整排查表：`D:\document\deepseek-harness\multi-agent\docs\03-troubleshooting.md`

## 7. 暂不支持：豆包工作（Doubao Work）

**结论：豆包工作无法被本技能调用**，它没有可编程入口。已核实（2026-10-14）：

| 检查 | 结果 |
|---|---|
| CLI 可执行文件 | ❌ 无（安装目录只有 helper 与代理进程） |
| headless / print 模式 | ❌ 无 |
| 本地 HTTP API | ❌ 运行时 10 个 `DoubaoWork` 进程都不监听任何本地端口 |
| 调试端口 | ❌ 未发现 |
| 对外 MCP server | ❌ 只有 `mcp_helper.dll`（它作为 MCP 客户端消费工具） |

它是 Chromium + 字节 Lark 组件的**纯 GUI 应用**（`D:\Program Files\DoubaoWork\`）。
它自身反而具备 agent 能力：`agent_mode\workspace\.skills` 有大量内置技能，还有
`sdks\aha_cua`（计算机操作）与沙箱终端 —— 但这些都是**给人在界面里用**的。

**替代方案（按可靠性排序）**：

1. **反向集成（推荐）**：给它写一个技能，让*它*通过本中继调用 Codex / WorkBuddy / 千问办公。
   它的 `.user_skills` 目录为空且可写，技能可带脚本 → 可以 curl 中继。效果是"在豆包工作里也能用上那三个 Agent"。
   详见 `docs/08-doubao-work.md`。
2. GUI 自动化：脆弱（需前台、无法可靠读回结果），**不要当可靠通道**。
3. 深链 `doubaowork://`：只能唤起应用，没有返回值通道，不构成调用。

**如果将来它开放了 CLI/API**：按 `docs/07-skill.md` 的步骤，在 `scripts\agents.ps1` 加一个分支、
在本技能第 1/2 节各加一行即可。
