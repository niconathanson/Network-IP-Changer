<#
    Network IP Changer
    -------------------
    A one-click GUI to set a static IPv4 address / subnet / gateway on any
    connected network adapter (Wi-Fi, Ethernet, USB dongles), or flip it back
    to automatic (DHCP). Supports saved profiles for networks you use often.

    Just run it (or click the shortcut) - it self-elevates to admin, which is
    required to change IP settings on Windows.
#>

# ---------------------------------------------------------------------------
# 0. Catch-all error handler: never vanish silently. Log + show a popup.
# ---------------------------------------------------------------------------
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$script:LogPath   = Join-Path $script:ScriptDir 'error.log'
trap {
    $detail = "[{0}]`r`n{1}`r`n{2}`r`n" -f (Get-Date -Format s), ($_ | Out-String), $_.InvocationInfo.PositionMessage
    try { Add-Content -Path $script:LogPath -Value $detail -Encoding UTF8 } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "Network IP Changer hit an error:`r`n`r`n$($_.Exception.Message)`r`n`r`nFull details were written to:`r`n$script:LogPath",
            'Network IP Changer', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Self-elevate to Administrator (changing IPs requires it)
# ---------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Relaunch with Windows PowerShell 5.1 explicitly (always present, WinForms-friendly),
    # falling back to whatever launched us. Start-Process handles the runas verb correctly
    # on both PowerShell 5.1 and 7.
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $psExe)) { $psExe = (Get-Process -Id $PID).Path }
    try {
        Start-Process -FilePath $psExe -Verb RunAs -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', "`"$PSCommandPath`"")
    } catch {
        # Most likely the user dismissed the UAC prompt - nothing more to do.
    }
    exit
}

# ---------------------------------------------------------------------------
# 2. Hide the PowerShell console window (keep only the GUI)
# ---------------------------------------------------------------------------
Add-Type -Name Win -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
[Native.Win]::ShowWindow([Native.Win]::GetConsoleWindow(), 0) | Out-Null   # 0 = SW_HIDE

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# 3. Helpers
# ---------------------------------------------------------------------------
$script:ProfilePath = Join-Path $script:ScriptDir 'profiles.json'

function ConvertTo-PrefixLength([string]$mask) {
    # 255.255.255.0 -> 24 . Returns $null if the mask is not valid.
    $parsed = [ref]([System.Net.IPAddress]$null)
    if (-not [System.Net.IPAddress]::TryParse($mask, $parsed)) { return $null }
    $bits = ($mask.Split('.') | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''
    # A valid mask is a run of 1s followed by 0s.
    if ($bits -notmatch '^1*0*$') { return $null }
    ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function ConvertTo-SubnetMask([int]$prefix) {
    $bits = ('1' * $prefix).PadRight(32, '0')
    (0..3 | ForEach-Object { [Convert]::ToInt32($bits.Substring($_ * 8, 8), 2) }) -join '.'
}

function Test-IPv4([string]$ip) {
    $parsed = [ref]([System.Net.IPAddress]$null)
    if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
    if (-not [System.Net.IPAddress]::TryParse($ip, $parsed)) { return $false }
    # TryParse accepts things like "10" - require four dotted octets.
    ($ip.Split('.').Count -eq 4)
}

function Get-ClassfulMask([string]$ip) {
    # Mirrors the classic Windows behaviour of suggesting a mask from the IP.
    $first = [int]($ip.Split('.')[0])
    if     ($first -le 127) { '255.0.0.0' }
    elseif ($first -le 191) { '255.255.0.0' }
    else                    { '255.255.255.0' }
}

function Load-Profiles {
    if (-not (Test-Path $script:ProfilePath)) { return @() }
    try { $data = Get-Content $script:ProfilePath -Raw | ConvertFrom-Json } catch { return @() }
    # Recover older malformed saves that wrapped the array as { value: [...], Count: n }.
    if ($data -and ($data.PSObject.Properties.Name -contains 'value') -and
                   ($data.PSObject.Properties.Name -contains 'Count')) {
        $data = $data.value
    }
    @(@($data) | Where-Object { $_ -and $_.Name })
}

function Save-Profiles($profiles) {
    try { @($profiles) | ConvertTo-Json -Depth 5 | Set-Content $script:ProfilePath -Encoding UTF8 }
    catch { [System.Windows.Forms.MessageBox]::Show("Could not save presets:`n$($_.Exception.Message)", 'Network IP Changer') | Out-Null }
}

# ---------------------------------------------------------------------------
# 4. Build the window
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Network IP Changer'
$form.Size          = New-Object System.Drawing.Size(470, 408)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox   = $false
$form.Font          = New-Object System.Drawing.Font('Segoe UI', 9)

# Use the custom app icon in the title bar / taskbar if present
$icoPath = Join-Path $script:ScriptDir 'AppIcon.ico'
if (-not (Test-Path $icoPath)) { $icoPath = Join-Path $script:ScriptDir 'app.ico' }
if (Test-Path $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { } }

function New-Label($text, $x, $y, $w = 120) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 20); $l.TextAlign = 'MiddleLeft'
    $form.Controls.Add($l); $l
}
function New-TextBox($x, $y, $w = 250) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, 22)
    $form.Controls.Add($t); $t
}

