#requires -Version 5.1
<#
    Device Info Dashboard
    Generates a modern HTML dashboard with three pages: Device, Kaspersky, Battery
    Requires Administrator privileges
#>

$ErrorActionPreference = "SilentlyContinue"

# ================================================================
# ADMINISTRATOR CHECK (NON-BLOCKING)
# ================================================================

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Note: Running without Administrator privileges." -ForegroundColor Yellow
    Write-Host "Some features (KSC connection, license, Secure Boot) may be limited." -ForegroundColor Yellow
    Write-Host "For full results, right-click and 'Run as administrator'." -ForegroundColor Yellow
    Write-Host ""
}

# ================================================================
# DATA COLLECTION FUNCTIONS
# ================================================================

function Get-DeviceInfo {
    $info = @{}

    # System
    $cs = Get-CimInstance Win32_ComputerSystem
    $cp = Get-CimInstance Win32_ComputerSystemProduct
    $bios = Get-CimInstance Win32_BIOS
    $info.ComputerName = $env:COMPUTERNAME
    $info.UserName = $env:USERNAME
    $info.Manufacturer = $cs.Manufacturer
    $info.Model = $cs.Model
    $info.ProductName = $cp.Name
    $info.SerialNumber = $bios.SerialNumber
    $info.BIOS = $bios.SMBIOSBIOSVersion

    # Windows
    $os = Get-CimInstance Win32_OperatingSystem
    $info.OSEdition = $os.Caption
    $info.OSVersion = $os.Version
    $info.OSBuild = $os.BuildNumber
    $info.OSArch = $os.OSArchitecture

    # Windows License
    $lic = Get-CimInstance SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -like 'Windows*' } | Select-Object -First 1
    if ($lic) {
        $info.LicenseDescription = $lic.Description
        $info.LicensePartialKey = $lic.PartialProductKey
        $info.LicenseStatus = if ($lic.LicenseStatus -eq 1) { "ACTIVATED" } else { "NOT ACTIVATED" }
    } else {
        $info.LicenseDescription = "Not detected"
        $info.LicensePartialKey = "-"
        $info.LicenseStatus = "UNKNOWN"
    }

    # Product Keys
    $reg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    $info.RegistryKey = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).BackupProductKeyDefault
    if (-not $info.RegistryKey) { $info.RegistryKey = "Not available" }
    $oa3 = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3OriginalProductKey
    $info.BIOSKey = if ($oa3) { $oa3 } else { "Not available" }

    # CPU
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $info.CPUName = $cpu.Name
    $info.CPUCores = $cpu.NumberOfCores
    $info.CPUThreads = $cpu.NumberOfLogicalProcessors
    $info.CPUMaxSpeed = $cpu.MaxClockSpeed

    # RAM
    $info.TotalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $info.RAMModules = @()
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $info.RAMModules += [PSCustomObject]@{
            Capacity = [math]::Round($_.Capacity / 1GB, 2)
            Speed    = $_.Speed
            Manufacturer = $_.Manufacturer
        }
    }

    # GPU
    $info.GPUs = @()
    Get-CimInstance Win32_VideoController | ForEach-Object {
        $info.GPUs += [PSCustomObject]@{
            Name = $_.Name
            Driver = $_.DriverVersion
        }
    }

    # Storage
    $info.Disks = @()
    Get-CimInstance Win32_DiskDrive | ForEach-Object {
        $info.Disks += [PSCustomObject]@{
            Model = $_.Model
            Size = [math]::Round($_.Size / 1GB, 2)
        }
    }
    $info.LogicalDrives = @()
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $info.LogicalDrives += [PSCustomObject]@{
            Drive = $_.DeviceID
            Total = [math]::Round($_.Size / 1GB, 2)
            Free = [math]::Round($_.FreeSpace / 1GB, 2)
            Used = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
            PercentUsed = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
        }
    }

    # Network - Wi-Fi
    $wifi = Get-NetAdapter | Where-Object { $_.Name -match 'Wi-Fi|Wireless' }
    $info.WiFi = @()
    if ($wifi) {
        foreach ($n in $wifi) {
            $ip = Get-NetIPAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1
            $gw = (Get-NetIPConfiguration -InterfaceIndex $n.ifIndex).IPv4DefaultGateway.NextHop
            $info.WiFi += [PSCustomObject]@{
                Name = $n.Name
                Status = $n.Status
                MAC = $n.MacAddress
                IPv4 = if ($ip) { $ip.IPAddress } else { "Not connected" }
                Gateway = if ($gw) { $gw } else { "Not connected" }
            }
        }
    }

    # Network - LAN
    $lan = Get-NetAdapter -Physical | Where-Object { $_.Name -notmatch 'Wi-Fi|Wireless|Bluetooth' }
    $info.LAN = @()
    if ($lan) {
        foreach ($n in $lan) {
            $ip = Get-NetIPAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1
            $gw = (Get-NetIPConfiguration -InterfaceIndex $n.ifIndex).IPv4DefaultGateway.NextHop
            $info.LAN += [PSCustomObject]@{
                Name = $n.Name
                Status = $n.Status
                MAC = $n.MacAddress
                IPv4 = if ($ip) { $ip.IPAddress } else { "Not connected" }
                Gateway = if ($gw) { $gw } else { "Not connected" }
            }
        }
    }

    # Domain
    $info.Domain = $cs.Domain
    $info.PartOfDomain = $cs.PartOfDomain

    # Office
    $info.Office = @()
    $uninstallPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $office = Get-ItemProperty $uninstallPaths | Where-Object { $_.DisplayName -match 'Microsoft 365|Microsoft Office|Office LTSC' }
    if ($office) {
        foreach ($o in $office) {
            $info.Office += [PSCustomObject]@{
                Name = $o.DisplayName
                Version = $o.DisplayVersion
            }
        }
    }

    # Security Diagnostics
    $tpm = Get-Tpm
    if ($tpm) {
        $info.TPMPresent = $tpm.TpmPresent
        $info.TPMReady = $tpm.TpmReady
    } else {
        $info.TPMPresent = $false
        $info.TPMReady = $false
    }

    try {
        $info.SecureBoot = (Confirm-SecureBootUEFI -ErrorAction Stop)
    } catch {
        $info.SecureBoot = "Not supported / Legacy BIOS"
    }

    $defender = Get-MpComputerStatus
    if ($defender) {
        $info.DefenderEnabled = $defender.AMServiceEnabled
        $info.RealTimeProtection = $defender.RealTimeProtectionEnabled
    } else {
        $info.DefenderEnabled = $false
        $info.RealTimeProtection = $false
    }

    $info.PhysicalDisks = @()
    Get-PhysicalDisk | ForEach-Object {
        $info.PhysicalDisks += [PSCustomObject]@{
            Name = $_.FriendlyName
            Health = $_.HealthStatus
            Type = $_.MediaType
        }
    }

    return $info
}

