@echo off
rem Creates a plain Desktop shortcut (this one keeps the normal admin prompt).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-Shortcut.ps1"
if errorlevel 1 (
    echo.
    echo Shortcut creation reported a problem. See the message above.
    pause
)
