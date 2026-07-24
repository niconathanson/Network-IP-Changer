@echo off
rem Undoes the no-prompt setup (removes the scheduled task + its shortcut).
rem After this, the app asks for admin (UAC) again on launch.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-NoPrompt.ps1"
if errorlevel 1 (
    echo.
    echo Removal reported a problem. See the message above.
    pause
)
