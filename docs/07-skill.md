# 07 · 技能封装：把"多 Agent 调度"变成 DSH 技能

> 记录如何把本资料包的能力封装成 DSH 技能，以及 DSH 技能系统的完整机制。
> **以后想再做新技能，照这篇做即可。**

## 一、成品

| 项 | 值 |
|---|---|
| 技能名 | `multi-agent-bridge` |
| 安装位置 | `C:\Users\TANG\.agents\skills\multi-agent-bridge\SKILL.md` |
| 大小 | 约 6 KB |
| 生效方式 | **无需重启**：文件监视器触发目录刷新，会话中的技能列表当场更新 |
| 触发方式 | ①自然语言（由 frontmatter 的 `description` 匹配）②Web UI 输入 `/multi-agent-bridge` 显式调用 |

技能正文是一份"可执行操作手册"：中继健康检查 → `POST /run` 字段表与坑 → Agent 选择建议 →
并行 fan-out 写法 → 工具执行的**危险档位**与"必须先问用户"约束 → 额度提醒 → 报错对照表。

## 二、DSH 技能系统的机制（反查自 app.asar）

DSH 的实现打包在 `resources\app.asar` 里（PowerShell 不能当成目录读）。
用本包 `tools\asar_scan.py`（最小 asar 解析器）可以列出／提取其中任意文件。关键包：

| 包 | 职责 |
|---|---|
| `@deepseek-ai/dsh-skill` | 技能注册表（接受任意 provider） |
| `@deepseek-ai/dsh-skill-filesystem` | **从文件系统发现技能**（本文核心） |
| `@deepseek-ai/dsh-tool-skill` | 宿主侧的 `skill` 工具（模型可调用） |
| `@deepseek-ai/dsh-client-ui-skill` | Web 端 `/` 菜单与技能调用卡片 |
| `@deepseek-ai/dsh-skill-office` | office 三个内置技能（放在 `assets/<name>/SKILL.md`） |

### 扫描哪些根目录（按 rank 顺序）

| Rank | 来源 | 路径 |
|---|---|---|
| 100 | project-dsh | `<项目根>/.dsh/skills` |
| 200 | project-agents | `<项目根>/.agents/skills` |
| 300 | custom | `Config.customSkillDirs` |
| 400 | user-dsh | `<DSH_HOME>/skills`（默认 `~/.dsh/skills`，跳过其 `.system` 子目录） |
| 500 | user-agents | `<AGENTS_HOME>/skills`（默认 `~/.agents/skills`） |
| 600 | bundled | `bundledSkillDir`（随包提供） |

- **项目根** ＝ 包含 `.git` 的最近祖先目录；不存在则用当前 cwd。
  本机实测：`default-workspace` 往上到 `D:\` 都没有 `.git`，所以项目根就是 cwd 本身。
- 本机现有 8 个用户技能都在 rank 500 的 `~/.agents/skills`，**所以新技能也放这里，保持一致**。

### 技能格式

- 两种形态：目录包 `<名字>/SKILL.md`，或平铺文件 `<名字>.md`
- **只扫描一层**，刻意不支持嵌套 `**/SKILL.md`
- YAML frontmatter：
  - 必填 `name`（**kebab-case**）、`description`
  - 可选 `whenToUse`、`metadata`、`disable-model-invocation`、`user-invocable`
  - `disable-model-invocation: true` → 从模型目录与 loader 中排除（只能由用户显式调用）
  - `user-invocable: false` → 从 `/` 命令菜单中排除
  - 布尔值接受 `true/false`、`yes/no`、`on/off`、`1/0`（大小写不敏感）
  - **拼错或非布尔值 → 整个技能被丢弃**（只给警告，不会静默放行某个接口）
- 资源目录 `references/`、`scripts/`、`assets/` 可以随包携带；
  但编辑这些资源**不会**触发目录刷新，编辑 frontmatter 才会
- 目录与正文生命周期分离：发现阶段只解析 frontmatter，**每次加载都重读文件**
  → 改正文立即生效，无需版本号或缓存失效

### 实测验证路径（本次就是这么验的）

1. 写入 `~/.agents/skills/multi-agent-bridge/SKILL.md`
2. 会话的技能目录**当场刷新**，新技能出现在可用技能列表中（watcher 失效 → 目录刷新）
3. 用 `skill` 工具按名字加载 → 返回完整正文，基础目录正确解析为该技能目录

## 三、以后再做一个新技能（步骤）

1. 起一个 kebab-case 名字，例如 `my-new-skill`
2. 建目录 `%USERPROFILE%\.agents\skills\my-new-skill\`
3. 写 `SKILL.md`：

   ```yaml
   ---
   name: my-new-skill
   description: "一句话说明它做什么 + 什么时候该用。触发条件写得越具体越容易被正确调用。Use this when ..."
   ---

   # my-new-skill

   ...正文：可执行的操作步骤、命令、常见坑、参考资源路径...
   ```

4. 需要的话放 `references/`、`scripts/`、`assets/` 等资源
5. 保存即生效——技能列表会自己刷新，**不需要重启 DSH**
6. 验证：让 DSH 用 `skill` 工具加载该名字，或直接说触发词

### 写 `description` 的建议

`description` 既是**给模型看的触发条件**，也是 **`/` 菜单里的说明**。
把用户可能说的原话写进去（中英混排也可以）。例如本技能里写了
「让 Codex 做…」「三家各做一版」「用 CodeBuddy / 千问办公…」这类触发语。

## 四、附：asar 解析器用法

```powershell
$py = 'C:\Users\TANG\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'

# 列出所有路径含 "skill" 的条目（并打印顶层目录、条目总数）
& $py D:\document\deepseek-harness\multi-agent\tools\asar_scan.py

# 提取某个文件的内容（自动定位并打印）
& $py D:\document\deepseek-harness\multi-agent\tools\asar_scan.py 'dsh/node_modules/@deepseek-ai/dsh-skill-filesystem/README.zh.md'
```

原理备忘：asar 头部是 Chromium Pickle 格式——
文件前 4 字节是 size pickle 的 payload 大小，第 4~8 字节是**头部缓冲区大小**；
从偏移 8 读取该长度的缓冲区，缓冲区自身又是 `[uint32 字符串长度][JSON][padding]`；
文件数据区的基准偏移 = `8 + 头部缓冲区大小`。

## 五、其它可选的技能安装位置

- `~/.agents/skills`（rank 500，**当前使用**）：与现有 8 个用户技能一致；
  该目录被描述为"为兼容 skill 扫描的共享 agent 配置根目录"，其它遵循同一约定的 agent 工具也可能读到。
- `~/.dsh/skills`（rank 400）：只给 DSH 用的用户级位置。
- `<项目>/.dsh/skills`（rank 100）：随项目走，优先级最高，但只在项目内可见。