function Get-KasperskyInfo {
    $info = @{}
    $PF64 = ${env:ProgramFiles}
    $PF32 = ${env:ProgramFiles(x86)}

    # Find Kaspersky folders
    $folders = @()
    foreach ($root in @($PF64, $PF32, ${env:ProgramData})) {
        if ($root -and (Test-Path (Join-Path $root "Kaspersky Lab"))) {
            $folders += (Join-Path $root "Kaspersky Lab")
        }
    }

    # Services
    $allServices = Get-Service | Where-Object { $_.Name -match "kaspersky|klnagent|avp" -or $_.DisplayName -match "Kaspersky|Network Agent|Endpoint Security" }
    $info.KESService = $allServices | Where-Object { $_.Name -eq "AVP" -or $_.DisplayName -match "Kaspersky Endpoint Security" } | Select-Object -First 1
    $info.AgentService = $allServices | Where-Object { $_.Name -eq "klnagent" -or $_.DisplayName -match "Kaspersky.*Network Agent|Network Agent" } | Select-Object -First 1

    # AVP path
    $avpPath = $null
    foreach ($folder in $folders) {
        $found = Get-ChildItem -Path $folder -Filter "avp.com" -File -Recurse | Select-Object -First 1
        if ($found) { $avpPath = $found.FullName; break }
    }
    if (-not $avpPath) {
        $commonPaths = @(
            "$PF64\Kaspersky Lab\Kaspersky Endpoint Security for Windows\avp.com",
            "$PF32\Kaspersky Lab\Kaspersky Endpoint Security for Windows\avp.com",
            "$PF64\Kaspersky Lab\Kaspersky Endpoint Security 12\avp.com",
            "$PF32\Kaspersky Lab\Kaspersky Endpoint Security 12\avp.com"
        )
        foreach ($p in $commonPaths) { if (Test-Path $p) { $avpPath = $p; break } }
    }
    $info.AvpPath = $avpPath

    # KES Version
    $info.KESVersion = "NOT DETECTED"
    $info.KESVersionSource = ""
    if ($info.KESService) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$($info.KESService.Name)'"
        if ($svc -and $svc.PathName) {
            $exePath = $svc.PathName.Trim()
            if ($exePath -match '^"([^"]+)"') { $exePath = $Matches[1] }
            elseif ($exePath -match '^(.+?\.exe)') { $exePath = $Matches[1] }
            if ($exePath -and (Test-Path $exePath)) {
                $v = (Get-Item $exePath).VersionInfo
                if ($v.FileMajorPart -gt 0) {
                    $info.KESVersion = "$($v.FileMajorPart).$($v.FileMinorPart).$($v.FileBuildPart).$($v.FilePrivatePart)"
                    $info.KESVersionSource = "Running service executable"
                }
            }
        }
    }
    if ($info.KESVersion -eq "NOT DETECTED" -and $avpPath) {
        $avpExe = Join-Path (Split-Path $avpPath -Parent) "avp.exe"
        foreach ($c in @($avpExe, $avpPath)) {
            if ($c -and (Test-Path $c)) {
                $v = (Get-Item $c).VersionInfo
                if ($v.FileMajorPart -gt 0) {
                    $info.KESVersion = "$($v.FileMajorPart).$($v.FileMinorPart).$($v.FileBuildPart).$($v.FilePrivatePart)"
                    $info.KESVersionSource = "File version: $(Split-Path $c -Leaf)"
                    break
                }
            }
        }
    }

    # Network Agent Version
    $info.AgentVersion = "NOT DETECTED"
    $info.AgentVersionSource = ""
    $agentProduct = Get-ItemProperty @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') |
        Where-Object { $_.DisplayName -and $_.DisplayVersion -and $_.DisplayName -match "Network Agent" } |
        Sort-Object { try { [version]$_.DisplayVersion } catch { [version]"0.0" } } -Descending | Select-Object -First 1
    if ($agentProduct) {
        $info.AgentVersion = $agentProduct.DisplayVersion
        $info.AgentVersionSource = "Installed programs"
    }

    # klnagchk
    $klnagchkPath = $null
    foreach ($folder in $folders) {
        $found = Get-ChildItem -Path $folder -Filter "klnagchk.exe" -File -Recurse | Select-Object -First 1
        if ($found) { $klnagchkPath = $found.FullName; break }
    }
    if (-not $klnagchkPath) {
        $commonKln = @("$PF32\Kaspersky Lab\NetworkAgent\klnagchk.exe", "$PF64\Kaspersky Lab\NetworkAgent\klnagchk.exe")
        foreach ($p in $commonKln) { if (Test-Path $p) { $klnagchkPath = $p; break } }
    }
    $info.KlnagchkPath = $klnagchkPath

    # KSC Connection
    $info.AdminServer = "NOT DETECTED"
    $info.KSCConnection = "NOT CONNECTED"
    $info.LastSync = "NOT REPORTED"
    $info.TimeSinceConnection = ""

    if ($klnagchkPath -and $info.AgentService) {
        try {
            $output = & $klnagchkPath -sendhb 2>&1 | Out-String
            if ($output) {
                $m = [regex]::Match($output, "(?im)Administration Server address\s*[:=]\s*(.+)")
                if ($m.Success) { $info.AdminServer = $m.Groups[1].Value.Trim() }
                if ($output -match "(?i)connection.*established|connection.*successful|successfully connected|connection.*OK|connected.*Administration Server") {
                    $info.KSCConnection = "CONNECTED"
                }
                $t = [regex]::Match($output, "(?im)Date/time of the last request for synchronization\s*[:=]\s*(.+)")
                if ($t.Success) {
                    $info.LastSync = $t.Groups[1].Value.Trim()
                    try {
                        $parsed = $null
                        if ([DateTime]::TryParse($info.LastSync, [Globalization.CultureInfo]::CurrentCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                            $age = (Get-Date) - $parsed
                            if ($age.TotalSeconds -ge 0) {
                                $info.TimeSinceConnection = "{0:dd\.hh\:mm\:ss}" -f $age
                            }
                        }
                    } catch {}
                }
            }
        } catch {}
    }

    # License
    $info.LicenseStatus = "NOT AVAILABLE LOCALLY"
    if ($avpPath) {
        $licFound = $false
        foreach ($root in @("HKLM:\SOFTWARE\KasperskyLab", "HKLM:\SOFTWARE\WOW6432Node\KasperskyLab")) {
            if (Test-Path $root) {
                $keys = Get-ChildItem -Path $root -Recurse | Where-Object { $_.Name -match "License|Licensing|Activation" }
                if ($keys) { $licFound = $true; break }
            }
        }
        try {
            $licOut = & $avpPath license 2>&1 | Out-String
            if ($licOut -match "(?i)expired") { $info.LicenseStatus = "EXPIRED" }
            elseif ($licOut -match "(?i)active|valid") { $info.LicenseStatus = "ACTIVE / VALID" }
            elseif ($licFound) { $info.LicenseStatus = "INSTALLED" }
        } catch {
            if ($licFound) { $info.LicenseStatus = "INSTALLED" }
        }
    }

    # Connectivity
    $netTest = Test-NetConnection -ComputerName "activation-v2.kaspersky.com" -Port 443 -WarningAction SilentlyContinue
    $info.InternetAccess = if ($netTest.TcpTestSucceeded) { "AVAILABLE" } else { "NOT AVAILABLE" }

    # Overall status
    $kesOK = ($info.KESService -and $info.KESService.Status -eq "Running")
    $agentOK = ($info.AgentService -and $info.AgentService.Status -eq "Running")
    $serverOK = ($info.KSCConnection -eq "CONNECTED")
    $info.OverallStatus = if ($kesOK -and $agentOK -and $serverOK) { "HEALTHY" } else { "CHECK REQUIRED" }

    return $info
}

