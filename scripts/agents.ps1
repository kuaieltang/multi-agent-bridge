<#
.SYNOPSIS
    统一调度本机上其它 Agent CLI（Codex / WorkBuddy(CodeBuddy) / 千问办公(Qoder)）的封装。

.DESCRIPTION
    目标：在 DSH 的 workspace-write 沙箱下「零审批」调用外部 agent CLI。
    做法是把每个 CLI 的配置/状态目录（以及子进程的 HOME）重定向到本脚本所在目录，
    使被调 agent 不写 C:\Users\... 从而不被沙箱拒绝(EPERM)。

    默认只读：不带 -AllowTools 时禁用/收紧工具，避免被调 agent 改动文件。

.EXAMPLE
    .\agents.ps1 -Agent codex -Prompt "用一句话说明什么是幂等性"
.EXAMPLE
    .\agents.ps1 -Agent codebuddy -Prompt "把这句话改成正式商务语气：这活儿我干完了"
.EXAMPLE
    .\agents.ps1 -Agent qoder -Prompt "写一句周报开头" -AllowTools -WorkDir D:\tmp
.EXAMPLE
    .\agents.ps1 -Agent codex -Prompt "..." -Native   # 真实家目录，需要沙箱提权
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'codebuddy', 'qoder', 'qoder-models', 'qwenwork', 'qwenwork-version')]
    [string]$Agent,

    [string]$Prompt = '',
    [string]$WorkDir,
    [int]$TimeoutSec = 300,
    [string]$ExtraArgs = '',
    [switch]$AllowTools,

    # Codex 专用：完全绕过其自带沙箱（danger-full-access）
    [switch]$FullAccess,
    [switch]$Native,
    [string]$OutFile,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# 以 '-' 开头的额外参数无法通过 powershell -File 传递（会被当成参数名），用环境变量兜底
if (-not $ExtraArgs -and $env:BRIDGE_EXTRA_ARGS) { $ExtraArgs = $env:BRIDGE_EXTRA_ARGS }

if ($Agent -in @('codex', 'codebuddy', 'qoder') -and [string]::IsNullOrWhiteSpace($Prompt)) {
    throw "Agent=$Agent 需要 -Prompt"
}

