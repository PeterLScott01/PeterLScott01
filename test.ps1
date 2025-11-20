Clear-Host
<#
.SYNOPSIS
    Prompts for a hostname or IP and displays system information.

.DESCRIPTION
    This script prompts the user for a computer name or IP address, attempts to resolve it,
    and then queries the remote (or local) system for:
      - Computer name
      - IP address(es)
      - Total physical memory (GB)
      - Number of logical processors (CPUs)
      - Free and total space on local fixed drives

    Requires appropriate permissions and network connectivity for remote queries.

.NOTES
    Run PowerShell as Administrator when querying remote systems if needed.
    For remote systems, ensure WinRM/Remote WMI is enabled and accessible.
#>

# Prompt for target computer or IP
$target = Read-Host -Prompt "Enter hostname or IP address (leave blank for local)"
if (-not $target) { $target = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'localhost' } }

# Try to resolve and capture IPs
try {
    $dnsEntry = [System.Net.Dns]::GetHostEntry($target)
    $ipAddresses = $dnsEntry.AddressList
        | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }
        | ForEach-Object { $_.ToString() }
} catch {
    # If resolution fails, still attempt queries using the provided target
    $ipAddresses = @()
}

# Helper to format bytes to GB with 2 decimals
function Convert-ToGB {
    param([long]$Bytes)
    if ($null -eq $Bytes) { return $null }
    return [math]::Round($Bytes / 1GB, 2)
}

# Local-only fallback using .NET APIs (no CIM/WMI)
function Get-LocalSystemInfoDotNet {
    param([string]$TargetName)

    # Computer name
    $compName = if ($TargetName) { $TargetName } else { $env:COMPUTERNAME }

    # IP addresses (IPv4)
    $ips = @()
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($compName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.ToString() }
    } catch { $ips = @() }

    # Total physical memory via PerformanceCounter or WMI-less approach
    # Use ComputerInfo when available (Windows PowerShell 5.1+ has this type)
    $totalMemGB = $null
    try {
        $ci = Get-ComputerInfo -ErrorAction Stop
        if ($ci.CsTotalPhysicalMemory) { $totalMemGB = Convert-ToGB -Bytes ([int64]$ci.CsTotalPhysicalMemory) }
    } catch {
        # Fallback: Use GC memory info (this is not total physical, but avoids failure)
        try {
            $mem = [System.GC]::GetGCMemoryInfo()
            $totalMemGB = Convert-ToGB -Bytes ([int64]$mem.TotalAvailableMemoryBytes)
        } catch { $totalMemGB = $null }
    }

    # CPU count
    $cpuCount = [Environment]::ProcessorCount

    # Drive info
    $drives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }

    $diskInfo = $drives | ForEach-Object {
        [pscustomobject]@{
            Drive       = $_.Name.TrimEnd('\\')
            FileSystem  = $_.DriveFormat
            SizeGB      = Convert-ToGB -Bytes ([int64]$_.TotalSize)
            FreeGB      = Convert-ToGB -Bytes ([int64]$_.AvailableFreeSpace)
            FreePercent = if ($_.TotalSize) { [math]::Round(($_.AvailableFreeSpace / $_.TotalSize) * 100, 1) } else { $null }
        }
    }

    return [pscustomobject]@{
        ComputerName = $compName
        IPAddresses  = if ($ips -and $ips.Count -gt 0) { $ips -join ", " } else { "(unresolved)" }
        TotalMemoryGB = $totalMemGB
        CPUCount      = $cpuCount
        DiskInfo      = $diskInfo
    }
}

# Gather system info using CIM if available, otherwise WMI
$useCim = $false
# Try to import CIM cmdlets (helps on PowerShell 7+)
try { Import-Module CimCmdlets -ErrorAction Stop } catch { }

if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { $useCim = $true }
elseif (-not (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
    Write-Host "CIM/WMI not available; falling back to local-only .NET collection." -ForegroundColor Yellow
    $localInfo = Get-LocalSystemInfoDotNet -TargetName $target

    Write-Host "" -ForegroundColor Cyan
    Write-Host "System Information for: $target (local .NET fallback)" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    [pscustomobject]@{
        ComputerName = $localInfo.ComputerName
        IPAddresses  = $localInfo.IPAddresses
        TotalMemoryGB = $localInfo.TotalMemoryGB
        CPUCount      = $localInfo.CPUCount
    } | Format-List

    Write-Host "" 
    Write-Host "Local Fixed Drives:" -ForegroundColor Yellow
    $localInfo.DiskInfo | Sort-Object Drive | Format-Table -AutoSize

    Write-Host "" 
    Write-Host "Done." -ForegroundColor Green
    return
}

try {
    if ($useCim) {
        $cs    = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $target -ErrorAction Stop
        $os    = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $target -ErrorAction Stop
        $cpu   = Get-CimInstance -ClassName Win32_Processor -ComputerName $target -ErrorAction Stop | Select-Object -First 1
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ComputerName $target -ErrorAction Stop
    }
    else {
        $cs    = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $target -ErrorAction Stop
        $os    = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $target -ErrorAction Stop
        $cpu   = Get-WmiObject -Class Win32_Processor -ComputerName $target -ErrorAction Stop | Select-Object -First 1
        $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 3" -ComputerName $target -ErrorAction Stop
    }
} catch {
    Write-Error "Failed to query system information from '$target'. $_"
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host " - If using CIM: Ensure WinRM is enabled/accessible on the target (Enable-PSRemoting), and firewall allows WS-Man." -ForegroundColor Yellow
    Write-Host " - If using WMI: Ensure RPC/DCOM is reachable and firewall permits WMI." -ForegroundColor Yellow
    Write-Host " - Try: Test-Connection -ComputerName $target -Count 1" -ForegroundColor Yellow
    exit 1
}

# Compute values
$computerName = $cs.Name
$totalMemoryGB = Convert-ToGB -Bytes $cs.TotalPhysicalMemory
$logicalProcessorCount = $cpu.NumberOfLogicalProcessors

$diskInfo = $disks | ForEach-Object {
    [pscustomobject]@{
        Drive        = $_.DeviceID
        FileSystem   = $_.FileSystem
        SizeGB       = Convert-ToGB -Bytes $_.Size
        FreeGB       = Convert-ToGB -Bytes $_.FreeSpace
        FreePercent  = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { $null }
    }
}

# Output summary
Write-Host "" -ForegroundColor Cyan
Write-Host "System Information for: $target" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan

$ipDisplay = if ($ipAddresses -and $ipAddresses.Count -gt 0) { $ipAddresses -join ", " } else { "(unresolved)" }

[pscustomobject]@{
    ComputerName = $computerName
    IPAddresses  = $ipDisplay
    TotalMemoryGB = $totalMemoryGB
    CPUCount      = $logicalProcessorCount
} | Format-List

Write-Host "" 
Write-Host "Local Fixed Drives:" -ForegroundColor Yellow
$diskInfo | Sort-Object Drive | Format-Table -AutoSize

Write-Host "" 
Write-Host "Done." -ForegroundColor Green
