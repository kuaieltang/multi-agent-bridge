# 02 · 使用手册

## 一、最简用法：直接跟 DSH 说话

不需要你敲任何命令。参考说法：

| 你说 | 效果 |
|---|---|
| "让 Codex 写个校验手机号的正则" | 单一指派 |
| "三家各写一版方案，你来评分挑最好的" | 并行 fan-out + 交叉评审 |
| "用 CodeBuddy 把这段中文改成商务语气" | 指定 Agent + 指定任务 |
| "让千问办公总结这份文档，快一点" | 选最快的 Qoder |
| "让 Codex 实际改一下这个文件（允许写）" | DSH 会先跟你确认再放开写权限 |

## 二、中继 API（DSH 内部使用，你也可以自己调）

**POST** `http://127.0.0.1:18791/run`
请求头：`x-bridge-token: <relay/token.txt 的内容>`

请求体字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| `agent` | ✅ | `codex` / `codebuddy` / `qoder` / `qwenwork` / `qoder-models` / `qwenwork-version` |
| `prompt` | ✅ | 任务文本（探测类命令传占位值 `"x"` 即可） |
| `workdir` | | 工作目录，默认 DSH 当前目录 |
| `timeoutSec` | | 硬超时，默认 300 |
| `native` | | `true` = 用真实家目录/登录态（CodeBuddy、Qoder 必须用） |
| `allowTools` | | `true` = 放开工具执行（危险档位） |
| `fullAccess` | | Codex 专用，等同 `-s danger-full-access` |
| `extraArgs` | | 追加参数，例如 `"-s danger-full-access"` |

响应（JSON）：`exitCode`、`seconds`、`logFile`、`log`（完整输出）、`stdoutTail`、`stderrTail`。

示例（PowerShell）：

```powershell
$dir = 'D:\document\deepseek-harness\multi-agent\scripts\relay'
$token = (Get-Content "$dir\token.txt" -Raw).Trim()
curl.exe -sS -X POST http://127.0.0.1:18791/run `
  -H "x-bridge-token: $token" -H 'Content-Type: application/json; charset=utf-8' `
  --data-binary '@request.json'
```

> ⚠️ PowerShell 会把 `--data` 里 JSON 的引号吃掉，**务必用 `--data-binary '@文件'`**。

## 三、直连用法（不依赖中继，但每次要审批）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\agents.ps1 `
    -Agent codebuddy -Prompt "任务内容" -Native -AllowTools
```

参数：`-Agent`、`-Prompt`、`-WorkDir`、`-TimeoutSec`、`-AllowTools`、`-Native`、`-FullAccess`、`-ExtraArgs`、`-OutFile`、`-Quiet`。

> ⚠️ 以 `-` 开头的值无法通过 `powershell -File` 传递（会被当成参数名），改用环境变量 `BRIDGE_EXTRA_ARGS`。

## 四、并行 fan-out（DSH 常用形态）

DSH 会为每个 Agent 各起一个请求，同时发出、同时收结果，然后对比汇总。
要点：

- 每个 Agent 一个独立的 JSON 请求体文件
- 用 `Start-Process curl.exe` 并行启动时，**参数里不要含空格**（否则会被拆坏）：用 `-Hx-bridge-token:$token`、`-HContent-Type:application/json`、`--data-binary=@文件`
- 不同 Agent 超时差异较大（Qoder 最快、Codex 最慢），按各自情况设置 `timeoutSec`

## 五、每次调用会消耗什么

| Agent | 计费/额度 |
|---|---|
| Codex | 走 `api.deepseek.com`，按量计费（用你 `~/.codex/auth.json` 里的 Key） |
| WorkBuddy | 你 CodeBuddy 账号的额度 |
| 千问办公 | 你的个人免费版额度 |

DSH 会尽量把小任务路由到最省的选项，但**无法替你判断额度余量**。
