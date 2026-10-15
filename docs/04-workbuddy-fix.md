# 04 · WorkBuddy 登录失败：根因与修复记录

> 这是一次真实的排查过程。症状是"窗口一开就闪退，永远登不上"，最后发现是**安装包缺少交互式产物**。
> 换机重装后若再次遇到，照本文做即可。

## 一、症状

1. 用内置 CLI 启动交互界面 → 立刻退出，报：

```
Error: Cannot find module '../dist/codebuddy'
Require stack:
- ...\WorkBuddy\resources\app.asar.unpacked\cli\bin\codebuddy
```

2. Web UI 打开后显示 `Web UI is not built.`（只有 API，没有前端）。
3. `codebuddy -p "hi"` → `Authentication required. Please use /login command`（鉴权门先拦，根本进不到登录流程）。

## 二、根因

`bin/codebuddy` 会按变体分派产物：

| 条件 | 加载的产物 | 本机是否存在 |
|---|---|---|
| 无参数（TUI 模式） | `dist/codebuddy`（CJS） | ❌ **不存在** |
| `-p` / `--print` 等（headless） | `dist/codebuddy-headless.js` | ✅ 存在 |
| 环境变量 `CODEBUDDY_FORCE_LITE_WB_BUNDLE=1` | `dist/codebuddy-lite-wb.mjs` | ✅ 存在 |

也就是说：**这个安装只打包了 headless 和 lite-wb 两个产物，没有 TUI 产物**。
而无参数启动正好走 TUI 那条路，回退逻辑在该分支下是 `throw e`（直接抛错），所以必然崩溃 —— 你根本没有可以输入 `/login` 的界面。

补充证据：`lite-wb` 独立启动也会立刻 `exit 0`（它是给桌面端内嵌用的），所以也无法用来登录。

## 三、修复步骤

### 1) 安装官方原生构建（含完整 CLI 与 Web UI）

```powershell
$env:CODEBUDDY_FORCE_LITE_WB_BUNDLE = '1'   # 内置 CLI 只有 lite-wb 变体可用
codebuddy install                            # → 下载并安装 2.164.0
```

结果：

```
✓ CodeBuddy Code 2.164.0 installed successfully
  Location: C:\Users\TANG\AppData\Local\codebuddy\bin\codebuddy.exe
```

> 该命令必须在**沙箱外**运行（要联网下载）。

### 2) 用 Web UI 登录（关键：CLI 没有 login 子命令）

- `codebuddy.exe login` **不存在**（会被当成普通提问）
- `codebuddy -p "/login"` 会被鉴权门直接拦掉
- 原生构建的 Web UI 是**真实前端**（`<title>CodeBuddy Code Remote Control</title>`），所以走它：

```powershell
codebuddy.exe --serve --open --port 57450
```

启动日志会给出访问地址与口令：

```
Endpoint    http://127.0.0.1:57450
Web UI      http://127.0.0.1:57450/?password=<本机口令>
Password    <本机口令>
```

在浏览器里打开该地址 → 完成腾讯 SSO 授权 → 登录成功。

### 3) 备用登录方式（交互式 TUI）

如果将来 TUI 产物齐全，交互界面里的登录菜单是：

```
Select login method:
 ❯ Log in via Chinese Site            ← 国内用户选这个
   Log in via International Site
   Log in via iOA (Tencent only)      ← 腾讯内部员工专用，选了会失败
   Log in via Enterprise Domain
(Use ↑↓ to select, Enter to login)
```

随后会打开浏览器，并显示 `Waiting for auth... (Press ESC to cancel)`（**不要按 ESC**），
同时把登录链接复制到剪贴板。

### 4) 另一种免登录方式：环境变量

CLI 支持 `CODEBUDDY_API_KEY` / `CODEBUDDY_AUTH_TOKEN`。二进制里的界面文案明确写着：

> ⚠ Environment variable authentication detected
> The following environment variable(s) are set and will override /login

所以只要有 API Key，注入环境变量即可完全跳过登录界面。

## 四、工具执行为什么默认不工作（以及怎么开）

非交互（`-p`）模式下 CLI 无法弹窗确认权限，所有命令会被拒，模型会回复类似：

> Bash 和 PowerShell 都被权限策略拦截了（非交互模式下无法弹窗确认）

解法（已内置于桥接的 `-AllowTools` 档位）：

```
codebuddy -p --permission-mode bypassPermissions -y "<prompt>"
```

实测：开启后成功执行 shell 命令并统计出 3052 个文件。

## 五、附带发现：本地网关 API

`--serve` 暴露了一个完整的 HTTP API（`GET /api/docs`），主要接口：

- `POST /api/v1/auth/login` `{password}` → Bearer token
- `POST /api/v1/runs` `{id, type, text, source}` → 发起 Agent 执行（202 + runId）
- `GET /api/v1/runs/{runId}` / `/stream`(SSE)、`/api/v1/sessions`、`/api/v1/traces`、`/api/v1/jobs`、`/api/v1/pty` 等 100+ 接口
- 所有请求需带 `x-codebuddy-request` 头；API 调用另需 `Authorization: Bearer <token>`

注意：账号未登录时 `/api/v1/runs` 仍会受理，但 Agent 会在约 **21ms** 内以 `Error in agent run` 失败（可在 `/api/v1/traces` 看到）。