$leftX  = 20
$fieldX = 150
$y = 18

# --- Adapter picker ---
New-Label 'Network adapter:' $leftX $y | Out-Null
$cboAdapter = New-Object System.Windows.Forms.ComboBox
$cboAdapter.Location = New-Object System.Drawing.Point($fieldX, ($y - 2))
$cboAdapter.Size = New-Object System.Drawing.Size(220, 24)
$cboAdapter.DropDownStyle = 'DropDownList'
$cboAdapter.DisplayMember = 'Display'
$form.Controls.Add($cboAdapter)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(378, ($y - 3))
$btnRefresh.Size = New-Object System.Drawing.Size(70, 26)
$form.Controls.Add($btnRefresh)

$y += 34

# --- Current config read-out ---
$grpCurrent = New-Object System.Windows.Forms.GroupBox
$grpCurrent.Text = 'Current configuration'
$grpCurrent.Location = New-Object System.Drawing.Point($leftX, $y)
$grpCurrent.Size = New-Object System.Drawing.Size(428, 78)
$form.Controls.Add($grpCurrent)

$lblCurrent = New-Object System.Windows.Forms.Label
$lblCurrent.Location = New-Object System.Drawing.Point(12, 20)
$lblCurrent.Size = New-Object System.Drawing.Size(320, 52)
$lblCurrent.Font = New-Object System.Drawing.Font('Consolas', 9)
$grpCurrent.Controls.Add($lblCurrent)

# Auto-fill button (top-right of the box): copies the live config into the fields below
$btnAutofill = New-Object System.Windows.Forms.Button
$btnAutofill.Text = 'Auto-fill'
$btnAutofill.Location = New-Object System.Drawing.Point(344, 18)
$btnAutofill.Size = New-Object System.Drawing.Size(76, 24)
$grpCurrent.Controls.Add($btnAutofill)

$y += 90

# --- Presets ---
New-Label 'Preset:' $leftX $y | Out-Null
$cboProfile = New-Object System.Windows.Forms.ComboBox
$cboProfile.Location = New-Object System.Drawing.Point($fieldX, ($y - 2))
$cboProfile.Size = New-Object System.Drawing.Size(150, 24)
$cboProfile.DropDownStyle = 'DropDownList'
$form.Controls.Add($cboProfile)

$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Text = 'Save'
$btnSaveProfile.Location = New-Object System.Drawing.Point(308, ($y - 3))
$btnSaveProfile.Size = New-Object System.Drawing.Size(64, 26)
$form.Controls.Add($btnSaveProfile)

$btnDeleteProfile = New-Object System.Windows.Forms.Button
$btnDeleteProfile.Text = 'Delete'
$btnDeleteProfile.Location = New-Object System.Drawing.Point(378, ($y - 3))
$btnDeleteProfile.Size = New-Object System.Drawing.Size(70, 26)
$form.Controls.Add($btnDeleteProfile)

$y += 40

# --- Manual entry fields (each with a small Clear button) ---
function New-ClearButton($x, $y) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = 'Clear'
    $b.Location = New-Object System.Drawing.Point($x, ($y - 1))
    $b.Size = New-Object System.Drawing.Size(56, 24)
    $form.Controls.Add($b); $b
}
$clearX = 358

New-Label 'IP address:' $leftX $y | Out-Null
$txtIP = New-TextBox $fieldX $y 200
$btnClearIP = New-ClearButton $clearX $y
$y += 32
New-Label 'Subnet mask:' $leftX $y | Out-Null
$txtMask = New-TextBox $fieldX $y 200
$btnClearMask = New-ClearButton $clearX $y
$y += 32
New-Label 'Gateway (optional):' $leftX $y | Out-Null
$txtGateway = New-TextBox $fieldX $y 200
$btnClearGateway = New-ClearButton $clearX $y
$y += 44

# --- Action buttons ---
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = 'Apply Static IP'
$btnApply.Location = New-Object System.Drawing.Point($leftX, $y)
$btnApply.Size = New-Object System.Drawing.Size(150, 34)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255)
$form.Controls.Add($btnApply)

