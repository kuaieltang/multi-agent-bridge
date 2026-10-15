' agent-bridge relay autostart (hidden window)
' Installed in the user's Startup folder. Starts the local relay so that
' DSH can call Codex / CodeBuddy / Qoder with zero approval prompts.
'
' Stop it with:  D:\document\deepseek-harness\multi-agent\scripts\stop-relay.cmd
' Log file:      D:\document\deepseek-harness\multi-agent\scripts\relay\relay-autostart.log

Dim sh, nodeExe, relayJs, logFile, cmd
Set sh = CreateObject("WScript.Shell")

nodeExe = "C:\Users\TANG\AppData\Local\Programs\nodejs\node.exe"
relayJs = "D:\document\deepseek-harness\multi-agent\scripts\relay\relay.js"
logFile = "D:\document\deepseek-harness\multi-agent\scripts\relay\relay-autostart.log"

' 0 = hidden window, False = do not wait
cmd = "cmd /c """"" & nodeExe & """ """ & relayJs & """ >> """ & logFile & """ 2>&1"""
sh.Run cmd, 0, False
