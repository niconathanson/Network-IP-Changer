<#
    Creates a desktop shortcut called "Network IP Changer" that launches the
    tool with no visible console window. Run this once. After it appears on the
    desktop you can drag it to the taskbar / Start to pin it.
#>

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$target     = Join-Path $scriptDir 'NetworkIPChanger.ps1'
$desktop    = [Environment]::GetFolderPath('Desktop')
$lnkPath    = Join-Path $desktop 'Network IP Changer.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk   = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
$lnk.WorkingDirectory = $scriptDir
$icoPath = Join-Path $scriptDir 'AppIcon.ico'
if (-not (Test-Path $icoPath)) { $icoPath = Join-Path $scriptDir 'app.ico' }
if (Test-Path $icoPath) { $lnk.IconLocation = "$icoPath, 0" }
else { $lnk.IconLocation = "$env:SystemRoot\System32\netshell.dll, 0" }
$lnk.Description       = 'Change the static IP / subnet / gateway of any network adapter'
$lnk.WindowStyle       = 7                                            # minimized launcher
$lnk.Save()

Write-Host "Shortcut created on your Desktop: `"$lnkPath`"" -ForegroundColor Green
Write-Host "Right-click it and choose 'Pin to taskbar' or 'Pin to Start' for one-click access." -ForegroundColor Green