function Get-BatteryInfo {
    $info = @{}
    $reportPath = "$env:USERPROFILE\Desktop\battery-report.html"

    powercfg /batteryreport /output "$reportPath" | Out-Null

    if (Test-Path $reportPath) {
        $html = Get-Content $reportPath -Raw
        $designMatch = [regex]::Match($html, '(?i)DESIGN CAPACITY.*?([0-9,]+)\s*mWh')
        $fullMatch = [regex]::Match($html, '(?i)FULL CHARGE CAPACITY.*?([0-9,]+)\s*mWh')

        if ($designMatch.Success -and $fullMatch.Success) {
            $info.DesignCapacity = [double]($designMatch.Groups[1].Value -replace ',', '')
            $info.FullCapacity = [double]($fullMatch.Groups[1].Value -replace ',', '')
            $info.Health = ($info.FullCapacity / $info.DesignCapacity) * 100
            $info.DisplayHealth = [math]::Min($info.Health, 100)

            if ($info.Health -ge 90) { $info.Status = "EXCELLENT"; $info.StatusColor = "#00c853" }
            elseif ($info.Health -ge 80) { $info.Status = "GOOD"; $info.StatusColor = "#64dd17" }
            elseif ($info.Health -ge 60) { $info.Status = "FAIR"; $info.StatusColor = "#ffd600" }
            else { $info.Status = "WEAK"; $info.StatusColor = "#ff1744" }
        } else {
            $info.DesignCapacity = 0
            $info.FullCapacity = 0
            $info.Health = 0
            $info.DisplayHealth = 0
            $info.Status = "UNKNOWN"
            $info.StatusColor = "#9e9e9e"
        }
    } else {
        $info.DesignCapacity = 0
        $info.FullCapacity = 0
        $info.Health = 0
        $info.DisplayHealth = 0
        $info.Status = "NO BATTERY"
        $info.StatusColor = "#9e9e9e"
    }

    $info.ReportPath = $reportPath
    return $info
}