# ---------------------------------------------------------------- 基础路径
$BridgeRoot = $PSScriptRoot
$HomeRoot   = Join-Path $BridgeRoot 'home'
$OutRoot    = Join-Path $BridgeRoot 'out'
$TmpRoot    = Join-Path $BridgeRoot 'tmp'
foreach ($d in @($HomeRoot, $OutRoot, $TmpRoot)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
if (-not $WorkDir) { $WorkDir = (Get-Location).Path }
if (-not (Test-Path $WorkDir)) { throw "WorkDir 不存在: $WorkDir" }

$RealHome      = $env:USERPROFILE
$RealCodexHome = Join-Path $RealHome '.codex'
$SystemNode    = 'C:\Users\TANG\AppData\Local\Programs\nodejs\node.exe'
$WbRoot        = 'D:\Users\TANG\AppData\Local\Programs\WorkBuddy'
$QwRoot        = 'D:\Users\TANG\AppData\Local\Programs\QwenWorkCN\1.2.5-26092902'

# WorkBuddy 内置 CLI 缺少交互式产物（bin/codebuddy 会 require 不存在的 dist/codebuddy），
# 因此优先使用官方原生构建（自包含 exe，含完整 CLI）；缺失时回退到内置 CLI。
$CbNative  = 'C:\Users\TANG\AppData\Local\codebuddy\bin\codebuddy.exe'
$CbBundled = Join-Path $WbRoot 'resources\app.asar.unpacked\cli\bin\codebuddy'
$CbEntry   = if (Test-Path $CbNative) { $CbNative } else { $CbBundled }

$Endpoints = @{
    codex            = (Join-Path $RealCodexHome '.sandbox-bin\codex.exe')
    codebuddy        = $CbEntry
    qoder            = (Join-Path $QwRoot 'resources\bin\qoderclicn.exe')
    'qoder-models'   = (Join-Path $QwRoot 'resources\bin\qoderclicn.exe')
    qwenwork         = (Join-Path $QwRoot 'resources\bin\qwenwork-win32-x64.exe')
    'qwenwork-version' = (Join-Path $QwRoot 'resources\bin\qwenwork-win32-x64.exe')
}

$Exe        = $Endpoints[$Agent]
$UseNode    = $false
if ($Agent -eq 'codebuddy') {
    # 只有内置 CLI（node 脚本）才需要 node 包装；原生 exe 直接执行
    if ($Endpoints['codebuddy'] -notlike '*.exe') {
        $UseNode = $true
        $NodeExe = if (Test-Path $SystemNode) { $SystemNode }
                   else { 'C:\Users\TANG\.workbuddy\binaries\node\versions\22.22.2-6\node.exe' }
        if (-not (Test-Path $NodeExe)) { throw "找不到 node: $NodeExe" }
    }
    elseif (-not (Test-Path $Exe)) { throw "找不到 codebuddy: $Exe" }
}
elseif (-not (Test-Path $Exe)) { throw "找不到 $Agent 的可执行文件: $Exe" }

# ---------------------------------------------------------------- 隔离目录
$IsoHome  = Join-Path $HomeRoot $Agent
$IsoCodex = Join-Path $HomeRoot 'codex'
$IsoCb    = Join-Path $HomeRoot 'codebuddy'
$IsoQwen  = Join-Path $HomeRoot 'qwen'
foreach ($d in @($IsoHome, $IsoCodex, $IsoCb, $IsoQwen)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Quote-Arg([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    return '"' + ($s -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

$argList  = New-Object System.Collections.Generic.List[string]
$childEnv = @{}
$runMode  = if ($Native) { 'native' } else { 'isolated' }
$notes    = New-Object System.Collections.Generic.List[string]
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$answerFile = $null

switch ($Agent) {

    'codex' {
        if ($Native) { $notes.Add('CODEX_HOME=真实目录（需提权）') }
        else {
            $cfg = Join-Path $IsoCodex 'config.toml'
            if (-not (Test-Path $cfg)) {
                @'
model_provider = "custom"
model = "deepseek-flash"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers.custom]
name = "deepseek"
base_url = "https://api.deepseek.com"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
'@ | Set-Content -Path $cfg -Encoding UTF8
            }
            $authFile = Join-Path $RealCodexHome 'auth.json'
            if (Test-Path $authFile) {
                try {
                    $key = (Get-Content $authFile -Raw | ConvertFrom-Json).OPENAI_API_KEY
                    if ($key) {
                        $childEnv['OPENAI_API_KEY'] = $key
                        $notes.Add('OPENAI_API_KEY 从真实 auth.json 注入环境变量（不复制文件）')
                    }
                } catch { }
            }
            if (-not $childEnv.ContainsKey('OPENAI_API_KEY')) { $notes.Add('警告：未取到 API Key') }
            $childEnv['CODEX_HOME'] = $IsoCodex
            $notes.Add("CODEX_HOME=$IsoCodex")
        }

        $argList.AddRange([string[]]@('exec', '-C', $WorkDir, '--skip-git-repo-check'))

        # 沙箱档位：read-only(默认) / workspace-write(-AllowTools) / danger-full-access
        # 允许用 ExtraArgs 里的 -s <mode> 覆盖（否则会重复传 -s 直接报错）
        $sbMode = if ($FullAccess) { 'danger-full-access' }
                  elseif ($AllowTools) { 'workspace-write' }
                  else { 'read-only' }
        if ($ExtraArgs -and $ExtraArgs -match '(?:^|\s)-s\s+(\S+)') {
            $sbMode = $Matches[1]
            $ExtraArgs = ($ExtraArgs -replace '(?:^|\s)-s\s+\S+', ' ').Trim()
        }
        $argList.AddRange([string[]]@('-s', $sbMode))
        $notes.Add("codex sandbox=$sbMode")
        # Codex 会派生后台进程占用管道，导致 stdout 抓不全；用 -o 把最终回答落盘
        $answerFile = Join-Path $TmpRoot "codex-last-$stamp.txt"
        $argList.AddRange([string[]]@('-o', $answerFile))
        $notes.Add("最终回答落盘: codex-last-$stamp.txt")
        $promptPending = $true
    }

    'codebuddy' {
        if ($UseNode) { $argList.Add($Endpoints['codebuddy']) }   # node 的第一个参数：CLI 脚本
        if (-not $Native) {
            $childEnv['CODEBUDDY_CONFIG_DIR'] = $IsoCb
            $notes.Add("CODEBUDDY_CONFIG_DIR=$IsoCb")
        }
        else { $notes.Add('CODEBUDDY_CONFIG_DIR=真实目录（需提权）') }

        $permMode = if ($AllowTools) { 'bypassPermissions' } else { 'dontAsk' }
        $argList.AddRange([string[]]@('-p', '--output-format', 'text', '--permission-mode', $permMode))
        if ($AllowTools) {
            # headless 模式下工具必须先授权：-y + bypassPermissions
            $argList.Add('-y')
            $notes.Add('允许工具执行 (-y, bypassPermissions)')
        }
        else { $argList.AddRange([string[]]@('--tools', '')) }
        $promptPending = $true
    }

    'qoder' {
        if (-not $Native) {
            $argList.AddRange([string[]]@('--config-dir', $IsoQwen))
            $notes.Add("--config-dir $IsoQwen")
        }
        else { $notes.Add('使用真实配置目录（需提权）') }

        $argList.AddRange([string[]]@('-p', '-w', $WorkDir, '--permission-mode', 'dont_ask'))
        if (-not $AllowTools) { $argList.AddRange([string[]]@('--tools', '')) }
        # --tools 是可变参数，会把后面的 query 一起吞掉；用 -- 明确分隔
        $argList.Add('--')
        $promptPending = $true
    }

    'qoder-models' {
        if (-not $Native) {
            $argList.AddRange([string[]]@('--config-dir', $IsoQwen))
            $notes.Add("--config-dir $IsoQwen")
        }
        else { $notes.Add('使用真实配置目录') }
        $argList.Add('--list-models')
    }

    'qwenwork' {
        $argList.AddRange([string[]]@('-o', 'json'))
        $argList.AddRange([string[]]($Prompt -split '\s+'))
    }

    'qwenwork-version' {
        $argList.Add('version')
    }
}

# ---------------------------------------------------------------- 收尾参数
if ($ExtraArgs.Trim()) { $argList.AddRange([string[]]($ExtraArgs -split '\s+')) }
if ($promptPending) { $argList.Add($Prompt) }

# ---------------------------------------------------------------- 输出文件
if (-not $OutFile) { $OutFile = Join-Path $OutRoot "$Agent-$stamp.log" }
$stdOut = Join-Path $TmpRoot "$Agent-$stamp.out.txt"
$stdErr = Join-Path $TmpRoot "$Agent-$stamp.err.txt"

# 子进程 HOME 重定向（非 Native 模式）
if (-not $Native) {
    $childEnv['USERPROFILE']  = $IsoHome
    $childEnv['HOME']         = $IsoHome
    $childEnv['APPDATA']      = (Join-Path $IsoHome 'AppData\Roaming')
    $childEnv['LOCALAPPDATA'] = (Join-Path $IsoHome 'AppData\Local')
    foreach ($k in @('APPDATA', 'LOCALAPPDATA')) {
        $p = $childEnv[$k]
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

$argString = ($argList | ForEach-Object { Quote-Arg $_ }) -join ' '
$runExe    = if ($UseNode) { $NodeExe } else { $Exe }

# ---------------------------------------------------------------- 执行
# 用 .NET Process + 匿名管道读取（Windows 上不受命名管道沙箱限制），
# 拿到真实退出码、完整 stdout/stderr，并支持硬超时。
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $runExe
$psi.Arguments              = $argString
$psi.WorkingDirectory       = $WorkDir
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.RedirectStandardInput  = $true
try {
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding  = New-Object System.Text.UTF8Encoding($false)
} catch { }
foreach ($kv in $childEnv.GetEnumerator()) {
    $psi.EnvironmentVariables[$kv.Key] = [string]$kv.Value
}

$sw     = [System.Diagnostics.Stopwatch]::StartNew()
$proc   = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null   = $proc.Start()
$proc.StandardInput.Close()   # 立刻关闭 stdin，避免被调 agent 等待输入

$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()

if ($proc.WaitForExit($TimeoutSec * 1000)) {
    $status = "exit=$($proc.ExitCode)"
}
else {
    $status = "TIMEOUT(${TimeoutSec}s)"
    try { & taskkill.exe /F /T /PID $proc.Id 2>&1 | Out-Null } catch { }
    try { $proc.Kill() } catch { }
}
$sw.Stop()

# 子进程可能派生孙进程并继承管道句柄：读取必须有界，否则会永久阻塞
$readOkOut = $outTask.Wait(10000)
$readOkErr = $errTask.Wait(10000)

$body = ''
if ($readOkOut) { try { $body += $outTask.Result } catch { } }
else { $body += "`r`n[stdout 未在 10s 内关闭，可能有残留子进程持有管道]`r`n" }
if ($readOkErr) {
    try {
        $errText = $errTask.Result
        if ($errText -and $errText.Trim()) { $body += "`r`n--- stderr ---`r`n$errText" }
    } catch { }
}

if ($answerFile -and (Test-Path $answerFile)) {
    $ans = Get-Content $answerFile -Raw -ErrorAction SilentlyContinue
    if ($ans -and $ans.Trim()) {
        $body = "`r`n=== 最终回答 ===`r`n" + $ans.Trim() + "`r`n" + $body
    }
}

Set-Content -Path $stdOut -Value ($body) -Encoding UTF8

$header = @(
    "=== agent=$Agent mode=$runMode time=$stamp elapsed=$([int]$sw.Elapsed.TotalSeconds)s ==="
    "exe : $runExe"
    "args: $argString"
    "cwd : $WorkDir"
    "env : $($notes -join ' | ')"
    '---'
) -join "`r`n"

$full = $header + "`r`n" + $body + "`r`n=== $status ==="
Set-Content -Path $OutFile -Value $full -Encoding UTF8

if (-not $Quiet) { Write-Output $full }
Write-Output "OUTFILE: $OutFile"