$btnDhcp = New-Object System.Windows.Forms.Button
$btnDhcp.Text = 'Set to DHCP (Auto)'
$btnDhcp.Location = New-Object System.Drawing.Point(178, $y)
$btnDhcp.Size = New-Object System.Drawing.Size(150, 34)
$form.Controls.Add($btnDhcp)

$y += 38

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point($leftX, $y)
$lblStatus.Size = New-Object System.Drawing.Size(428, 36)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
$form.Controls.Add($lblStatus)

# ---------------------------------------------------------------------------
# 5. Behaviour
# ---------------------------------------------------------------------------
function Get-SelectedIfIndex {
    if ($cboAdapter.SelectedItem) { return [int]$cboAdapter.SelectedItem.IfIndex }
    return $null
}

function Update-Adapters {
    $prev = if ($cboAdapter.SelectedItem) { $cboAdapter.SelectedItem.IfIndex } else { $null }
    $cboAdapter.Items.Clear()
    Get-NetAdapter -ErrorAction SilentlyContinue |
        Sort-Object @{E = { $_.Status -ne 'Up' }}, Name |
        ForEach-Object {
            $cboAdapter.Items.Add([PSCustomObject]@{
                Display = "$($_.Name)  -  $($_.InterfaceDescription) [$($_.Status)]"
                IfIndex = $_.ifIndex
                Name    = $_.Name
            }) | Out-Null
        }
    if ($cboAdapter.Items.Count -gt 0) {
        $match = $null
        if ($prev) { $match = $cboAdapter.Items | Where-Object { $_.IfIndex -eq $prev } | Select-Object -First 1 }
        $cboAdapter.SelectedItem = if ($match) { $match } else { $cboAdapter.Items[0] }
    }
}

# Reads the live IPv4 settings off the selected adapter (used by both the
# read-out and the Auto-fill button).
function Get-CurrentConfig {
    $idx = Get-SelectedIfIndex
    if (-not $idx) { return $null }
    $ipObj = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    $ifCfg = Get-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $gwObj = Get-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Select-Object -First 1
    [PSCustomObject]@{
        HasIP   = [bool]$ipObj
        IP      = if ($ipObj) { $ipObj.IPAddress } else { '' }
        Mask    = if ($ipObj) { ConvertTo-SubnetMask $ipObj.PrefixLength } else { '' }
        Gateway = if ($gwObj) { $gwObj.NextHop } else { '' }
        IsDhcp  = [bool]($ifCfg -and $ifCfg.Dhcp -eq 'Enabled')
    }
}

function Update-CurrentConfig {
    $c = Get-CurrentConfig
    if (-not $c) { $lblCurrent.Text = ''; return }
    $mode = if ($c.IsDhcp) { 'DHCP (Automatic)' } else { 'Static (Manual)' }
    if ($c.HasIP) {
        $gw = if ($c.Gateway) { $c.Gateway } else { '(none)' }
        $lblCurrent.Text = "IP:      $($c.IP)`r`nMask:    $($c.Mask)`r`nGateway: $gw    Mode: $mode"
    } else {
        $lblCurrent.Text = "No IPv4 address assigned.`r`nMode: $mode"
    }
}

function Update-ProfileList {
    $cboProfile.Items.Clear()
    $cboProfile.Items.Add('') | Out-Null
    foreach ($p in Load-Profiles) { if ($p.Name) { $cboProfile.Items.Add($p.Name) | Out-Null } }
}

# Auto-suggest subnet mask when an IP is typed and mask is blank (classic Windows behaviour)
$txtIP.Add_Leave({
    if ((Test-IPv4 $txtIP.Text) -and [string]::IsNullOrWhiteSpace($txtMask.Text)) {
        $txtMask.Text = Get-ClassfulMask $txtIP.Text
    }
})

$cboAdapter.Add_SelectedIndexChanged({ Update-CurrentConfig })
$btnRefresh.Add_Click({ Update-Adapters; Update-CurrentConfig })

$cboProfile.Add_SelectedIndexChanged({
    $name = $cboProfile.SelectedItem
    if (-not $name) { return }
    $p = Load-Profiles | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($p) {
        $txtIP.Text = $p.IP; $txtMask.Text = $p.Mask; $txtGateway.Text = $p.Gateway
    }
})