# ================================================================
# HTML GENERATION
# ================================================================

function ConvertTo-HtmlEscaped {
    param([string]$Text)
    if (-not $Text) { return "" }
    return $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}

function Get-StatusColor {
    param([string]$Status)
    switch -Regex ($Status.ToUpper()) {
        "ACTIVATED|RUNNING|CONNECTED|HEALTHY|AVAILABLE|EXCELLENT|GOOD|READY|ON|TRUE|INSTALLED|ACTIVE" { return "#00c853" }
        "NOT ACTIVATED|NOT CONNECTED|CHECK REQUIRED|NOT AVAILABLE|FAIR|EXPIRED|WEAK|PROBLEM" { return "#ff1744" }
        "NOT DETECTED|UNKNOWN|NOT SUPPORTED|LEGACY|NOT REPORTED|NO RESPONSE" { return "#ff9100" }
        default { return "#9e9e9e" }
    }
}

function Get-StatusIcon {
    param([string]$Status)
    switch -Regex ($Status.ToUpper()) {
        "ACTIVATED|RUNNING|CONNECTED|HEALTHY|AVAILABLE|EXCELLENT|GOOD|READY|ON|TRUE|INSTALLED|ACTIVE" { return "&#10003;" }
        "NOT ACTIVATED|NOT CONNECTED|CHECK REQUIRED|NOT AVAILABLE|FAIR|EXPIRED|WEAK|PROBLEM" { return "&#10007;" }
        "NOT DETECTED|UNKNOWN|NOT SUPPORTED|LEGACY|NOT REPORTED|NO RESPONSE" { return "&#9888;" }
        default { return "&#8226;" }
    }
}

