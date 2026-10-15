@echo off
title stop agent-bridge relay
echo ============================================================
echo  Stopping any running agent-bridge relay ...
echo ============================================================
powershell.exe -NoProfile -Command "$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match 'relay\.js' }; if ($p) { $p | ForEach-Object { Write-Host ('killing PID ' + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } else { Write-Host 'no relay process found' }"
echo.
echo Done. Press any key to close.
pause >nul
