# Multi-Agent 工作方式 — 完整资料包

> 本仓库是技能 **`multi-agent-bridge`** 的源码与文档包。它让 DeepSeek Harness（DSH）能调用本机另外三个 Agent —— **Codex**、**WorkBuddy**、**千问办公** —— 去实际完成任务，而不是只能"聊天"。

## 作为技能安装

把本仓库克隆后，将整个目录（或仅 `SKILL.md`）放进你的 Agent 技能目录：

| 环境 | 路径 |
| --- | --- |
| QwenWork（Windows） | `%USERPROFILE%\.qwenworkcn\skills\multi-agent-bridge\` |
| WorkBuddy（Windows） | `%USERPROFILE%\.workbuddy\skills\multi-agent-bridge\` |
| 其他支持 SKILL.md 的 Agent | 对应的 skills 目录 |

```bash
# 国内推荐（Gitee 镜像）
git clone https://gitee.com/laotangshiye/multi-agent-bridge.git ~/.qwenworkcn/skills/multi-agent-bridge

# 或 GitHub
git clone https://github.com/kuaieltang/multi-agent-bridge.git ~/.qwenworkcn/skills/multi-agent-bridge
```

> ⚠️ **路径说明**：仓库内文档（如 `D:\document\deepseek-harness\multi-agent\`）是作者开发机上的绝对路径，仅作说明用。克隆后请把它们替换为你自己的目录；中继与脚本的实际位置以你克隆后的路径为准。
> 中继密钥 `scripts/relay/token.txt` 与运行时目录 `scripts/home/`、`scripts/out/`、`scripts/tmp/` 不会进版本库（见 `.gitignore`），首次运行由脚本自动生成。

---

**这套东西解决什么问题**：让 DSH（DeepSeek Harness）能够调用本机上另外三个 Agent —— **Codex**、**WorkBuddy**、**千问办公** —— 去实际完成任务，而不是只能"聊天"。

你只需要用自然语言告诉 DSH 要做什么，它负责选 Agent、发任务、收结果、交叉验证。

```
DSH ──┬─ 直连：agents.ps1（在 DSH 沙箱内，需要审批，因为沙箱内无法建立 TLS）
      │
      └─ 中继：relay.js（在沙箱外常驻，127.0.0.1 明文 HTTP）── agents.ps1 ──┬─ Codex
                                                                            ├─ WorkBuddy (CodeBuddy)
                                                                            └─ 千问办公 (Qoder)
```

> 豆包工作**没有**接进来：它没有任何可编程入口（无 CLI、无本地 API），详见 [docs/08-doubao-work.md](docs/08-doubao-work.md)。

## 当前部署状态（2026-10-14 起）

| 项 | 状态 |
|---|---|
| **本目录** | 已是**唯一实体**（文档 + 运行脚本 + 运行态数据都在这里） |
| **中继** | 监听 `127.0.0.1:18791`，由**开机自启**拉起（隐藏窗口，登录即就绪） |
| 自启入口 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\agent-bridge-relay.vbs` |
| 自启性质 | **登录时启动一次，不是守护进程**；中继若中途崩溃不会自动重拉 → 用下面的方式恢复 |
| 停止中继 | 双击 `scripts\stop-relay.cmd`；永久取消自启＝删除 Startup 里的那个 vbs |
| 手动启动 | 双击 `scripts\start-relay.cmd`（会显示窗口，可看日志） |
| **DSH 技能** | 已封装为技能 `multi-agent-bridge`（装在 `~/.qwenworkcn/skills/` 或 `~/.workbuddy/skills/`），说触发词即可自动加载，见 [docs/07-skill.md](docs/07-skill.md) |
| 旧的 `default-workspace\agent-bridge` | **仅作历史备份**，不再维护；确认无用后可直接删除 |

> · 改了 `relay\relay.js` 需要重启中继才生效；改了 `agents.ps1` **立即生效**（中继每次调用都会重新执行它）。
> · 运维速查表、注意事项、部署验证记录 → [docs/06-deployment-log.md](docs/06-deployment-log.md)

### ⚠️ 恢复中继时的正确姿势（踩过的坑）

**不要用「一次性命令」启动中继**（即使是提权的一次性命令）：DSH 在该命令结束后会回收其进程树，
中继会在几十分钟内悄悄消失 —— 2026-10-14 实测发生过一次，导致所有调用失败。正确顺序：

1. **首选**：请用户双击 `scripts\start-relay.cmd`（用户自己的终端＝完全脱离 DSH，最稳）
2. **或**由 DSH 以**后台任务**（managed background job）方式运行 `scripts\relay\relay.js`，本会话内持续存活
3. 修好后确认：访问 `http://127.0.0.1:18791/` 返回 **404** 即正常

## 快速开始（3 步）

1. **确认中继在跑**：浏览器或 PowerShell 访问 `http://127.0.0.1:18791/`，返回 **404** 就是正常（它只接受 POST）。
   开机自启正常情况下无需手动操作。
2. **确认凭据在位**：见 [docs/05-environment.md](docs/05-environment.md) 的三个检查点。
3. **直接跟 DSH 说话**，例如：
   - "让 Codex 写个校验手机号的正则"
   - "三家各写一版方案，你来评分挑最好的"
   - "用 CodeBuddy 把这段中文改成商务语气"

## 文件索引

| 文件 | 内容 |
|---|---|
| [docs/01-overview.md](docs/01-overview.md) | 架构、三个 Agent 的可用性与实测记录、能力边界 |
| [docs/02-usage.md](docs/02-usage.md) | 中继 API 详解、直连用法、并行 fan-out、任务指派建议 |
| [docs/03-troubleshooting.md](docs/03-troubleshooting.md) | 症状→原因→解决速查表、四个核心坑、恢复步骤 |
| [docs/04-workbuddy-fix.md](docs/04-workbuddy-fix.md) | WorkBuddy 登录失败的完整根因分析与修复记录 |
| [docs/05-environment.md](docs/05-environment.md) | 精确路径/版本/端口/凭据位置/开机自启/恢复清单 |
| [docs/06-deployment-log.md](docs/06-deployment-log.md) | 部署记录、运维速查表、三条注意事项、变更历史 |
| [docs/07-skill.md](docs/07-skill.md) | 技能封装机制：技能根目录优先级、SKILL.md 格式规则、asar 解析方法、如何再做新技能 |
| [docs/08-doubao-work.md](docs/08-doubao-work.md) | 豆包工作为什么没接进来：逐项排查证据 + 三种替代方案 |
| `scripts/` | 调度器、中继、自启 VBS、一键启动/停止/登录脚本 |
| `tools/asar_scan.py` | 最小 app.asar 解析器（查 DSH 内部实现用） |

## 现状速览（2026-10-14 全部实测通过）

| Agent | 问答 | 工具执行 | 调用模式 |
|---|---|---|---|
| Codex | ✅ | ✅ | isolated |
| WorkBuddy (CodeBuddy 2.164.0) | ✅ | ✅ | native |
| 千问办公 (Qoder 1.1.59) | ✅ | 默认禁用 | native |
| 豆包工作 (Doubao Work 2.25.18) | ⛔ 无编程接口 | ⛔ | — |

## 姊妹仓库

- [codebase-oss-borrow-audit](https://github.com/kuaieltang/codebase-oss-borrow-audit) — 审阅代码库、对标开源、输出 P0/P1/P2 分级可借鉴清单的审计技能