function Generate-DevicePage {
    param($Data)

    $html = @"
    <div class="page-content">
        <!-- System Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128421;</span>
                <h3>System Information</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Computer Name</span><span class="value">$($Data.ComputerName)</span></div>
                    <div class="info-item"><span class="label">User</span><span class="value">$($Data.UserName)</span></div>
                    <div class="info-item"><span class="label">Manufacturer</span><span class="value">$($Data.Manufacturer)</span></div>
                    <div class="info-item"><span class="label">Model</span><span class="value">$($Data.Model)</span></div>
                    <div class="info-item"><span class="label">Product Name</span><span class="value">$($Data.ProductName)</span></div>
                    <div class="info-item"><span class="label">Serial Number</span><span class="value">$($Data.SerialNumber)</span></div>
                    <div class="info-item"><span class="label">BIOS Version</span><span class="value">$($Data.BIOS)</span></div>
                </div>
            </div>
        </div>

        <!-- Windows Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128187;</span>
                <h3>Windows</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Edition</span><span class="value">$($Data.OSEdition)</span></div>
                    <div class="info-item"><span class="label">Version</span><span class="value">$($Data.OSVersion)</span></div>
                    <div class="info-item"><span class="label">Build</span><span class="value">$($Data.OSBuild)</span></div>
                    <div class="info-item"><span class="label">Architecture</span><span class="value">$($Data.OSArch)</span></div>
                </div>
            </div>
        </div>

        <!-- License Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128273;</span>
                <h3>Windows License</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $Data.LicenseStatus)">$($Data.LicenseStatus)</span>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Description</span><span class="value">$($Data.LicenseDescription)</span></div>
                    <div class="info-item"><span class="label">Partial Key</span><span class="value">$($Data.LicensePartialKey)</span></div>
                    <div class="info-item"><span class="label">Registry Key</span><span class="value">$($Data.RegistryKey)</span></div>
                    <div class="info-item"><span class="label">BIOS Key</span><span class="value">$($Data.BIOSKey)</span></div>
                </div>
            </div>
        </div>

        <!-- CPU Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#9881;</span>
                <h3>Processor</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">CPU</span><span class="value">$($Data.CPUName)</span></div>
                    <div class="info-item"><span class="label">Cores</span><span class="value">$($Data.CPUCores)</span></div>
                    <div class="info-item"><span class="label">Threads</span><span class="value">$($Data.CPUThreads)</span></div>
                    <div class="info-item"><span class="label">Max Speed</span><span class="value">$($Data.CPUMaxSpeed) MHz</span></div>
                </div>
            </div>
        </div>

        <!-- RAM Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128190;</span>
                <h3>Memory (RAM)</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Total RAM</span><span class="value">$($Data.TotalRAM) GB</span></div>
                </div>
                $(if ($Data.RAMModules.Count -gt 0) {
                    "<table class='data-table'><thead><tr><th>Module</th><th>Capacity</th><th>Speed</th><th>Manufacturer</th></tr></thead><tbody>"
                    foreach ($mod in $Data.RAMModules) {
                        "<tr><td>RAM</td><td>$($mod.Capacity) GB</td><td>$($mod.Speed) MHz</td><td>$($mod.Manufacturer)</td></tr>"
                    }
                    "</tbody></table>"
                })
            </div>
        </div>

        <!-- GPU Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128444;</span>
                <h3>Graphics</h3>
            </div>
            <div class="card-body">
                $(if ($Data.GPUs.Count -gt 0) {
                    "<table class='data-table'><thead><tr><th>GPU</th><th>Driver Version</th></tr></thead><tbody>"
                    foreach ($gpu in $Data.GPUs) {
                        "<tr><td>$($gpu.Name)</td><td>$($gpu.Driver)</td></tr>"
                    }
                    "</tbody></table>"
                } else { "<p class='no-data'>No GPU detected</p>" })
            </div>
        </div>

        <!-- Storage Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128464;</span>
                <h3>Storage</h3>
            </div>
            <div class="card-body">
                $(if ($Data.Disks.Count -gt 0) {
                    "<h4>Physical Disks</h4><table class='data-table'><thead><tr><th>Model</th><th>Size</th></tr></thead><tbody>"
                    foreach ($d in $Data.Disks) { "<tr><td>$($d.Model)</td><td>$($d.Size) GB</td></tr>" }
                    "</tbody></table>"
                })
                $(if ($Data.LogicalDrives.Count -gt 0) {
                    "<h4>Logical Drives</h4><table class='data-table'><thead><tr><th>Drive</th><th>Total</th><th>Used</th><th>Free</th><th>Usage</th></tr></thead><tbody>"
                    foreach ($d in $Data.LogicalDrives) {
                        $barColor = if ($d.PercentUsed -gt 80) { "#ff1744" } elseif ($d.PercentUsed -gt 60) { "#ff9100" } else { "#00c853" }
                        "<tr><td>$($d.Drive)</td><td>$($d.Total) GB</td><td>$($d.Used) GB</td><td>$($d.Free) GB</td><td><div class='progress-bar'><div class='progress-fill' style='width: $($d.PercentUsed)%; background: $barColor'></div></div><span class='progress-text'>$($d.PercentUsed)%</span></td></tr>"
                    }
                    "</tbody></table>"
                })
            </div>
        </div>

        <!-- Network Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128246;</span>
                <h3>Network</h3>
            </div>
            <div class="card-body">
                $(if ($Data.WiFi.Count -gt 0) {
                    $wifiMACs = ($Data.WiFi | ForEach-Object { $_.MAC }) -join ' | '
                    $wifiInfo = ($Data.WiFi | ForEach-Object { "$($_.Name) ($($_.Status)) - $($_.IPv4) GW: $($_.Gateway)" }) -join '<br>'
                    "<h4>Wi-Fi</h4><div class='mac-line'>MAC: <strong>$wifiMACs</strong></div><div class='info-grid'><div class='info-item' style='grid-column: 1/-1'><span class='label'>Adapter</span><span class='value'>$wifiInfo</span></div></div>"
                } else { "<p class='no-data'>No Wi-Fi adapter detected</p>" })
                $(if ($Data.LAN.Count -gt 0) {
                    $lanMACs = ($Data.LAN | ForEach-Object { $_.MAC }) -join ' | '
                    $lanInfo = ($Data.LAN | ForEach-Object { "$($_.Name) ($($_.Status)) - $($_.IPv4) GW: $($_.Gateway)" }) -join '<br>'
                    "<h4>Ethernet / LAN</h4><div class='mac-line'>MAC: <strong>$lanMACs</strong></div><div class='info-grid'><div class='info-item' style='grid-column: 1/-1'><span class='label'>Adapter</span><span class='value'>$lanInfo</span></div></div>"
                } else { "<p class='no-data'>No Ethernet adapter detected</p>" })
            </div>
        </div>

        <!-- Domain Card -->
        <div class="card" style="margin-top: 20px; max-width: 400px;">
            <div class="card-header">
                <span class="card-icon">&#127760;</span>
                <h3>Domain</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Domain</span><span class="value">$($Data.Domain)</span></div>
                    <div class="info-item"><span class="label">Domain Joined</span><span class="value">$($Data.PartOfDomain)</span></div>
                </div>
            </div>
        </div>

        <!-- Office Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128196;</span>
                <h3>Microsoft Office</h3>
            </div>
            <div class="card-body">
                $(if ($Data.Office.Count -gt 0) {
                    "<table class='data-table'><thead><tr><th>Product</th><th>Version</th></tr></thead><tbody>"
                    foreach ($o in $Data.Office) { "<tr><td>$($o.Name)</td><td>$($o.Version)</td></tr>" }
                    "</tbody></table>"
                } else { "<p class='no-data'>Microsoft Office not detected</p>" })
            </div>
        </div>

        <!-- Security Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128737;</span>
                <h3>Security Diagnostics</h3>
            </div>
            <div class="card-body">
                <div class="security-grid">
                    <div class="security-item">
                        <span class="security-label">TPM Present</span>
                        <span class="security-value" style="color: $(if ($Data.TPMPresent) { '#00c853' } else { '#ff1744' })">$(if ($Data.TPMPresent) { 'YES' } else { 'NO' })</span>
                    </div>
                    <div class="security-item">
                        <span class="security-label">TPM Ready</span>
                        <span class="security-value" style="color: $(if ($Data.TPMReady) { '#00c853' } else { '#ff1744' })">$(if ($Data.TPMReady) { 'YES' } else { 'NO' })</span>
                    </div>
                    <div class="security-item">
                        <span class="security-label">Secure Boot</span>
                        <span class="security-value" style="color: $(if ($Data.SecureBoot -eq $true) { '#00c853' } else { '#ff9100' })">$(if ($Data.SecureBoot -eq $true) { 'ENABLED' } else { $Data.SecureBoot })</span>
                    </div>
                    <div class="security-item">
                        <span class="security-label">Defender</span>
                        <span class="security-value" style="color: $(if ($Data.DefenderEnabled) { '#00c853' } else { '#ff1744' })">$(if ($Data.DefenderEnabled) { 'ENABLED' } else { 'DISABLED' })</span>
                    </div>
                    <div class="security-item">
                        <span class="security-label">Real-Time Protection</span>
                        <span class="security-value" style="color: $(if ($Data.RealTimeProtection) { '#00c853' } else { '#ff1744' })">$(if ($Data.RealTimeProtection) { 'ON' } else { 'OFF' })</span>
                    </div>
                </div>
                $(if ($Data.PhysicalDisks.Count -gt 0) {
                    "<h4>Physical Disk Health</h4><table class='data-table'><thead><tr><th>Disk</th><th>Health</th><th>Type</th></tr></thead><tbody>"
                    foreach ($d in $Data.PhysicalDisks) {
                        $healthColor = if ($d.Health -eq "Healthy") { "#00c853" } else { "#ff1744" }
                        "<tr><td>$($d.Name)</td><td style='color: $healthColor'>$($d.Health)</td><td>$($d.Type)</td></tr>"
                    }
                    "</tbody></table>"
                })
            </div>
        </div>
    </div>
