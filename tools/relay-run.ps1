<#
    relay-run.ps1  —  通过本机中继调用 Codex / WorkBuddy / 千问办公

    用法：
        powershell -NoProfile -ExecutionPolicy Bypass -File relay-run.ps1 `
            -BodyFile 请求体.json [-OutFile 结果.txt]

    BodyFile 是一份 JSON，字段见 multi-agent-bridge 技能第 1 节：
        agent / prompt / workdir / timeoutSec / native / allowTools
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BodyFile,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$relay = 'D:\document\deepseek-harness\multi-agent\scripts\relay'
$token = (Get-Content (Join-Path $relay 'token.txt') -Raw).Trim()

$body = Get-Content -LiteralPath $BodyFile -Raw -Encoding UTF8
$parsed = $body | ConvertFrom-Json
Write-Host ("--> 派给 " + $parsed.agent + "（timeoutSec=" + $parsed.timeoutSec + "）") -ForegroundColor Cyan

$resp = & curl.exe -sS -X POST 'http://127.0.0.1:18791/run' `
    -H "x-bridge-token: $token" -H 'Content-Type: application/json; charset=utf-8' `
    --data-binary "@$BodyFile" --max-time ([int]$parsed.timeoutSec + 60) 2>&1

$text = ($resp | Out-String).Trim()
try {
    $o = $text | ConvertFrom-Json
    Write-Host ("<-- exitCode=" + $o.exitCode + "  用时 " + $o.seconds + "s") -ForegroundColor Cyan
    $result = $o.log
} catch {
    Write-Host '<-- 返回不是 JSON，原样输出' -ForegroundColor Yellow
    $result = $text
}

if ($OutFile) {
    [System.IO.File]::WriteAllText($OutFile, $result, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("    已存 -> " + $OutFile) -ForegroundColor Green
}
else { Write-Output $result }
