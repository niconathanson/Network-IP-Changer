@echo off
rem One-time setup: launch the app with NO admin prompt (scheduled-task method).
rem Double-click this. It approves admin ONCE to register the task, then makes a
rem Desktop shortcut that opens the app instantly with no prompt.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-NoPrompt.ps1"
if errorlevel 1 (
    echo.
    echo Setup reported a problem. See the message above.
    pause
)
