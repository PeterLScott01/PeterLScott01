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
if ([string]::IsNullOrWhiteSpace($target)) {
    $target = $env:COMPUTERNAME
}

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

# Gather system info via CIM/WMI
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $target -ErrorAction Stop
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $target -ErrorAction Stop
    $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $target -ErrorAction Stop | Select-Object -First 1
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ComputerName $target -ErrorAction Stop
} catch {
    Write-Error "Failed to query system information from '$target'. $_"
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
