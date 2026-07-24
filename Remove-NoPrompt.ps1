<#
    Undoes Setup-NoPrompt.ps1: unregisters the scheduled task and removes the
    silent trigger + Desktop shortcut. After this, the app again asks for admin
    (UAC) on launch. Run once (it self-elevates to remove the task).
#>

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$vbs       = Join-Path $scriptDir 'Run Network IP Changer (no prompt).vbs'
$taskName  = 'Network IP Changer'
$psExe     = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$principalCheck = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process -FilePath $psExe -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    } catch { }
    exit
}

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Network IP Changer.lnk'
    if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Removed the no-prompt setup.`r`n`r`nThe app will now ask for admin (UAC) again. You can still launch it with 'Launch Network IP Changer.cmd'.",
        'Network IP Changer - Removed', 'OK', 'Information') | Out-Null
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Removal failed:`r`n`r`n$($_.Exception.Message)",
        'Network IP Changer - Removed', 'OK', 'Error') | Out-Null
    exit 1
}