"@

    return $html
}

function Generate-KasperskyPage {
    param($Data)

    $kesStatus = if ($Data.KESService) { $Data.KESService.Status } else { "NOT FOUND" }
    $agentStatus = if ($Data.AgentService) { $Data.AgentService.Status } else { "NOT FOUND" }
    $overallColor = Get-StatusColor $Data.OverallStatus

    $html = @"
    <div class="page-content">
        <!-- Overall Status -->
        <div class="card status-card">
            <div class="card-header">
                <span class="card-icon">&#128737;</span>
                <h3>Kaspersky Security Status</h3>
                <span class="status-badge large" style="background: $overallColor">$($Data.OverallStatus)</span>
            </div>
        </div>

        <!-- KES Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128737;</span>
                <h3>Endpoint Security</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $kesStatus)">$kesStatus</span>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">KES Version</span><span class="value">$($Data.KESVersion)</span></div>
                    <div class="info-item"><span class="label">Version Source</span><span class="value">$($Data.KESVersionSource)</span></div>
                    <div class="info-item"><span class="label">Service Name</span><span class="value">$(if ($Data.KESService) { $Data.KESService.Name } else { 'N/A' })</span></div>
                    <div class="info-item"><span class="label">AVP Path</span><span class="value small">$($Data.AvpPath)</span></div>
                </div>
            </div>
        </div>

        <!-- Network Agent Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128257;</span>
                <h3>Network Agent</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $agentStatus)">$agentStatus</span>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Agent Version</span><span class="value">$($Data.AgentVersion)</span></div>
                    <div class="info-item"><span class="label">Version Source</span><span class="value">$($Data.AgentVersionSource)</span></div>
                    <div class="info-item"><span class="label">Service Name</span><span class="value">$(if ($Data.AgentService) { $Data.AgentService.Name } else { 'N/A' })</span></div>
                    <div class="info-item"><span class="label">klnagchk Path</span><span class="value small">$($Data.KlnagchkPath)</span></div>
                </div>
            </div>
        </div>

        <!-- KSC Connection Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128421;</span>
                <h3>KSC Server Connection</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $Data.KSCConnection)">$($Data.KSCConnection)</span>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Administration Server</span><span class="value">$($Data.AdminServer)</span></div>
                    <div class="info-item"><span class="label">Last Synchronization</span><span class="value">$($Data.LastSync)</span></div>
                    $(if ($Data.TimeSinceConnection) { "<div class='info-item'><span class='label'>Time Since Connection</span><span class='value'>$($Data.TimeSinceConnection)</span></div>" })
                </div>
            </div>
        </div>

        <!-- License Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128273;</span>
                <h3>License</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $Data.LicenseStatus)">$($Data.LicenseStatus)</span>
            </div>
        </div>

        <!-- Connectivity Card -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#127760;</span>
                <h3>Connectivity</h3>
                <span class="status-badge" style="background: $(Get-StatusColor $Data.InternetAccess)">$($Data.InternetAccess)</span>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Kaspersky Internet Access</span><span class="value">$($Data.InternetAccess)</span></div>
                    <div class="info-item"><span class="label">Target</span><span class="value">activation-v2.kaspersky.com:443</span></div>
                </div>
            </div>
        </div>
    </div>
