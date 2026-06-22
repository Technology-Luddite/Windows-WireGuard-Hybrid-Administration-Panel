<#
    .SYNOPSIS
        WireGuard Administration Panel - Unified Edition (v1.0)
    .NOTES
        Must be run as Administrator. Supports running directly as a .ps1 script
        or compiled as a standalone .exe binary via ps2exe. Self-extracts its own
        taskbar and title bar icon when compiled.
#>

# Ensure WinForms and Visual Styles are loaded
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- DYNAMIC RUNTIME PATH & PROCESS RESOLUTION ---
$IsCompiledExe = $false
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Running as a raw .ps1 script file
    $CurrentModuleRoot = $PSScriptRoot
} else {
    # Running compiled inside an .exe wrapper (resolves parent folder of the binary)
    $IsCompiledExe = $true
    $CurrentModuleRoot = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

# --- STATE CONFIGURATION ---
$SecureRootDir   = Join-Path $env:ProgramData "WireGuard"
$ConfigVault     = Join-Path $SecureRootDir "Data\Configurations"
$StateFilePath   = Join-Path $SecureRootDir "wg_server_state.json"
$WgInstallPath   = "C:\Program Files\WireGuard\wg.exe"
$WgServicePath   = "C:\Program Files\WireGuard\wireguard.exe"
$ServerConfig    = Join-Path $ConfigVault "wg0.conf"
$InterfaceName   = "wg0"
$ServiceName     = "WireGuardTunnel`$$InterfaceName"
$ClientFolder    = Join-Path $CurrentModuleRoot "Clients"  # Dynamic folder path reference

$GlobalServerPrivateKey = "UIdR4djFuIpuJ7qi1dfuBfwGHXGrAKJyL3nlVy6nzHM="

if (-not (Test-Path $SecureRootDir)) { New-Item -ItemType Directory -Path $SecureRootDir -Force | Out-Null }
if (-not (Test-Path $ConfigVault)) { New-Item -ItemType Directory -Path $ConfigVault -Force | Out-Null }
if (-not (Test-Path $ClientFolder)) { New-Item -ItemType Directory -Path $ClientFolder -Force | Out-Null }

# -------------------------------------------------------------------------
# BACKEND UTILITIES & ROUTING DETECTION
# -------------------------------------------------------------------------

Function Test-NetNatSupport {
    try {
        $null = Get-Command -Name "Get-NetNat" -ErrorAction Stop
        $null = Get-CimClass -ClassName "MSFT_NetNat" -Namespace "root\StandardCimv2" -ErrorAction Stop
        return $true
    } catch { return $false }
}

Function Enable-IcsRouting {
    param([string]$PublicAdapterName, [string]$PrivateAdapterName)
    try {
        $NetSharingManager = New-Object -ComObject HnetCfg.HNetShare
        $PublicConnection = $null; $PrivateConnection = $null
        foreach ($connection in $NetSharingManager.EnumEveryConnection) {
            $props = $NetSharingManager.NetConnectionProps($connection)
            if ($props.Name -eq $PublicAdapterName) { $PublicConnection = $NetSharingManager.INetSharingConfigurationForINetConnection($connection) }
            if ($props.Name -eq $PrivateAdapterName) { $PrivateConnection = $NetSharingManager.INetSharingConfigurationForINetConnection($connection) }
        }
        if ($null -ne $PublicConnection) { $PublicConnection.DisableSharing() | Out-Null; $PublicConnection.EnableSharing(0) | Out-Null }
        if ($null -ne $PrivateConnection) { $PrivateConnection.DisableSharing() | Out-Null; $PrivateConnection.EnableSharing(1) | Out-Null }
        return $true
    } catch { return $false }
}

Function Disable-IcsRouting {
    try {
        $NetSharingManager = New-Object -ComObject HnetCfg.HNetShare
        foreach ($connection in $NetSharingManager.EnumEveryConnection) {
            $config = $NetSharingManager.INetSharingConfigurationForINetConnection($connection)
            if ($config.SharingEnabled) { $config.DisableSharing() | Out-Null }
        }
    } catch {}
}

Function Get-WireGuardStatus {
    if (Test-Path $WgInstallPath) {
        $Svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Svc -and $Svc.Status -eq 'Running') { return "Active (Tunnel Live)" }
        return "Installed (Stopped)"
    } else { return "Not Found (Action Required)" }
}

