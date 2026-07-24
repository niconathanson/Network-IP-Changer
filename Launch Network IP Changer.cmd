@echo off
rem ============================================================
rem  Foolproof launcher for Network IP Changer.
rem  Double-click this file. It runs the tool with Windows
rem  PowerShell 5.1 and bypasses the script execution policy,
rem  so it does not depend on .ps1 file associations.
rem ============================================================
setlocal
set "PS1=%~dp0NetworkIPChanger.ps1"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

rem If the script returned an error, keep this window open so the
rem message can be read instead of vanishing.
if errorlevel 1 (
    echo.
    echo -----------------------------------------------------------
    echo  The tool reported an error. See error.log next to this file.
    echo -----------------------------------------------------------
    pause
)
endlocal