"@

    return $html
}

function Generate-BatteryPage {
    param($Data)

    $healthColor = $Data.StatusColor
    $circumference = 2 * [math]::PI * 54
    $dashOffset = $circumference * (1 - ($Data.DisplayHealth / 100))

    $html = @"
    <div class="page-content">
        <!-- Battery Health Gauge -->
        <div class="card gauge-card">
            <div class="card-header">
                <span class="card-icon">&#128267;</span>
                <h3>Battery Health</h3>
                <span class="status-badge large" style="background: $healthColor">$($Data.Status)</span>
            </div>
            <div class="card-body">
                <div class="gauge-container">
                    <svg class="gauge" viewBox="0 0 120 120">
                        <circle class="gauge-bg" cx="60" cy="60" r="54" />
                        <circle class="gauge-fill" cx="60" cy="60" r="54"
                            stroke="$healthColor"
                            stroke-dasharray="$circumference"
                            stroke-dashoffset="$dashOffset"
                            transform="rotate(-90 60 60)" />
                    </svg>
                    <div class="gauge-text">
                        <span class="gauge-value">$([math]::Round($Data.DisplayHealth))%</span>
                        <span class="gauge-label">Health</span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Battery Details -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128267;</span>
                <h3>Battery Details</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Design Capacity</span><span class="value">$($Data.DesignCapacity.ToString('N0')) mWh</span></div>
                    <div class="info-item"><span class="label">Full Charge Capacity</span><span class="value">$($Data.FullCapacity.ToString('N0')) mWh</span></div>
                    <div class="info-item"><span class="label">Actual Health</span><span class="value">$($Data.Health.ToString('N2'))%</span></div>
                    <div class="info-item"><span class="label">Display Health</span><span class="value">$($Data.DisplayHealth.ToString('N0'))%</span></div>
                    <div class="info-item"><span class="label">Status</span><span class="value" style="color: $healthColor">$($Data.Status)</span></div>
                </div>
            </div>
        </div>

        <!-- Report Path -->
        <div class="card">
            <div class="card-header">
                <span class="card-icon">&#128196;</span>
                <h3>Report</h3>
            </div>
            <div class="card-body">
                <div class="info-grid">
                    <div class="info-item"><span class="label">Battery Report</span><span class="value small">$($Data.ReportPath)</span></div>
                </div>
            </div>
        </div>
    </div>
"@

    return $html
}

# ================================================================
# MAIN HTML TEMPLATE
# ================================================================