Function Get-RandomClientName {
    return "RemoteWorker_$((Get-Random -Minimum 1000 -Maximum 9999))"
}

Function Update-ButtonStates {
    $Status = Get-WireGuardStatus
    $lblStatusValue.Text = $Status
    if ($Status -like "Active*") {
        $lblStatusValue.ForeColor = [System.Drawing.Color]::Green
        $btnPreFlight.Enabled     = $false
        $btnProvision.Enabled    = $false
    } else {
        $lblStatusValue.ForeColor = [System.Drawing.Color]::Red
        $btnPreFlight.Enabled     = $true
        $btnProvision.Enabled    = (Test-Path $WgInstallPath)
    }
}

Function Get-PublicKeyFromPrivate {
    param([string]$PrivateKey)
    if (Test-Path $WgInstallPath) {
        $pInfoPub = New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName = $WgInstallPath; Arguments = "pubkey"; RedirectStandardInput = $true; RedirectStandardOutput = $true; UseShellExecute = $false; CreateNoWindow = $true }
        $procPub = [System.Diagnostics.Process]::Start($pInfoPub); $procPub.StandardInput.WriteLine($PrivateKey); $procPub.StandardInput.Close()
        $PublicKey = $procPub.StandardOutput.ReadToEnd().Trim(); $procPub.WaitForExit()
        return $PublicKey
    }
    return "pG6XbZff68K4VkWG2v6zK7Xb89JK4vkWv2R6zMk7mXE="
}

Function New-WireGuardKeyPair {
    if (Test-Path $WgInstallPath) {
        $pInfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName = $WgInstallPath; Arguments = "genkey"; RedirectStandardOutput = $true; UseShellExecute = $false; CreateNoWindow = $true }
        $proc = [System.Diagnostics.Process]::Start($pInfo); $PrivateKey = $proc.StandardOutput.ReadToEnd().Trim(); $proc.WaitForExit()
        $PublicKey = Get-PublicKeyFromPrivate -PrivateKey $PrivateKey
    } else { $PrivateKey = "UIdR4djFuIpuJ7qi1dfuBfwGHXGrAKJyL3nlVy6nzHM="; $PublicKey  = "pG6XbZff68K4VkWG2v6zK7Xb89JK4vkWv2R6zMk7mXE=" }
    return [PSCustomObject]@{ PrivateKey = $PrivateKey; PublicKey = $PublicKey }
}

Function Sync-WireGuardServerConfiguration {
    $ServerPrivateKey = $GlobalServerPrivateKey
    if (Test-Path $ServerConfig) {
        $Match = (Get-Content -Path $ServerConfig -Raw) -match "PrivateKey\s*=\s*(?<Key>[A-Za-z0-9+/=]+)"
        if ($Match) { $ServerPrivateKey = $Matches.Key.Trim() }
    }
    $IsUsingICS = (-not (Test-NetNatSupport))
    $TargetSubnet = if ($IsUsingICS) { "192.168.137.1" } else { "10.10.0.1" }

    $NewServerBlock = "[Interface]`r`nPrivateKey = $ServerPrivateKey`r`nAddress = $TargetSubnet/24`r`nListenPort = 51820`r`n`r`n"
    $ClientFiles = Get-ChildItem -Path $ClientFolder -Filter "*.conf"
    foreach ($File in $ClientFiles) {
        $Text = Get-Content -Path $File.FullName -Raw
        $HasPublicKey = $Text -match "#\s*PublicKeyReference:\s*(?<Pub>[A-Za-z0-9+/=]+)"
        $ClientPublicKey = if ($HasPublicKey) { $Matches.Pub.Trim() } else { "" }
        $HasAddress = $Text -match "Address\s*=\s*(?<IPAddress>[0-9./]+)"
        $IPAlloc = if ($HasAddress) { $Matches.IPAddress.Trim() -replace '/\d+', '' } else { if ($IsUsingICS) { "192.168.137.5" } else { "10.10.0.5" } }
        if ($ClientPublicKey) { $NewServerBlock += "[Peer]`r`n# UserProfileIdentity: $($File.BaseName)`r`nPublicKey = $ClientPublicKey`r`nAllowedIPs = $IPAlloc/32`r`n`r`n" }
    }
    [System.IO.File]::WriteAllText($ServerConfig, $NewServerBlock, (New-Object System.Text.UTF8Encoding($false)))
}

