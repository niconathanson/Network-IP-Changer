<#
    One-time setup: launch Network IP Changer with NO admin (UAC) prompt.

    How it works: it registers a Scheduled Task that runs the app elevated in
    your interactive session, then makes a Desktop shortcut that silently
    triggers that task. Because you're allowed to run your own scheduled tasks,
    Windows launches it elevated without asking for consent each time.

    Run this ONCE (it will ask for admin a single time to register the task).
    If you ever move this folder, just run it again.

    Security note: this pre-authorises THIS app to run elevated silently. Anyone/
    anything that can trigger the task gets admin for it. That's the trade-off
    for skipping the prompt. To undo, run Remove-NoPrompt.ps1.
#>

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$ps1       = Join-Path $scriptDir 'NetworkIPChanger.ps1'
$ico       = Join-Path $scriptDir 'AppIcon.ico'
if (-not (Test-Path $ico)) { $ico = Join-Path $scriptDir 'app.ico' }
$vbs       = Join-Path $scriptDir 'Run Network IP Changer (no prompt).vbs'
$taskName  = 'Network IP Changer'
$psExe     = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# --- Self-elevate once (registering a highest-privilege task needs admin) ---
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
    # 1. Register the task: runs the app elevated, in the logged-on user's session.
    $action = New-ScheduledTaskAction -Execute $psExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $settings.ExecutionTimeLimit = 'PT0S'   # never auto-terminate the GUI
    $task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings `
        -Description 'Launches Network IP Changer elevated without a UAC prompt.'
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

    # 2. Silent trigger (VBS runs schtasks hidden, so no console flash).
    $vbsContent = 'CreateObject("WScript.Shell").Run "schtasks /run /tn ""' + $taskName + '""", 0, False'
    Set-Content -Path $vbs -Value $vbsContent -Encoding ASCII

    # 3. Desktop shortcut -> the silent trigger, wearing the app icon.
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop 'Network IP Changer.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $lnk.Arguments        = "`"$vbs`""
    $lnk.WorkingDirectory = $scriptDir
    if (Test-Path $ico) { $lnk.IconLocation = "$ico, 0" }
    $lnk.Description = 'Change network adapter IP - no admin prompt'
    $lnk.Save()

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Setup complete.`r`n`r`nA 'Network IP Changer' shortcut is on your Desktop - it now opens WITHOUT an admin prompt.`r`n`r`nRight-click it to Pin to taskbar or Start.`r`n`r`nIf you move this folder, run 'Turn off Admin Permission Popup' again.",
        'Network IP Changer - Setup', 'OK', 'Information') | Out-Null
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Setup failed:`r`n`r`n$($_.Exception.Message)",
        'Network IP Changer - Setup', 'OK', 'Error') | Out-Null
    exit 1
}
