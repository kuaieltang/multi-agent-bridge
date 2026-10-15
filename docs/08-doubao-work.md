# 08 · 豆包工作为什么没有接进来（调查记录）

> 2026-10-14 调查。起因：要求把「豆包工作」也作为可调度 Agent 接进 `multi-agent-bridge`。
> **结论：做不到** —— 它没有任何可编程入口。本文记录证据与替代方案，避免以后重复调查。

## 一、环境事实

| 项 | 值 |
|---|---|
| 名称 / 注册版本 | 豆包工作 `2.25.18`（内核 manifest 显示 `2.32.8`） |
| 安装位置 | `D:\Program Files\DoubaoWork\`（主程序 `app\DoubaoWork.exe`） |
| 技术栈 | Chromium + 字节 Lark/飞书 组件（`liblark.dll` 162 MB、`DoubaoWork.dll` 307 MB） |
| 用户数据 | `%LOCALAPPDATA%\DoubaoWork\User Data\`；用户配置 `C:\Users\TANG\DoubaoWork\` |
| 它自己的 agent | `...\User Data\Default\.doubaowork\agent_mode\workspace\`，内含 `.skills`（大量 `doubao-*` 内置技能）、`.user_skills`（当前为空）、`experience` |
| 自带自动化能力 | `app\sdks\aha_cua`（Computer-Use Agent）、技能 `browser-use-automation` / `computer-use-automation` / `browser-record-replay`、`terminal_conpty` + `sbox`（沙箱终端） |
| 深链协议 | `doubaowork://` → `"D:\Program Files\DoubaoWork\app\DoubaoWork.exe" -- --open-url="%1"` |

## 二、为什么不能像其它三个那样调用（逐项排查）

| 检查项 | 结果 |
|---|---|
| 是否有 CLI 可执行文件 | ❌ 安装目录内没有任何 CLI；只有 helper（`file_search_host.exe`、`file_utils_host.exe`、`ghelper.exe`、`update.exe`、`repair.exe`、`ttdaemon.exe`）与代理进程（`DoubaoWork_browser_proxy.exe`、`DoubaoWork_proxy.exe`） |
| 是否有 headless / print 模式 | ❌ 无 |
| 是否暴露本地 HTTP API | ❌ 运行时 10 个 `DoubaoWork` 进程**都没有监听任何本地端口**（已用 `Get-Process` 取 PID 与 `netstat -ano` 逐条交叉核对；第一次核对因沙箱限制漏查，已重做） |
| 是否有调试端口 | ❌ 未发现 `--remote-debugging` 之类参数 |
| 是否对外提供 MCP server | ❌ 只有 `app\mcp_helper.dll`，说明它作为 MCP **客户端**消费工具；没有对外暴露 |
| 是否有可脚本化的任务入口 | ⚠️ `app\task-mode-resource`（`runtime-bundle` + `python-packages`）是它内部"任务模式"的资源，不是外部接口 |
| 官方文档 | 未找到面向外部的本地自动化 / CLI 文档 |

**结论**：它是**纯 GUI 应用**。它自身具备相当强的 agent 能力（技能体系 + 计算机操作 + 沙箱终端），
但那是给人在界面里用的，对外没有稳定的编程接口。

## 三、替代方案（按可靠性排序）

### 方案 A：反向集成 —— 让豆包工作来调用本中继（推荐）
- 它的 agent 模式支持技能，且 `agent_mode\workspace\.user_skills` 目前**为空、可写**
- 它的技能可以带脚本（内置技能里就有 `bin\preview.cmd`），并且它能执行终端命令
- 所以可以给它写一个技能，教它 `POST http://127.0.0.1:18791/run` 去调用 Codex / WorkBuddy / 千问办公

效果：**在豆包工作的界面里也能用上这三个 Agent**。方向相反，但同样实用。
前置工作：先弄清它 `.user_skills` 的技能格式（可参照 `workspace\.skills\<name>\` 的结构与 `references\` 约定）。

### 方案 B：GUI 自动化（脆弱，不建议依赖）
技术上可用 Win32/UIA + SendKeys/剪贴板驱动它的窗口，但：
- 需要应用在前台、屏幕不锁、分辨率固定
- 结果只能靠截图/OCR 读回，容易出错
- DSH 当前会话并未暴露 computer-use 工具

**因此不要写进技能当作可靠通道。**

### 方案 C：深链唤起（只能"叫醒"，不能"取结果"）
`doubaowork://...` 可以拉起应用，但：
- 支持的深链动作未知
- 没有任何返回值通道

→ 不构成"调用"。

## 四、如果将来它开放了入口

按本包 `docs/07-skill.md` 的步骤即可接入：在 `scripts\agents.ps1` 加一个分支（入口路径 / headless 参数 /
认证方式 / 调用模式），在技能 `multi-agent-bridge` 的第 1、2 节各加一行。

需要事先确认的四件事：
1. 可执行文件路径（或本地 API 端口）
2. 非交互调用参数（是否有 `-p` / `--print` 之类）
3. 认证方式（登录态文件在哪，或用环境变量注入 token）
4. 调用模式：凭据在真实家目录 → `native: true`；否则用隔离模式