function Generate-FullHtml {
    param($DeviceData, $KasperskyData, $BatteryData)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $devicePage = Generate-DevicePage -Data $DeviceData
    $kasperskyPage = Generate-KasperskyPage -Data $KasperskyData
    $batteryPage = Generate-BatteryPage -Data $BatteryData

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <title>Device Info Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            min-height: 100vh;
        }

        .header {
            background: linear-gradient(135deg, #161b22 0%, #1c2333 100%);
            border-bottom: 1px solid #30363d;
            padding: 16px 24px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            position: sticky;
            top: 0;
            z-index: 100;
        }

        .header-left {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .header-icon {
            font-size: 28px;
        }

        .header h1 {
            font-size: 20px;
            font-weight: 600;
            color: #f0f6fc;
        }

        .header-right {
            display: flex;
            align-items: center;
            gap: 16px;
            font-size: 13px;
            color: #8b949e;
        }

        .header-right span {
            display: flex;
            align-items: center;
            gap: 4px;
        }

        .tab-bar {
            background: #161b22;
            border-bottom: 1px solid #30363d;
            padding: 0 24px;
            display: flex;
            gap: 4px;
        }

        .tab {
            padding: 12px 24px;
            cursor: pointer;
            border: none;
            background: transparent;
            color: #8b949e;
            font-size: 14px;
            font-weight: 500;
            border-bottom: 2px solid transparent;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .tab:hover {
            color: #f0f6fc;
            background: rgba(255,255,255,0.03);
        }

        .tab.active {
            color: #58a6ff;
            border-bottom-color: #58a6ff;
        }

        .tab-icon {
            font-size: 16px;
        }

        .page {
            display: none;
            padding: 24px;
            max-width: 1400px;
            margin: 0 auto;
        }

        .page.active {
            display: block;
        }

        .page-content {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
        }

        .card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 12px;
            overflow: hidden;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .card:hover {
            border-color: #58a6ff;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }

        .card-header {
            padding: 16px 20px;
            border-bottom: 1px solid #30363d;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .card-icon {
            font-size: 20px;
        }

        .card-header h3 {
            font-size: 15px;
            font-weight: 600;
            color: #f0f6fc;
            flex: 1;
        }

        .card-body {
            padding: 16px 20px;
        }

        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }

        .info-item {
            display: flex;
            flex-direction: column;
            gap: 4px;
        }

        .info-item .label {
            font-size: 11px;
            color: #8b949e;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .info-item .value {
            font-size: 14px;
            color: #f0f6fc;
            font-weight: 500;
        }

        .info-item .value.small {
            font-size: 12px;
            color: #8b949e;
            word-break: break-all;
        }

        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .status-badge.large {
            padding: 6px 16px;
            font-size: 13px;
        }

        .data-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 8px;
        }

        .data-table th {
            text-align: left;
            padding: 8px 12px;
            font-size: 11px;
            color: #8b949e;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border-bottom: 1px solid #30363d;
        }

        .data-table td {
            padding: 8px 12px;
            font-size: 13px;
            color: #c9d1d9;
            border-bottom: 1px solid #21262d;
        }

        .data-table tr:hover td {
            background: rgba(255,255,255,0.02);
        }

        .security-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }

        .security-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 12px;
            background: #0d1117;
            border-radius: 8px;
            border: 1px solid #21262d;
        }

        .security-label {
            font-size: 12px;
            color: #8b949e;
        }

        .security-value {
            font-size: 13px;
            font-weight: 600;
        }

        .progress-bar {
            width: 100%;
            height: 6px;
            background: #21262d;
            border-radius: 3px;
            overflow: hidden;
            display: inline-block;
            vertical-align: middle;
            margin-right: 8px;
        }

        .progress-fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.3s ease;
        }

        .progress-text {
            font-size: 12px;
            color: #8b949e;
        }

        .no-data {
            color: #8b949e;
            font-style: italic;
            padding: 12px 0;
        }

        .gauge-card {
            grid-column: 1 / -1;
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        .gauge-container {
            position: relative;
            width: 200px;
            height: 200px;
            margin: 20px 0;
        }

        .gauge {
            width: 100%;
            height: 100%;
        }

        .gauge-bg {
            fill: none;
            stroke: #21262d;
            stroke-width: 10;
        }

        .gauge-fill {
            fill: none;
            stroke-width: 10;
            stroke-linecap: round;
            transition: stroke-dashoffset 1s ease;
        }

        .gauge-text {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            text-align: center;
        }

        .gauge-value {
            display: block;
            font-size: 36px;
            font-weight: 700;
            color: #f0f6fc;
        }

        .gauge-label {
            display: block;
            font-size: 12px;
            color: #8b949e;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .status-card {
            grid-column: 1 / -1;
            text-align: center;
            padding: 20px;
        }

        .mac-line {
            padding: 12px 20px;
            font-size: 14px;
            color: #c9d1d9;
            background: #0d1117;
            border-radius: 8px;
            margin-bottom: 12px;
            border: 1px solid #21262d;
            white-space: nowrap !important;
            word-break: keep-all !important;
            overflow-x: auto;
            display: block;
            width: 100%;
            box-sizing: border-box;
        }

        .mac-line strong {
            color: #58a6ff;
            font-weight: 600;
            font-family: 'Consolas', 'Monaco', monospace;
            letter-spacing: 0.5px;
        }

        h4 {
            font-size: 13px;
            color: #8b949e;
            margin: 16px 0 8px 0;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        @media (max-width: 768px) {
            .page-content {
                grid-template-columns: 1fr;
            }
            .info-grid {
                grid-template-columns: 1fr;
            }
            .security-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <span class="header-icon">&#128421;</span>
            <h1>Device Info Dashboard</h1>
        </div>
        <div class="header-right">
            <span>&#128100; $($DeviceData.ComputerName)</span>
            <span>&#128197; $timestamp</span>
        </div>
    </div>

    <div class="tab-bar">
        <button class="tab active" onclick="showPage('device', this)">
            <span class="tab-icon">&#128421;</span> Device
        </button>
        <button class="tab" onclick="showPage('kaspersky', this)">
            <span class="tab-icon">&#128737;</span> Kaspersky
        </button>
        <button class="tab" onclick="showPage('battery', this)">
            <span class="tab-icon">&#128267;</span> Battery
        </button>
    </div>

    <div id="page-device" class="page active">
        $devicePage
    </div>

    <div id="page-kaspersky" class="page">
        $kasperskyPage
    </div>

    <div id="page-battery" class="page">
        $batteryPage
    </div>

    <script>
        function showPage(pageName, tabElement) {
            // Hide all pages
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));

            // Show selected page
            document.getElementById('page-' + pageName).classList.add('active');
            tabElement.classList.add('active');
        }
    </script>
</body>
</html>
"@

    return $html
}

# ================================================================
# MAIN EXECUTION
# ================================================================

Clear-Host
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "           DEVICE INFO DASHBOARD" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Collecting device information..." -ForegroundColor Yellow

$deviceData = Get-DeviceInfo
Write-Host "  [OK] Device info collected" -ForegroundColor Green

Write-Host "Collecting Kaspersky information..." -ForegroundColor Yellow
$kasperskyData = Get-KasperskyInfo
Write-Host "  [OK] Kaspersky info collected" -ForegroundColor Green

Write-Host "Collecting battery information..." -ForegroundColor Yellow
$batteryData = Get-BatteryInfo
Write-Host "  [OK] Battery info collected" -ForegroundColor Green

Write-Host ""
Write-Host "Generating dashboard..." -ForegroundColor Yellow

$html = Generate-FullHtml -DeviceData $deviceData -KasperskyData $kasperskyData -BatteryData $batteryData

$outputPath = "$env:USERPROFILE\Desktop\DeviceDashboard.html"
$html | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "  [OK] Dashboard saved to: $outputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Opening dashboard in browser..." -ForegroundColor Cyan

Start-Process $outputPath

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "Dashboard complete!" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Cyan