# -------------------------------------------------------------------------
# CORE OPERATIONS
# -------------------------------------------------------------------------

Function Invoke-PreFlightCheck {
    param([System.Windows.Forms.TextBox]$LogTextBox)
    $LogTextBox.AppendText("[*] Starting Pre-Flight Check...`r`n")
    if (Test-Path $WgInstallPath) {
        $LogTextBox.AppendText("[+] WireGuard installation detected at $WgInstallPath`r`n")
    } else {
        $LogTextBox.AppendText("[!] WireGuard missing. Downloading official installer...`r`n")
        try {
            $msiPath = Join-Path $env:TEMP "wireguard.msi"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://download.wireguard.com/windows-client/wireguard-amd64-1.1.msi" -OutFile $msiPath -ErrorAction Stop
            $process = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru
            if ($process.ExitCode -eq 0) { $LogTextBox.AppendText("[+] WireGuard installed successfully!`r`n") }
        } catch { $LogTextBox.AppendText("[-] Error during download/install: $_`r`n") }
    }
}

Function Invoke-ProvisionServer {
    param([System.Windows.Forms.TextBox]$LogTextBox)
    $LogTextBox.AppendText("[*] Provisioning Routing Architecture...`r`n")
    $PrimaryAdapter = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -notlike '*WireGuard*' -and $_.InterfaceAlias -notlike '*Loopback*' } | Select-Object -First 1
    $PrimaryAdapterAlias = $PrimaryAdapter.InterfaceAlias

    try {
        $null = New-NetFirewallRule -Name "WireGuard-Server" -DisplayName "WireGuard UDP Server Inbound" -Direction Inbound -Protocol UDP -LocalPort 51820 -Action Allow -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters" -Name "EnableRebootPersistConnection" -Value 1

        if (Test-NetNatSupport) {
            $LogTextBox.AppendText("[+] System supports Enterprise NetNAT. Initializing 10.10.0.0/24 subnet...`r`n")
            $null = New-NetNat -Name "WG_PassThrough_NAT" -InternalIPInterfaceAddressPrefix "10.10.0.0/24" -ErrorAction SilentlyContinue
        } else {
            $LogTextBox.AppendText("[!] NetNAT missing. Activating ICS fallback wrapper...`r`n")
            Sync-WireGuardServerConfiguration
            if (Test-Path $WgServicePath) {
                Start-Process -FilePath $WgServicePath -ArgumentList "/installtunnelservice `"$ServerConfig`"" -Wait -NoNewWindow
                Start-Sleep -Seconds 2
            }
            $Success = Enable-IcsRouting -PublicAdapterName $PrimaryAdapterAlias -PrivateAdapterName $InterfaceName
            if ($Success) { $LogTextBox.AppendText("[+] ICS Legacy Wrapper mapping complete. Subnet target: 192.168.137.0/24`r`n") }
        }
        $LogTextBox.AppendText("[+] Routing infrastructure successfully built.`r`n")
    } catch { $LogTextBox.AppendText("[-] Provisioning Error: $_`r`n") }
}

Function Invoke-NuclearRollback {
    param([System.Windows.Forms.TextBox]$LogTextBox)
    $LogTextBox.AppendText("[!] CRITICAL: Executing Full Nuclear Rollback Sequence...`r`n")
    
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        $LogTextBox.AppendText("[*] Stopping and unregistering WireGuard service tunnels...`r`n")
        $SvcExec = if (Test-Path $WgServicePath) { $WgServicePath } else { "wireguard.exe" }
        Start-Process -FilePath $SvcExec -ArgumentList "/uninstalltunnelservice $InterfaceName" -Wait -NoNewWindow
        Start-Sleep -Seconds 2
    }
    
    $LogTextBox.AppendText("[*] Tearing down routing engine architectures...`r`n")
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 0
    Remove-NetFirewallRule -Name "WireGuard-Server" -ErrorAction SilentlyContinue
    
    if (Test-NetNatSupport) { Remove-NetNat -Name "WG_PassThrough_NAT" -Confirm:$false -ErrorAction SilentlyContinue } else { Disable-IcsRouting }

    $LogTextBox.AppendText("[*] Purging secure configuration asset vaults...`r`n")
    if (Test-Path $ServerConfig) { Remove-Item $ServerConfig -Force }
    if (Test-Path $ClientFolder) { Remove-Item $ClientFolder -Recurse -Force -ErrorAction SilentlyContinue }

    $LogTextBox.AppendText("[*] Querying system registry rules for active WireGuard application tracks...`r`n")
    $UninstallSelection = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*WireGuard*" }
    if ($UninstallSelection) {
        foreach ($app in $UninstallSelection) {
            $LogTextBox.AppendText("[!] Launching silent uninstallation for application: $($app.DisplayName)...`r`n")
            if ($app.UninstallString -like "msiexec*") {
                $silentArgs = $app.UninstallString -replace "msiexec.exe", "" -replace "/I", "/X" -replace "/i", "/x"
                $silentArgs += " /qn /norestart"
                $process = Start-Process msiexec.exe -ArgumentList $silentArgs -Wait -PassThru
                $LogTextBox.AppendText("[+] MSI Execution dropped with Exit Code: $($process.ExitCode)`r`n")
            }
        }
    }
    $LogTextBox.AppendText("[+] Nuclear scrub absolute. System restored and application dropped.`r`n")
}

# --- WINDOWS FORM LAYOUT DESIGN ---
$MainForm = New-Object System.Windows.Forms.Form -Property @{ Text = "WireGuard Hybrid Administration Panel (v1.0)"; Size = New-Object System.Drawing.Size(850, 560); StartPosition = "CenterScreen"; FormBorderStyle = "FixedSingle"; MaximizeBox = $false }

# --- REFLECTION-BASED SELF-ICON EXTRACTION ---
if ($IsCompiledExe) {
    try {
        $RunningPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $MainForm.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($RunningPath)
    } catch {}
}

$TabControl = New-Object System.Windows.Forms.TabControl -Property @{ Size = New-Object System.Drawing.Size(810, 480); Location = New-Object System.Drawing.Point(12, 12) }

# TAB 1
$TabServer = New-Object System.Windows.Forms.TabPage -Property @{ Text = "Server Orchestration" }
$lblStatusTitle = New-Object System.Windows.Forms.Label -Property @{ Text = "WireGuard Engine Status:"; Location = New-Object System.Drawing.Point(20, 22); Size = New-Object System.Drawing.Size(200, 20); Font = New-Object System.Drawing.Font("Arial", 9.5, [System.Drawing.FontStyle]::Bold) }
$lblStatusValue = New-Object System.Windows.Forms.Label -Property @{ Text = ""; Location = New-Object System.Drawing.Point(220, 22); Size = New-Object System.Drawing.Size(250, 20); Font = New-Object System.Drawing.Font("Arial", 9.5, [System.Drawing.FontStyle]::Bold) }
$btnPreFlight = New-Object System.Windows.Forms.Button -Property @{ Text = "Run Pre-Flight Check"; Location = New-Object System.Drawing.Point(20, 60); Size = New-Object System.Drawing.Size(180, 35) }
$btnProvision = New-Object System.Windows.Forms.Button -Property @{ Text = "Provision Infrastructure"; Location = New-Object System.Drawing.Point(210, 60) ; Size = New-Object System.Drawing.Size(180, 35) }
$btnNuke      = New-Object System.Windows.Forms.Button -Property @{ Text = "Nuclear Rollback"; Location = New-Object System.Drawing.Point(600, 60); Size = New-Object System.Drawing.Size(180, 35); BackColor = [System.Drawing.Color]::MistyRose }
$txtLogs      = New-Object System.Windows.Forms.TextBox -Property @{ Multiline = $true; ScrollBars = "Vertical"; ReadOnly = $true; Location = New-Object System.Drawing.Point(20, 120); Size = New-Object System.Drawing.Size(760, 290); Font = New-Object System.Drawing.Font("Consolas", 9.0); BackColor = [System.Drawing.Color]::Black; ForeColor = [System.Drawing.Color]::LightGreen }

$btnPreFlight.Add_Click({ Invoke-PreFlightCheck -LogTextBox $txtLogs; Update-ButtonStates })
$btnProvision.Add_Click({ Invoke-ProvisionServer -LogTextBox $txtLogs; Update-ButtonStates })
$btnNuke.Add_Click({ if ([System.Windows.Forms.MessageBox]::Show("Are you sure?", "Confirm App Purge", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning) -eq "Yes") { Invoke-NuclearRollback -LogTextBox $txtLogs; Update-ButtonStates } })
$TabServer.Controls.AddRange(@($lblStatusTitle, $lblStatusValue, $btnPreFlight, $btnProvision, $btnNuke, $txtLogs))

# TAB 2
$TabClient = New-Object System.Windows.Forms.TabPage -Property @{ Text = "Add New Client" }
$lblClientName = New-Object System.Windows.Forms.Label -Property @{ Text = "Profile Identifier Name:"; Location = New-Object System.Drawing.Point(20, 25); Size = New-Object System.Drawing.Size(180, 20) }
$txtClientName = New-Object System.Windows.Forms.TextBox -Property @{ Text = Get-RandomClientName; Location = New-Object System.Drawing.Point(200, 22); Size = New-Object System.Drawing.Size(250, 20) }
$btnGenClient  = New-Object System.Windows.Forms.Button -Property @{ Text = "Generate Client Profile"; Location = New-Object System.Drawing.Point(20, 70); Size = New-Object System.Drawing.Size(220, 40) }
$txtClientOutput = New-Object System.Windows.Forms.TextBox -Property @{ Multiline = $true; ScrollBars = "Vertical"; ReadOnly = $true; Location = New-Object System.Drawing.Point(20, 130); Size = New-Object System.Drawing.Size(760, 290); Font = New-Object System.Drawing.Font("Consolas", 9.0) }

$btnGenClient.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtClientName.Text)) { return }
    $TargetIdentifier = $txtClientName.Text.Trim(); $ClientOutPath = Join-Path $ClientFolder "$TargetIdentifier.conf"; $txtClientOutput.Clear()
    $ActiveServerPrivateKey = $GlobalServerPrivateKey
    if (Test-Path $ServerConfig) {
        $Match = (Get-Content -Path $ServerConfig -Raw) -match "PrivateKey\s*=\s*(?<Key>[A-Za-z0-9+/=]+)"
        if ($Match) { $ActiveServerPrivateKey = $Matches.Key.Trim() }
    }
    $TrueServerPublicKey = Get-PublicKeyFromPrivate -PrivateKey $ActiveServerPrivateKey
    $ClientKeys = New-WireGuardKeyPair
    
    # --- AUTOMATED WAN DISCOVERY ---
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $WebClient = New-Object System.Net.WebClient
    $ResolvedWAN = ""

    $HardwareAdapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*WireGuard*' -and $_.InterfaceAlias -notlike '*Loopback*' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1
    $BackupIP = if ($null -ne $HardwareAdapter) { $HardwareAdapter.IPAddress } else { "192.168.200.44" }

    try { 
        $ResolvedWAN = ($WebClient.DownloadString("https://api.ipify.org")).Trim() 
    } catch {
        try { 
            $ResolvedWAN = ($WebClient.DownloadString("https://icanhazip.com")).Trim() 
        } catch {
            $UserPrompt = [Microsoft.VisualBasic.Interaction]::InputBox("Automated internet lookup failed. Enter Server IP or Hostname:", "WAN Address Entry", $BackupIP)
            if (-not [string]::IsNullOrWhiteSpace($UserPrompt)) { 
                $ResolvedWAN = $UserPrompt.Trim() 
            } else { 
                $ResolvedWAN = $BackupIP 
            }
        }
    }
    
    if ($ResolvedWAN -match "<html" -or [string]::IsNullOrWhiteSpace($ResolvedWAN)) {
        $ResolvedWAN = $BackupIP
    }

    $ExistingPeers = Get-ChildItem -Path $ClientFolder -Filter "*.conf"
    $AssignedIPSlot = 5 + $ExistingPeers.Count
    $ClientIP = if (-not (Test-NetNatSupport)) { "192.168.137.$AssignedIPSlot" } else { "10.10.0.$AssignedIPSlot" }
    
    $ClientBlock = "# --- Client Profile ---`r`n# Identifier: $TargetIdentifier`r`n# PublicKeyReference: $($ClientKeys.PublicKey)`r`n`r`n[Interface]`r`nPrivateKey = $($ClientKeys.PrivateKey)`r`nAddress = $ClientIP/24`r`nDNS = 9.9.9.9`r`n`r`n[Peer]`r`nPublicKey = $TrueServerPublicKey`r`nEndpoint = $($ResolvedWAN):51820`r`nAllowedIPs = 0.0.0.0/0`r`n"
    [System.IO.File]::WriteAllText($ClientOutPath, $ClientBlock, (New-Object System.Text.UTF8Encoding($false)))
    $txtClientOutput.AppendText("[+] FILE EXPORT SUCCESS:`r`n -> $ClientOutPath`r`n`r`n$ClientBlock")
    Sync-WireGuardServerConfiguration
    $ActiveService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($ActiveService -and $ActiveService.Status -eq 'Running') {
        if (Test-Path $WgInstallPath) { Start-Process -FilePath $WgInstallPath -ArgumentList "set $InterfaceName peer $($ClientKeys.PublicKey) allowed-ips $ClientIP/32" -Wait -NoNewWindow }
    } else { if (Test-Path $WgServicePath) { Start-Process -FilePath $WgServicePath -ArgumentList "/installtunnelservice `"$ServerConfig`"" -Wait -NoNewWindow } }
    $txtClientName.Text = Get-RandomClientName; Update-ButtonStates
    if ($null -ne $RefreshPeerListEngine) { &$RefreshPeerListEngine }
})
$TabClient.Controls.AddRange(@($lblClientName, $txtClientName, $btnGenClient, $txtClientOutput))

# TAB 3
$TabManage = New-Object System.Windows.Forms.TabPage -Property @{ Text = "Manage Clients" }
$lstPeers   = New-Object System.Windows.Forms.ListBox -Property @{ Location = New-Object System.Drawing.Point(20, 40); Size = New-Object System.Drawing.Size(350, 140) }
$btnDeleteClient = New-Object System.Windows.Forms.Button -Property @{ Text = "Remove Selected Client"; Location = New-Object System.Drawing.Point(390, 80); Size = New-Object System.Drawing.Size(160, 35); BackColor = [System.Drawing.Color]::MistyRose }
$txtViewConfig = New-Object System.Windows.Forms.TextBox -Property @{ Multiline = $true; ScrollBars = "Vertical"; ReadOnly = $true; Location = New-Object System.Drawing.Point(20, 215); Size = New-Object System.Drawing.Size(760, 195); Font = New-Object System.Drawing.Font("Consolas", 9.0); BackColor = [System.Drawing.Color]::WhiteSmoke }

$RefreshPeerListEngine = {
    $lstPeers.Items.Clear(); $txtViewConfig.Clear()
    if (Test-Path $ClientFolder) { foreach ($F in (Get-ChildItem -Path $ClientFolder -Filter "*.conf")) { [void]$lstPeers.Items.Add($F.BaseName) } }
}
$lstPeers.Add_SelectedIndexChanged({ if ($null -ne $lstPeers.SelectedItem) { $FileTarget = Join-Path $ClientFolder "$($lstPeers.SelectedItem.ToString()).conf"; if (Test-Path $FileTarget) { $txtViewConfig.Text = Get-Content -Path $FileTarget -Raw } } })
$btnDeleteClient.Add_Click({
    if ($null -eq $lstPeers.SelectedItem) { return }
    $SelectedProfile = $lstPeers.SelectedItem.ToString(); $TargetConfFile = Join-Path $ClientFolder "$SelectedProfile.conf"; $PublicKeyToRevoke = $null
    if (Test-Path $TargetConfFile) {
        $TextContent = Get-Content -Path $TargetConfFile -Raw
        if ($TextContent -match "#\s*PublicKeyReference:\s*(?<Pub>[A-Za-z0-9+/=]+)") { $PublicKeyToRevoke = $Matches.Pub.Trim() }
        Remove-Item -Path $TargetConfFile -Force
    }
    if ($PublicKeyToRevoke -and ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -eq 'Running')) {
        if (Test-Path $WgInstallPath) { Start-Process -FilePath $WgInstallPath -ArgumentList "set $InterfaceName peer $PublicKeyToRevoke remove" -Wait -NoNewWindow }
    }
    Sync-WireGuardServerConfiguration; Update-ButtonStates; &$RefreshPeerListEngine
})
$TabManage.Controls.AddRange(@($lstPeers, $btnDeleteClient, $txtViewConfig))