$btnSaveProfile.Add_Click({
    if (-not (Test-IPv4 $txtIP.Text)) { [System.Windows.Forms.MessageBox]::Show('Enter a valid IP address before saving a preset.', 'Network IP Changer') | Out-Null; return }
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name for this preset:', 'Save Preset', $cboProfile.SelectedItem)
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $profiles = @(Load-Profiles | Where-Object { $_.Name -ne $name })
    $profiles += [PSCustomObject]@{ Name = $name; IP = $txtIP.Text; Mask = $txtMask.Text; Gateway = $txtGateway.Text }
    Save-Profiles $profiles
    Update-ProfileList
    $cboProfile.SelectedItem = $name
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
    $lblStatus.Text = "Saved preset '$name'."
})

$btnDeleteProfile.Add_Click({
    $name = $cboProfile.SelectedItem
    if (-not $name) { return }
    if ([System.Windows.Forms.MessageBox]::Show("Delete preset '$name'?", 'Network IP Changer', 'YesNo', 'Question') -ne 'Yes') { return }
    Save-Profiles @(Load-Profiles | Where-Object { $_.Name -ne $name })
    Update-ProfileList
    $lblStatus.Text = "Deleted preset '$name'."
})

# Auto-fill: copy the adapter's live IP/mask/gateway into the entry fields below,
# handy for saving a preset or tweaking just one field without retyping everything.
$btnAutofill.Add_Click({
    if (-not $cboAdapter.SelectedItem) { [System.Windows.Forms.MessageBox]::Show('Select a network adapter first.', 'Network IP Changer') | Out-Null; return }
    $c = Get-CurrentConfig
    if (-not $c -or -not $c.HasIP) {
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
        $lblStatus.Text = 'This adapter has no active IPv4 config to auto-fill.'
        return
    }
    $txtIP.Text = $c.IP; $txtMask.Text = $c.Mask; $txtGateway.Text = $c.Gateway
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
    $lblStatus.Text = "Filled fields from current config of '$($cboAdapter.SelectedItem.Name)'."
})

$btnClearIP.Add_Click({ $txtIP.Clear() })
$btnClearMask.Add_Click({ $txtMask.Clear() })
$btnClearGateway.Add_Click({ $txtGateway.Clear() })

$btnApply.Add_Click({
    $idx = Get-SelectedIfIndex
    if (-not $idx) { [System.Windows.Forms.MessageBox]::Show('Select a network adapter first.', 'Network IP Changer') | Out-Null; return }
    if (-not (Test-IPv4 $txtIP.Text))   { [System.Windows.Forms.MessageBox]::Show('Enter a valid IPv4 address (e.g. 192.168.1.50).', 'Network IP Changer') | Out-Null; return }
    if ([string]::IsNullOrWhiteSpace($txtMask.Text)) { $txtMask.Text = Get-ClassfulMask $txtIP.Text }
    $prefix = ConvertTo-PrefixLength $txtMask.Text
    if ($null -eq $prefix) { [System.Windows.Forms.MessageBox]::Show('Subnet mask is not valid (e.g. 255.255.255.0).', 'Network IP Changer') | Out-Null; return }
    $gw = $txtGateway.Text.Trim()
    if ($gw -and -not (Test-IPv4 $gw)) { [System.Windows.Forms.MessageBox]::Show('Gateway is not a valid IPv4 address. Leave it blank if you do not need one.', 'Network IP Changer') | Out-Null; return }

    try {
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        $params = @{ InterfaceIndex = $idx; IPAddress = $txtIP.Text; PrefixLength = $prefix; AddressFamily = 'IPv4'; ErrorAction = 'Stop' }
        if ($gw) { $params.DefaultGateway = $gw }
        New-NetIPAddress @params | Out-Null

        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
        $lblStatus.Text = "Applied $($txtIP.Text) / $($txtMask.Text) to '$($cboAdapter.SelectedItem.Name)'."
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
        $lblStatus.Text = "Error: $($_.Exception.Message)"
    }
    Update-CurrentConfig
})

$btnDhcp.Add_Click({
    $idx = Get-SelectedIfIndex
    if (-not $idx) { [System.Windows.Forms.MessageBox]::Show('Select a network adapter first.', 'Network IP Changer') | Out-Null; return }
    try {
        Get-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Enabled -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction SilentlyContinue
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
        $lblStatus.Text = "'$($cboAdapter.SelectedItem.Name)' set to DHCP (Automatic)."
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
        $lblStatus.Text = "Error: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 400
    Update-CurrentConfig
})

# Needed for the InputBox used when saving a preset
Add-Type -AssemblyName Microsoft.VisualBasic

# ---------------------------------------------------------------------------
# 6. Go
# ---------------------------------------------------------------------------
Update-Adapters
Update-ProfileList
Update-CurrentConfig
[System.Windows.Forms.Application]::Run($form)
