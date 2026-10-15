@echo off
title agent-bridge relay (127.0.0.1:18791)
echo ============================================================
echo  agent-bridge relay
echo.
echo  Starts the local relay that lets DSH call Codex / CodeBuddy /
echo  Qoder with ZERO approval prompts.
echo.
echo  Run this from YOUR OWN terminal (outside the DSH sandbox).
echo  If it says EADDRINUSE, a relay is already running - just
echo  close this window.
echo ============================================================
echo.
"C:\Users\TANG\AppData\Local\Programs\nodejs\node.exe" "%~dp0relay\relay.js"
echo.
echo === relay exited. Press any key to close ===
pause >nul