# TAB 4
$TabMonitor = New-Object System.Windows.Forms.TabPage -Property @{ Text = "Live Tunnel Dashboard" }
$btnRefreshMonitor = New-Object System.Windows.Forms.Button -Property @{ Text = "Query Live Kernel Diagnostics"; Location = New-Object System.Drawing.Point(20, 20); Size = New-Object System.Drawing.Size(240, 35) }
$txtMonitor        = New-Object System.Windows.Forms.TextBox -Property @{ Multiline = $true; ScrollBars = "Vertical"; ReadOnly = $true; Location = New-Object System.Drawing.Point(20, 70); Size = New-Object System.Drawing.Size(760, 340); Font = New-Object System.Drawing.Font("Consolas", 9.5); BackColor = [System.Drawing.Color]::MidnightBlue; ForeColor = [System.Drawing.Color]::White }

$btnRefreshMonitor.Add_Click({
    $txtMonitor.Clear()
    if (Test-Path $WgInstallPath) {
        $pInfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName = $WgInstallPath; Arguments = "show"; RedirectStandardOutput = $true; UseShellExecute = $false; CreateNoWindow = $true }
        $proc = [System.Diagnostics.Process]::Start($pInfo); $txtMonitor.Text = $proc.StandardOutput.ReadToEnd(); $proc.WaitForExit()
    }
})
$TabMonitor.Controls.AddRange(@($btnRefreshMonitor, $txtMonitor))

$TabControl.Controls.AddRange(@($TabServer, $TabClient, $TabManage, $TabMonitor))
$MainForm.Controls.Add($TabControl)

Update-ButtonStates; &$RefreshPeerListEngine
$MainForm.ShowDialog() | Out-Null